class PairModel {
  final String id;
  final String memberA;
  final String memberB;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PairModel({
    required this.id,
    required this.memberA,
    required this.memberB,
    this.createdAt,
    this.updatedAt,
  });

  PairModel copyWith({
    String? id,
    String? memberA,
    String? memberB,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PairModel(
      id: id ?? this.id,
      memberA: memberA ?? this.memberA,
      memberB: memberB ?? this.memberB,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory PairModel.fromJson(Map<String, dynamic> json) {
    return PairModel(
      id: json['id'] as String,
      memberA: json['memberA'] as String,
      memberB: json['memberB'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'memberA': memberA,
      'memberB': memberB,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
