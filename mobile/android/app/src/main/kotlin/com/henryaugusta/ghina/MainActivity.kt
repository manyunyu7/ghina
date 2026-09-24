package com.henryaugusta.ghina

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Hosts the small Ghina platform bridge (see lib/data/platform/platform_bridge.dart):
 *  - Android share target: ACTION_SEND / ACTION_SEND_MULTIPLE (text/..., image/...).
 *    Shared content:// images are copied into cacheDir/share_intake right away (the
 *    read grant dies with the intent); Dart moves them into app documents.
 *    Every share (cold start or while running) is queued until Dart listens on the
 *    share EventChannel, so none is lost.
 *  - App settings shortcut + "should show rationale" for the mic permission.
 *  - Offline speech support query / model download (Android 13+ RecognitionSupport).
 */
class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var shareSink: EventChannel.EventSink? = null
    private val pendingShares = mutableListOf<Map<String, Any?>>()
    private var fileSeq = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Restored (rotation / process death) or reopened from Recents: the share
        // was already handled — don't import it twice.
        val fromHistory = (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (savedInstanceState == null && !fromHistory) handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, SHARE_EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                shareSink = events
                val queued = pendingShares.toList()
                pendingShares.clear()
                queued.forEach { events?.success(it) }
            }

            override fun onCancel(arguments: Any?) {
                shareSink = null
            }
        })

        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                // Shares are delivered through the event channel (queued until
                // listened); kept for API symmetry.
                "share.initial" -> result.success(null)
                "app.openSettings" -> result.success(openAppSettings())
                "mic.shouldShowRationale" -> result.success(
                    shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)
                )
                "speech.support" -> speechSupport(
                    call.argument<String>("locale") ?: "id-ID"
                ) { result.success(it) }
                "speech.downloadModel" -> result.success(
                    downloadSpeechModel(call.argument<String>("locale") ?: "id-ID")
                )
                else -> result.notImplemented()
            }
        }
    }

    // --- share target --------------------------------------------------------------

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val type = intent.type ?: ""
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val texts = mutableListOf<String>()
        val streams = mutableListOf<Uri>()

        if (action == Intent.ACTION_SEND) {
            intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.let { texts.add(it) }
            streamExtra(intent)?.let { streams.add(it) }
        } else {
            intent.getCharSequenceArrayListExtra(Intent.EXTRA_TEXT)?.forEach { texts.add(it.toString()) }
            streamListExtra(intent)?.let { streams.addAll(it) }
        }
        // Some apps only put the URIs in ClipData.
        if (streams.isEmpty()) {
            intent.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { streams.add(it) }
            }
        }
        // Consume it so a later recreate with the same intent doesn't re-import.
        intent.action = null

        io.execute {
            val images = mutableListOf<String>()
            for (uri in streams.take(MAX_IMAGES)) {
                val mime = runCatching { contentResolver.getType(uri) }.getOrNull() ?: type
                when {
                    mime.startsWith("image/") -> copyToCache(uri, mime)?.let { images.add(it) }
                    mime.startsWith("text/") && texts.isEmpty() -> readText(uri)?.let { texts.add(it) }
                }
            }
            val payload = mapOf("subject" to subject, "texts" to texts, "images" to images)
            main.post { deliverShare(payload) }
        }
    }

    private fun deliverShare(payload: Map<String, Any?>) {
        val sink = shareSink
        if (sink != null) sink.success(payload) else pendingShares.add(payload)
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }

    private fun copyToCache(uri: Uri, mime: String): String? = runCatching {
        val dir = File(cacheDir, "share_intake").apply { mkdirs() }
        val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "jpg"
        val out = File(dir, "${System.currentTimeMillis()}_${fileSeq++}.$ext")
        var total = 0L
        contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { output ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > MAX_IMAGE_BYTES) throw IllegalStateException("too large")
                    output.write(buf, 0, n)
                }
            }
        } ?: return@runCatching null
        out.absolutePath
    }.getOrElse { null }

    private fun readText(uri: Uri): String? = runCatching {
        contentResolver.openInputStream(uri)?.use { input ->
            val bytes = input.readNBytesCompat(MAX_TEXT_BYTES)
            String(bytes, Charsets.UTF_8)
        }
    }.getOrNull()

    private fun java.io.InputStream.readNBytesCompat(max: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(8 * 1024)
        while (out.size() < max) {
            val n = read(buf, 0, minOf(buf.size, max - out.size()))
            if (n < 0) break
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    // --- settings ------------------------------------------------------------------

    private fun openAppSettings(): Boolean = runCatching {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    }.getOrDefault(false)

    // --- speech --------------------------------------------------------------------

    private fun speechSupport(locale: String, reply: (Map<String, Any?>) -> Unit) {
        val sdk = Build.VERSION.SDK_INT
        val available = runCatching { SpeechRecognizer.isRecognitionAvailable(this) }.getOrDefault(false)
        val onDevice = sdk >= 31 &&
            runCatching { SpeechRecognizer.isOnDeviceRecognitionAvailable(this) }.getOrDefault(false)
        val result = mutableMapOf<String, Any?>(
            "sdkInt" to sdk,
            "recognitionAvailable" to available,
            "onDeviceAvailable" to onDevice,
        )
        if (sdk < 33 || (!available && !onDevice)) {
            reply(result)
            return
        }
        val queries = mutableListOf<Pair<String, SpeechRecognizer>>()
        runCatching {
            if (available) queries.add("defaultService" to SpeechRecognizer.createSpeechRecognizer(this))
            if (onDevice) queries.add("onDeviceService" to SpeechRecognizer.createOnDeviceSpeechRecognizer(this))
        }
        if (queries.isEmpty()) {
            reply(result)
            return
        }
        var remaining = queries.size
        var replied = false
        fun finishOne() {
            remaining--
            if (remaining <= 0 && !replied) {
                replied = true
                reply(result)
            }
        }
        val timeout = Runnable {
            if (!replied) {
                replied = true
                reply(result)
            }
            queries.forEach { (_, r) -> runCatching { r.destroy() } }
        }
        main.postDelayed(timeout, 3000)
        val recognizeIntent = recognizeIntent(locale)
        for ((key, recognizer) in queries) {
            try {
                recognizer.checkRecognitionSupport(
                    recognizeIntent,
                    Executors.newSingleThreadExecutor(),
                    object : RecognitionSupportCallback {
                        override fun onSupportResult(support: RecognitionSupport) {
                            main.post {
                                result[key] = mapOf(
                                    "installed" to support.installedOnDeviceLanguages,
                                    "pending" to support.pendingOnDeviceLanguages,
                                    "supported" to support.supportedOnDeviceLanguages,
                                    "online" to support.onlineLanguages,
                                )
                                runCatching { recognizer.destroy() }
                                finishOne()
                            }
                        }

                        override fun onError(error: Int) {
                            main.post {
                                runCatching { recognizer.destroy() }
                                finishOne()
                            }
                        }
                    },
                )
            } catch (e: Exception) {
                runCatching { recognizer.destroy() }
                finishOne()
            }
        }
    }

    private fun downloadSpeechModel(locale: String): Boolean {
        if (Build.VERSION.SDK_INT < 33) return false
        return runCatching {
            val onDevice = SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            val recognizer = if (onDevice) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            } else {
                SpeechRecognizer.createSpeechRecognizer(this)
            }
            recognizer.triggerModelDownload(recognizeIntent(locale))
            // Give the service time to take the request before unbinding.
            main.postDelayed({ runCatching { recognizer.destroy() } }, 10_000)
            true
        }.getOrDefault(false)
    }

    private fun recognizeIntent(locale: String) = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val METHODS = "com.henryaugusta.ghina/platform"
        private const val SHARE_EVENTS = "com.henryaugusta.ghina/share"
        private const val MAX_IMAGES = 20
        private const val MAX_IMAGE_BYTES = 25L * 1024 * 1024
        private const val MAX_TEXT_BYTES = 100 * 1024
    }
}
