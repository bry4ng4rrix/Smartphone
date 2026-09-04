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

/// Un appareil connecté à un compte de la société (onglet "Appareils").
class CompanyDevice {
  CompanyDevice({
    required this.id,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    this.label,
    this.ipAddress,
    this.userAgent,
    this.lastSeen,
  });

  final int id;
  final String userName;
  final String userEmail;
  final String userRole;
  final String? label;
  final String? ipAddress;
  final String? userAgent;
  final DateTime? lastSeen;

  factory CompanyDevice.fromJson(Map<String, dynamic> json) {
    return CompanyDevice(
      id: asInt(json['id']),
      userName: asString(json['user_name']),
      userEmail: asString(json['user_email']),
      userRole: asString(json['user_role']),
      label: asStringOrNull(json['label']),
      ipAddress: asStringOrNull(json['ip_address']),
      userAgent: asStringOrNull(json['user_agent']),
      lastSeen: asDateOrNull(json['last_seen']),
    );
  }
}

/// Statut d'abonnement de la société (onglet "Abonnement", propriétaire
/// uniquement — §11 README).
class CompanySubscription {
  CompanySubscription({
    required this.status,
    this.daysLeftInTrial,
    this.isCurrentlyActive = false,
    this.offerName,
    this.offerDurationMonths,
  });

  final String status; // active | disabled | pending | trial | demo
  final int? daysLeftInTrial;
  final bool isCurrentlyActive;
  final String? offerName;
  final int? offerDurationMonths;

  factory CompanySubscription.fromJson(Map<String, dynamic> json) {
    final offer = json['offer'] as Map<String, dynamic>?;
    return CompanySubscription(
      status: asString(json['status'], 'pending'),
      daysLeftInTrial: asIntOrNull(json['days_left_in_trial']),
      isCurrentlyActive: asBool(json['is_currently_active']),
      offerName: offer != null ? asStringOrNull(offer['name']) : null,
      offerDurationMonths: offer != null ? asIntOrNull(offer['duration_months']) : null,
    );
  }
}

/// Une demande envoyée à Label Technology (activation, suppression
/// d'appareil) — historique affiché dans l'onglet "Abonnement"/"Appareils".
class CompanyRequest {
  CompanyRequest({required this.id, required this.requestType, required this.status, this.createdAt});

  final int id;
  final String requestType; // activation | device_deletion | payment | password_reset
  final String status; // pending | approved | rejected
  final DateTime? createdAt;

  factory CompanyRequest.fromJson(Map<String, dynamic> json) {
    return CompanyRequest(
      id: asInt(json['id']),
      requestType: asString(json['request_type']),
      status: asString(json['status']),
      createdAt: asDateOrNull(json['created_at']),
    );
  }
}
