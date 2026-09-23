import '../../core/failure.dart';

final _colorRe = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Default palette (web `COLOR_PALETTE`).
const colorPalette = [
  '#6366f1',
  '#8b5cf6',
  '#ec4899',
  '#ef4444',
  '#f97316',
  '#f59e0b',
  '#eab308',
  '#84cc16',
  '#22c55e',
  '#10b981',
  '#14b8a6',
  '#06b6d4',
  '#0ea5e9',
  '#3b82f6',
  '#64748b',
];

/// Currencies accepted by the server.
const supportedCurrencies = ['IDR', 'USD', 'EUR', 'GBP', 'JPY', 'SGD', 'MYR'];

String requireName(String? v, {int max = 60, String field = 'name'}) {
  final s = (v ?? '').trim();
  if (s.isEmpty) throw ValidationFailure('Nama wajib diisi', field: field);
  if (s.length > max) {
    throw ValidationFailure(
      'Nama terlalu panjang (maks $max karakter)',
      field: field,
    );
  }
  return s;
}

double requirePositiveAmount(double? v, {String field = 'amount'}) {
  if (v == null || !v.isFinite || v <= 0) {
    throw ValidationFailure('Jumlah harus lebih dari 0', field: field);
  }
  return v;
}

String requireColor(String? v) {
  if (v == null || !_colorRe.hasMatch(v)) {
    throw const ValidationFailure('Warna tidak valid', field: 'color');
  }
  return v;
}

String requireCurrency(String? v) {
  if (v == null || !supportedCurrencies.contains(v)) {
    throw const ValidationFailure(
      'Mata uang tidak didukung',
      field: 'currency',
    );
  }
  return v;
}

/// Trim; empty → null. Enforces [max] length when given.
String? optionalText(String? v, {int? max, String field = 'note'}) {
  final s = v?.trim();
  if (s == null || s.isEmpty) return null;
  if (max != null && s.length > max) {
    throw ValidationFailure(
      'Catatan terlalu panjang (maks $max karakter)',
      field: field,
    );
  }
  return s;
}

/// Empty string → null.
String? optionalId(String? v) => (v == null || v.isEmpty) ? null : v;
