/// Petits convertisseurs tolérants utilisés par tous les `fromJson` des
/// modèles : DRF sérialise les `DecimalField` en string, certains champs
/// sont optionnels selon le rôle (serializers restreints préparateur/livreur).
library;

double? asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

double asDouble(dynamic v, [double fallback = 0]) => asDoubleOrNull(v) ?? fallback;

int? asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  return null;
}

int asInt(dynamic v, [int fallback = 0]) => asIntOrNull(v) ?? fallback;

bool asBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true' || v == '1';
  if (v is num) return v != 0;
  return fallback;
}

String asString(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

String? asStringOrNull(dynamic v) => v?.toString();

DateTime? asDateOrNull(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}
