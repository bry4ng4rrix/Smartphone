import 'json_utils.dart';

/// Onglet "Réinit. mots de passe" du module Super Admin — demandes des
/// gérants/employés d'une société ayant oublié leur mot de passe, résolues
/// par un admin (§11 Smartreadme.md, infrastructure SaaS conservée).
class PasswordResetRequest {
  PasswordResetRequest({
    required this.id,
    required this.status,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    this.magasinName,
    this.createdAt,
    this.resolvedAt,
  });

  final int id;
  final String status; // pending | approved | rejected
  final String userName;
  final String userEmail;
  final String userRole;
  final String? magasinName;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  factory PasswordResetRequest.fromJson(Map<String, dynamic> json) {
    return PasswordResetRequest(
      id: asInt(json['id']),
      status: asString(json['status']),
      userName: asString(json['user_name']),
      userEmail: asString(json['user_email']),
      userRole: asString(json['user_role']),
      magasinName: asStringOrNull(json['magasin_name']),
      createdAt: asDateOrNull(json['created_at']),
      resolvedAt: asDateOrNull(json['resolved_at']),
    );
  }
}

