/// The signed-in user (`user` object of the auth endpoints).
final class AppUser {
  const AppUser({
    required this.id,
    this.name,
    this.email,
    this.image,
    required this.currency,
    required this.syncEpoch,
  });

  final String id;
  final String? name;
  final String? email;
  final String? image;

  /// ISO code, e.g. `IDR`. Format money with this.
  final String currency;
  final String syncEpoch;

  /// First name or email prefix, for greetings.
  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n.split(RegExp(r'\s+')).first;
    final e = email;
    if (e != null && e.contains('@')) return e.split('@').first;
    return 'Kamu';
  }

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.image == image &&
      other.currency == currency &&
      other.syncEpoch == syncEpoch;

  @override
  int get hashCode => Object.hash(id, name, email, image, currency, syncEpoch);

  @override
  String toString() => 'AppUser($id, $email, $currency)';
}
