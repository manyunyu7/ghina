/// Android share target (docs/notes.md → Capture paths): text / URL / image(s)
/// shared from another app become a new note with `source = "share"`.
library;

/// Max links kept per note (spec: `links` ≤ 20).
const kMaxSharedLinks = 20;

/// Max images taken from one share.
const kMaxSharedImages = 20;

/// What another app shared with Ghina, already normalised
/// (see [SharedPayload.normalize]).
final class SharedPayload {
  const SharedPayload({
    this.title,
    this.text,
    this.urls = const [],
    this.imagePaths = const [],
  });

  /// `EXTRA_SUBJECT` — e.g. the page title when sharing from a browser.
  final String? title;

  /// Body text with surrounding whitespace trimmed; null when the shared text
  /// was only link(s) (those are in [urls]) or nothing was shared.
  final String? text;

  /// http(s) links found in the shared text/subject, deduplicated, in order,
  /// at most [kMaxSharedLinks].
  final List<String> urls;

  /// Images copied into app storage (`<documents>/shared_images/…`) — safe to
  /// keep; move/import them into note photos and delete what you don't use.
  final List<String> imagePaths;

  bool get isEmpty =>
      (title == null || title!.isEmpty) &&
      (text == null || text!.isEmpty) &&
      urls.isEmpty &&
      imagePaths.isEmpty;

  /// Suggested note body: the text, or the title when only a link was shared.
  String get suggestedBody => text ?? '';

  /// Builds a payload from the raw intent extras.
  static SharedPayload normalize({
    String? subject,
    Iterable<String> texts = const [],
    Iterable<String> imagePaths = const [],
  }) {
    final title = _clean(subject);
    final parts = texts.map(_clean).whereType<String>().toList();
    final joined = parts.isEmpty ? null : parts.join('\n\n');

    final urls = <String>[];
    void addAll(String? s) {
      if (s == null) return;
      for (final u in extractUrls(s)) {
        if (urls.length >= kMaxSharedLinks) return;
        if (!urls.contains(u)) urls.add(u);
      }
    }

    addAll(joined);
    addAll(title);

    String? text = joined;
    if (text != null && _onlyLinks(text)) text = null;
    final images = <String>[];
    for (final p in imagePaths) {
      if (p.trim().isEmpty || images.contains(p)) continue;
      if (images.length >= kMaxSharedImages) break;
      images.add(p);
    }
    return SharedPayload(
      title: title == text ? null : title,
      text: text,
      urls: List.unmodifiable(urls),
      imagePaths: List.unmodifiable(images),
    );
  }

  @override
  String toString() =>
      'SharedPayload(title: $title, text: $text, urls: $urls, images: $imagePaths)';
}

String? _clean(String? s) {
  if (s == null) return null;
  final t = s.replaceAll('\r\n', '\n').trim();
  return t.isEmpty ? null : t;
}

final _urlRe = RegExp(
  r'''(?:https?://|www\.)[^\s<>"'`]+''',
  caseSensitive: false,
);

const _trailing = '.,;:!?\'"»”’>';

/// http(s) URLs in [text], in order (not deduplicated). `www.x.y` gets an
/// `https://` prefix; trailing punctuation and unbalanced closing brackets are
/// stripped ("lihat https://a.b/c)." → `https://a.b/c`).
List<String> extractUrls(String text) {
  final out = <String>[];
  for (final m in _urlRe.allMatches(text)) {
    var u = m.group(0)!;
    var changed = true;
    while (changed && u.isNotEmpty) {
      changed = false;
      final last = u[u.length - 1];
      if (_trailing.contains(last)) {
        u = u.substring(0, u.length - 1);
        changed = true;
        continue;
      }
      for (final (open, close) in const [('(', ')'), ('[', ']'), ('{', '}')]) {
        if (last == close &&
            close.allMatches(u).length > open.allMatches(u).length) {
          u = u.substring(0, u.length - 1);
          changed = true;
          break;
        }
      }
    }
    if (u.toLowerCase().startsWith('www.')) u = 'https://$u';
    final uri = Uri.tryParse(u);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) continue;
    out.add(u);
  }
  return out;
}

/// True when [text] has nothing but URLs (and separators/punctuation).
bool _onlyLinks(String text) {
  if (extractUrls(text).isEmpty) return false;
  final rest = text
      .replaceAll(_urlRe, '')
      .replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
  return rest.isEmpty;
}

/// Receives shares from other apps.
abstract interface class ShareIntake {
  /// Shares, including the one that cold-started the app (delivered once to the
  /// first listener). Broadcast; payloads are never empty.
  Stream<SharedPayload> get payloads;

  Future<void> dispose();
}
