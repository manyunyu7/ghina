# Platform services for Notes (voice, dictation, share target)

Spec: `docs/notes.md`, sections **Voice notes** and **Capture paths**.

| Layer | Path |
|---|---|
| Ports (pure interfaces + value types) | `lib/domain/services/` (`services.dart` barrel) |
| Implementations + no-ops + fakes | `lib/data/platform/` (`platform.dart` barrel) |
| Riverpod providers / controllers | `lib/presentation/state/platform/` (`platform_state.dart` barrel) |
| Native bridge | `android/app/src/main/kotlin/com/henryaugusta/ghina/MainActivity.kt` |

Packages: `record` 7.1.x (recording), `just_audio` 0.10.x (playback), `speech_to_text` 7.5.x
(dictation), `fake_async` (dev, tests). The share target uses **no plugin** (see below).

Every service provider is overridable. On Android/iOS the production implementation is used;
on other platforms and under `flutter test` the provider falls back to a no-op
(`Noop*`). For tests use the scriptable fakes in `fakes.dart` (`FakeVoiceRecorder`,
`FakeSpeechTranscriber`, `FakeMicrophonePermission`, `FakeShareIntake`).

---

## 1. UX contract: "Rekam suara" vs "Dikte" (read this before building the UI)

**Recording audio and live speech recognition cannot run at the same time — the UI has two
separate modes.**

Why:

- Android `SpeechRecognizer` runs in another process (Google app / Android System
  Intelligence) and opens the microphone itself. With our own `AudioRecord` open at the same
  time, Android's capture policy gives the mic to one client only; the other gets silence or
  `ERROR_AUDIO`/`ERROR_RECOGNIZER_BUSY`. On MediaTek devices (Infinix, Tecno) the recognizer
  usually fails outright.
- Neither `speech_to_text` nor the platform APIs can transcribe an **existing audio file** on
  Android (`SpeechRecognizer` only listens to the mic; the Android 13 `EXTRA_AUDIO_SOURCE`
  stream input isn't exposed by any plugin and is not honoured by every recognizer). So
  "record now, transcribe the clip later on-device" is not possible in v1.
- iOS could technically do both on one `AVAudioSession`, but it would be a different UX from
  Android for little value — we keep one contract.

The contract the UI must implement:

| Mode | Button (ID) | Controller | Output |
|---|---|---|---|
| **Voice clip** | "Rekam suara" (tap to toggle, or hold-to-record; long-press on the Notes FAB starts it immediately) | `voiceRecorderControllerProvider` | `VoiceRecording` → note attachment (audio, `transcript = null`) |
| **Dictation** | "Dikte" (mic icon in the editor toolbar) | `dictationControllerProvider` | text inserted into the note body at the cursor |

- Starting one **cancels/stops the other** automatically (one mic owner): starting a recording
  cancels an active dictation; starting dictation *stops* (keeps) an active recording.
- The clip's `transcript` field (spec) stays empty in v1 on Android; the user can type one
  or dictate into the body. Do **not** offer "Transkrip" on an existing clip.
- If dictation is unavailable, the "Dikte" button still shows but tapping it shows
  `DictationState.hint` (Indonesian) — voice clips always work.

### Voice clip — `voiceRecorderControllerProvider` (auto-dispose)

State machine: `idle → starting → recording → stopping → idle(lastRecording)`, or `error`.

```dart
final s = ref.watch(voiceRecorderControllerProvider);
final c = ref.read(voiceRecorderControllerProvider.notifier);

await c.start();              // asks for mic permission on first use
final clip = await c.stop();  // VoiceRecording? (null when < 0.3 s / empty)
await c.cancel();             // discard while recording
c.takeRecording();            // clip produced by auto-stop / hold-release race
await c.discardRecording();   // delete the finished clip file
```

- `s.elapsed`, `s.remaining`, `s.progress` (0..1 of 10 min), `s.levels` (last 48 levels 0..1 —
  draw as waveform bars).
- **Auto-stop at 10 min** (`maxVoiceDurationProvider`): state becomes `idle` with
  `lastRecording != null && autoStopped == true` — listen for it and save the clip:
  ```dart
  ref.listen(voiceRecorderControllerProvider, (_, s) {
    if (s.autoStopped && s.lastRecording != null) attach(c.takeRecording()!);
  });
  ```
- Hold-to-record: call `start()` on press, `stop()` on release. A release while still
  `starting` is handled (it stops right after start; the result lands in `lastRecording`).
- Errors: `s.error` (`permission` / `busy` / `unsupported` / `failed`). For `permission`
  check `s.permission == MicPermissionStatus.permanentlyDenied` → show "Buka Pengaturan"
  (`c.openSettings()`).
- Disposing the provider (sheet closed) discards an unfinished clip — keep the provider
  watched while the recorder UI is visible.

Files: AAC-LC `.m4a`, mono, 64 kbps, 44.1 kHz (MIME `audio/mp4`), stored in
`<app documents>/voice/<uuid>.m4a` (persistent, not temp). ~4.8 MB per 10 min (< 20 MB upload
cap). 44.1 kHz rather than 16 kHz because every Android AAC encoder supports it (MediaTek
encoders sometimes renegotiate low rates) and playback sounds natural; any future server-side
ASR resamples to 16 kHz without loss in the speech band. The data layer owns the note
attachment row and upload; this layer only produces the file (`VoiceRecording.path`,
`duration`, `sizeBytes`, `mimeType`).

### Playback — `voicePlayerControllerProvider` (auto-dispose, one shared player)

```dart
final p = ref.watch(voicePlayerControllerProvider);
final c = ref.read(voicePlayerControllerProvider.notifier);
c.toggle(clip.id, filePath: clip.localPath, url: clip.remoteUrl, headers: authHeaders);
p.isPlaying(clip.id); p.positionOf(clip.id); p.duration;  // Slider → c.seek(d)
```

Playing another clip stops the current one. Local file wins; if it fails and a URL is given,
it falls back to streaming. `just_audio` was chosen over `audioplayers` for its precise
position/duration streams (scrubbing), request headers for authenticated URLs, and accurate
seeking on ExoPlayer.

### Dictation — `dictationControllerProvider` (auto-dispose)

```dart
final d = ref.watch(dictationControllerProvider);
final c = ref.read(dictationControllerProvider.notifier);
await c.start();                 // false → see d.phase (unavailable + d.hint, or error)
d.committed / d.partial / d.text // show partial greyed while listening
final text = await c.stop();     // waits for the final result (≤ 3 s)
insertAtCursor(c.takeText());    // returns + clears
```

- Continuous: Android ends a recognizer session after a few seconds of silence; the
  controller transparently starts a new one (`phase: restarting` for ~250 ms) until the user
  presses stop. After 3 consecutive sessions without words it stops by itself (`idle`).
- Partial results replace each other within a session; finals are appended with a space.
  Late duplicate finals are ignored.
- Fatal errors (network, language unavailable, permission, busy, audio) → `phase: error`,
  `d.error.kind`; text recognised so far is kept.
- `c.cancel()` drops the live partial, keeps committed text.

### Offline availability & fallback hint

`speechAvailabilityProvider` (and `DictationState.availability`) → `SpeechAvailability`:

| `offline` | Meaning | Dikte allowed (`dictationAllowsNetworkProvider = false`, default) |
|---|---|---|
| `installed` | `id-ID` offline model installed (checked via Android 13+ `SpeechRecognizer.checkRecognitionSupport`) | yes — fully on-device |
| `unknown` | Android ≤ 12, or recognizer doesn't answer the query (common on non-Pixel) | yes, best effort (hint shown) |
| `downloadable` | supported offline but not downloaded / download pending | no → hint + button "Unduh" → `c.downloadOfflineModel()` (Android 13+ `triggerModelDownload`) |
| `unsupported` | no offline model for `id-ID` on this device | no → hint; voice clip only |
| `recognizerAvailable == false` | no speech service at all | no |

Spec says no cloud transcription in v1, so `dictationAllowsNetworkProvider` defaults to
`false`. Override it to `true` to allow Google's network recognizer when no offline pack
exists. The transcriber forces the dedicated on-device service (`onDevice: true`) only when
that service really has `id-ID` installed; otherwise it uses the default recognizer (on
Infinix/Tecno: the Google app), which uses its offline pack when installed and — if the phone
is online — may still use the network. **We cannot fully prevent that for `unknown`;** it is a
limitation of the `speech_to_text` plugin and the Google recognizer.

**Infinix Android 13/14 expectation:** no dedicated on-device service
(`isOnDeviceRecognitionAvailable == false`); the Google app is the recognizer. If the user has
installed "Bahasa Indonesia" under *Google app › Setelan › Suara › Pengenalan ucapan offline*
(menu path varies by Google-app version/ROM), dictation works offline; the support query often
returns nothing → `unknown` → allowed with the hint
"Dikte memakai layanan suara perangkat. Agar bisa offline, pasang paket "Bahasa Indonesia"…".
If the Google app is disabled/removed (some Transsion ROMs ship with "Go" variants),
`recognizerAvailable` is false.

---

## 2. Android share target

Intent filters on `MainActivity` (`AndroidManifest.xml`): `SEND` `text/plain`, `SEND`
`image/*`, `SEND_MULTIPLE` `image/*`, `SEND_MULTIPLE` `text/plain`, label "Catatan Ghina".

**Why no `receive_sharing_intent`:** its 1.9 release is Swift-Package-Manager-only on iOS and
this project's iOS target doesn't use SPM (it breaks `pub get`/iOS builds), and we only need
Android. The native part is ~150 lines in `MainActivity.kt`:

- `launchMode` changed `singleTop → singleTask`, so a share always reaches the single running
  instance (`onNewIntent`) instead of spawning a second Flutter engine (and a second database
  connection) inside the sender's task. After sharing, Back returns to Ghina's previous screen,
  not to the sender app.
- Shared `content://` images are copied into `cacheDir/share_intake/` on a background thread
  right away (read grants expire with the intent); max 20 images, 25 MB each. A shared
  `text/*` file is read as text (≤ 100 KB).
- Every share (the cold-start one and ones received while running) is **queued natively until
  Dart listens** on the `com.henryaugusta.ghina/share` event channel — nothing is lost before
  the UI is ready. Restored activities / launches from Recents don't re-import.

Dart: `ChannelShareIntake` moves the images into `<app documents>/shared_images/` and emits a
normalised `SharedPayload`:

```dart
SharedPayload {
  String? title;          // EXTRA_SUBJECT (e.g. page title from a browser)
  String? text;           // trimmed body; null if the text was only link(s)
  List<String> urls;      // http(s)/www links from text+subject, deduped, ≤ 20
  List<String> imagePaths;// files in app storage — import into note photos
}
```

`pendingShareProvider` (kept alive, FIFO): `state` = oldest unhandled share or null;
`.notifier.take()` pops it; `.clear()` drops all (sign-out).

### Wiring hook for the UI agent (router/app files are not owned by this layer)

Add **one** listener in the signed-in app shell (the widget that wraps the authenticated
routes — e.g. the `ShellRoute` builder in `lib/app/router.dart` or the home scaffold), so that
`pendingShareProvider` is created at startup and survives navigation:

```dart
// In the shell's ConsumerState.build (or a small ConsumerWidget wrapper around the shell):
ref.listen<SharedPayload?>(pendingShareProvider, (_, next) {
  if (next == null) return;
  if (ref.read(currentUserProvider) == null) return;   // keep it pending until signed in
  final payload = ref.read(pendingShareProvider.notifier).take()!;
  // 1. create the note: source "share", title/body from payload.title/text,
  //    links from payload.urls, photos imported from payload.imagePaths
  // 2. open the "Catatan dari share" sheet (add label / → Tugas / → Konten)
  WidgetsBinding.instance.addPostFrameCallback((_) => openShareSheet(context, payload));
}, fireImmediately: true);   // fireImmediately → handles the cold-start share
```

Also re-check after sign-in (e.g. `ref.listen(currentUserProvider, …)` → if
`ref.read(pendingShareProvider) != null` run the same handler), and call
`ref.read(pendingShareProvider.notifier).clear()` on sign-out. Delete unused files in
`imagePaths` after importing (they live in `shared_images/`).

iOS share extension: out of scope (v1) — `shareIntakeProvider` is a no-op on iOS.

---

## 3. Permissions

| Platform | Declared | Asked when |
|---|---|---|
| Android | `RECORD_AUDIO` (manifest); `<queries>` for `android.speech.RecognitionService` (package visibility, Android 11+) | first tap on "Rekam suara" / "Dikte" (`MicrophonePermission.request()` via the controllers) |
| iOS | `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (Indonesian, `Info.plist`) | mic on first recording; speech on first dictation (plugin) |

`MicrophonePermission.status()/request()` → `granted | denied | permanentlyDenied |
unsupported`. Android "don't ask again" is detected right after a denial
(`shouldShowRequestPermissionRationale == false`); iOS treats any denial after the prompt as
permanent. `openAppSettings()` opens the app's settings page (Android; returns false on iOS
— tell the user to open Settings › Ghina).

---

## 4. Known device limits

- **No simultaneous record + transcribe** (see §1). No on-device transcription of saved clips.
- Android recognizer sessions stop after ~2–5 s of silence (system-imposed, not
  configurable on most devices) — handled by auto-restart; a short word can be lost at the
  boundary.
- Some Android ROMs / Google-app versions play a start sound at every recognizer session;
  with auto-restart that can mean a short beep after each pause. Not suppressible from the
  app — verify on the Infinix device.
- The offline check needs Android 13+ and a recognizer that implements
  `checkRecognitionSupport`; many OEM/Google-app builds return nothing → `unknown`.
- Recording pauses during a phone call (`record`'s interruption handling); the reported
  duration excludes the pause.
- Share: only the first 20 images; images > 25 MB are skipped; `SEND_MULTIPLE` with mixed
  types (image + video) keeps only the images. Videos/PDFs are not accepted (no filter).
- iOS: share target not implemented; `openAppSettings()` unsupported.
