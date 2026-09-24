/// Max photos per transaction (`docs/transaction-photos.md`).
const maxTransactionPhotos = 5;

/// One photo attached to a transaction: either uploaded ([url], a server path
/// like `/uploads/abc.jpg` — display with `AppConfig.resolveUrl`) or taken
/// offline and waiting for upload ([localPath], a device file — display with
/// `Image.file`). The sync engine uploads pending ones before pushing the
/// transaction and swaps them for their URL.
final class TransactionPhoto {
  const TransactionPhoto.remote(String this.url) : localPath = null;
  const TransactionPhoto.local(String this.localPath) : url = null;

  final String? url;
  final String? localPath;

  /// Not uploaded yet.
  bool get isPending => localPath != null;

  @override
  bool operator ==(Object other) =>
      other is TransactionPhoto &&
      other.url == url &&
      other.localPath == localPath;

  @override
  int get hashCode => Object.hash(url, localPath);

  @override
  String toString() => isPending
      ? 'TransactionPhoto.local($localPath)'
      : 'TransactionPhoto($url)';
}
