class UserModel {
  final String uid;
  final String name;
  final String email;
  final String avatarUrl;
  final String? partnerId;
  final String? pairId;
  final String? fcmToken;
  final String? telegramChatId;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.avatarUrl,
    this.partnerId,
    this.pairId,
    this.fcmToken,
    this.telegramChatId,
    this.lastSeenAt,
    this.createdAt,
    this.updatedAt,
  });

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? avatarUrl,
    String? partnerId,
    String? pairId,
    String? fcmToken,
    String? telegramChatId,
    DateTime? lastSeenAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      partnerId: partnerId ?? this.partnerId,
      pairId: pairId ?? this.pairId,
      fcmToken: fcmToken ?? this.fcmToken,
      telegramChatId: telegramChatId ?? this.telegramChatId,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatarUrl'] as String? ?? '',
      partnerId: json['partnerId'] as String?,
      pairId: json['pairId'] as String?,
      fcmToken: json['fcmToken'] as String?,
      telegramChatId: json['telegramChatId'] as String?,
      lastSeenAt: _parseDate(json['lastSeenAt']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is String) return DateTime.tryParse(val);
    try {
      // Handle Firebase Timestamp without importing it explicitly
      return (val.toDate() as DateTime);
    } catch (_) {
      return null;
    }
  }


  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'avatarUrl': avatarUrl,
      'partnerId': partnerId,
      'pairId': pairId,
      'fcmToken': fcmToken,
      'telegramChatId': telegramChatId,
      'lastSeenAt': lastSeenAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
