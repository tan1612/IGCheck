import 'package:cloud_firestore/cloud_firestore.dart';

class IGRequestModel {
  final String id;
  final String instagramUsername; // Acts as username for Instagram, UID/username for Facebook
  final String displayName;
  final String note;
  final String password;
  final String twoFactorKey;
  final String originalImageUrl;
  final String thumbnailImageUrl;
  final String originalImagePath;
  final String thumbnailImagePath;
  final int imageSizeBytes;
  final String senderId;
  final String receiverId;
  final String pairId;
  final String status; // pending, approved, rejected, needs_update, updated, cancelled
  final String feedback;
  final String lastUpdatedBy;
  final String lastAction; // created, updated_image, updated_info, approved, rejected, needs_update, feedback_added, resubmitted
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? reviewedAt;
  final String accountType; // 'instagram' or 'facebook'
  final int rejectionCount; // Number of times rejected

  IGRequestModel({
    required this.id,
    required this.instagramUsername,
    required this.displayName,
    required this.note,
    this.password = '',
    this.twoFactorKey = '',
    required this.originalImageUrl,
    required this.thumbnailImageUrl,
    required this.originalImagePath,
    required this.thumbnailImagePath,
    required this.imageSizeBytes,
    required this.senderId,
    required this.receiverId,
    required this.pairId,
    required this.status,
    required this.feedback,
    required this.lastUpdatedBy,
    required this.lastAction,
    this.createdAt,
    this.updatedAt,
    this.reviewedAt,
    this.accountType = 'instagram',
    this.rejectionCount = 0,
  });

  IGRequestModel copyWith({
    String? id,
    String? instagramUsername,
    String? displayName,
    String? note,
    String? password,
    String? twoFactorKey,
    String? originalImageUrl,
    String? thumbnailImageUrl,
    String? originalImagePath,
    String? thumbnailImagePath,
    int? imageSizeBytes,
    String? senderId,
    String? receiverId,
    String? pairId,
    String? status,
    String? feedback,
    String? lastUpdatedBy,
    String? lastAction,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? reviewedAt,
    String? accountType,
    int? rejectionCount,
  }) {
    return IGRequestModel(
      id: id ?? this.id,
      instagramUsername: instagramUsername ?? this.instagramUsername,
      displayName: displayName ?? this.displayName,
      note: note ?? this.note,
      password: password ?? this.password,
      twoFactorKey: twoFactorKey ?? this.twoFactorKey,
      originalImageUrl: originalImageUrl ?? this.originalImageUrl,
      thumbnailImageUrl: thumbnailImageUrl ?? this.thumbnailImageUrl,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      thumbnailImagePath: thumbnailImagePath ?? this.thumbnailImagePath,
      imageSizeBytes: imageSizeBytes ?? this.imageSizeBytes,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      pairId: pairId ?? this.pairId,
      status: status ?? this.status,
      feedback: feedback ?? this.feedback,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      lastAction: lastAction ?? this.lastAction,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      accountType: accountType ?? this.accountType,
      rejectionCount: rejectionCount ?? this.rejectionCount,
    );
  }

  factory IGRequestModel.fromJson(Map<String, dynamic> json) {
    return IGRequestModel(
      id: json['id'] as String,
      instagramUsername: json['instagramUsername'] as String,
      displayName: json['displayName'] as String? ?? '',
      note: json['note'] as String? ?? '',
      password: json['password'] as String? ?? '',
      twoFactorKey: json['twoFactorKey'] as String? ?? '',
      originalImageUrl: json['originalImageUrl'] as String? ?? '',
      thumbnailImageUrl: json['thumbnailImageUrl'] as String? ?? '',
      originalImagePath: json['originalImagePath'] as String? ?? '',
      thumbnailImagePath: json['thumbnailImagePath'] as String? ?? '',
      imageSizeBytes: _parseInt(json['imageSizeBytes']),
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      pairId: json['pairId'] as String,
      status: json['status'] as String? ?? 'pending',
      feedback: json['feedback'] as String? ?? '',
      lastUpdatedBy: json['lastUpdatedBy'] as String? ?? '',
      lastAction: json['lastAction'] as String? ?? 'created',
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      reviewedAt: _parseDate(json['reviewedAt']),
      accountType: json['accountType'] as String? ?? 'instagram',
      rejectionCount: _parseInt(json['rejectionCount']),
    );
  }

  static int _parseInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  static DateTime? _parseDate(dynamic date) {
    if (date == null) return null;
    if (date is Timestamp) return date.toDate();
    if (date is String) return DateTime.tryParse(date);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'instagramUsername': instagramUsername,
      'displayName': displayName,
      'note': note,
      'password': password,
      'twoFactorKey': twoFactorKey,
      'originalImageUrl': originalImageUrl,
      'thumbnailImageUrl': thumbnailImageUrl,
      'originalImagePath': originalImagePath,
      'thumbnailImagePath': thumbnailImagePath,
      'imageSizeBytes': imageSizeBytes,
      'senderId': senderId,
      'receiverId': receiverId,
      'pairId': pairId,
      'status': status,
      'feedback': feedback,
      'lastUpdatedBy': lastUpdatedBy,
      'lastAction': lastAction,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'accountType': accountType,
      'rejectionCount': rejectionCount,
    };
  }
}
