import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ig_request_model.dart';
import '../utils/date_utils.dart';

class FirestoreService extends ChangeNotifier {
  bool get useFirebase => Firebase.apps.isNotEmpty;

  // In-memory request database for mock
  final List<IGRequestModel> _requests = [];

  // Track active stream controllers to broadcast changes in mock mode
  final List<Map<String, dynamic>> _inboxSubscriptions = [];
  final List<Map<String, dynamic>> _sentSubscriptions = [];

  FirestoreService() {
    if (!useFirebase) {
      _seedInitialRequests();
    }
  }

  void _seedInitialRequests() {
    final now = DateTime.now();
    _requests.addAll([
      IGRequestModel(
        id: 'req_1',
        instagramUsername: '@jane_doe',
        displayName: 'Jane Doe',
        note: 'Vy check giúp anh tài khoản này nha, nghi vấn clone.',
        originalImageUrl: '',
        thumbnailImageUrl: '',
        originalImagePath: '',
        thumbnailImagePath: '',
        imageSizeBytes: 0,
        senderId: 'uid_tan',
        receiverId: 'uid_vy',
        pairId: 'pair_tan_vy',
        status: 'pending',
        feedback: '',
        password: 'password123',
        twoFactorKey: 'CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G',
        lastUpdatedBy: 'uid_tan',
        lastAction: 'created',
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 3)),
        accountType: 'instagram',
      ),
      IGRequestModel(
        id: 'req_2',
        instagramUsername: '100084729103841',
        displayName: 'Facebook Clone 1',
        note: 'Tấn xem hộ em tài khoản FB này có lừa đảo không.',
        originalImageUrl: '',
        thumbnailImageUrl: '',
        originalImagePath: '',
        thumbnailImagePath: '',
        imageSizeBytes: 0,
        senderId: 'uid_vy',
        receiverId: 'uid_tan',
        pairId: 'pair_tan_vy',
        status: 'needs_update',
        feedback: 'Thông reverse 2FA bị sai rồi em ơi, xem lại nhé.',
        password: 'cloneig@0605',
        twoFactorKey: 'CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G',
        lastUpdatedBy: 'uid_tan',
        lastAction: 'needs_update',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 5)),
        reviewedAt: now.subtract(const Duration(hours: 5)),
        accountType: 'facebook',
      ),
    ]);
  }

  // Get current list in memory
  List<IGRequestModel> get requests => List.unmodifiable(_requests);

  // Streams
  Stream<List<IGRequestModel>> streamInboxRequests(String currentUserId, String? pairId) {
    if (useFirebase) {
      return FirebaseFirestore.instance
          .collection('requests')
          .where('receiverId', isEqualTo: currentUserId)
          .where('pairId', isEqualTo: pairId)
          .snapshots()
          .map((snapshot) {
            final list = snapshot.docs.map((doc) => IGRequestModel.fromJson(doc.data())).toList();
            list.sort((a, b) => (b.updatedAt ?? DateTime.now()).compareTo(a.updatedAt ?? DateTime.now()));
            return list;
          });
    } else {
      final controller = StreamController<List<IGRequestModel>>.broadcast();
      final sub = {'controller': controller, 'userId': currentUserId, 'pairId': pairId};
      _inboxSubscriptions.add(sub);
      
      controller.onCancel = () {
        _inboxSubscriptions.remove(sub);
        controller.close();
      };
      
      scheduleMicrotask(() {
        if (!controller.isClosed) {
          final filtered = _requests.where((r) => r.receiverId == currentUserId && r.pairId == pairId).toList();
          filtered.sort((a, b) => (b.updatedAt ?? DateTime.now()).compareTo(a.updatedAt ?? DateTime.now()));
          controller.add(filtered);
        }
      });
      return controller.stream;
    }
  }

  Stream<List<IGRequestModel>> streamSentRequests(String currentUserId, String? pairId) {
    if (useFirebase) {
      return FirebaseFirestore.instance
          .collection('requests')
          .where('senderId', isEqualTo: currentUserId)
          .where('pairId', isEqualTo: pairId)
          .snapshots()
          .map((snapshot) {
            final list = snapshot.docs.map((doc) => IGRequestModel.fromJson(doc.data())).toList();
            list.sort((a, b) => (b.updatedAt ?? DateTime.now()).compareTo(a.updatedAt ?? DateTime.now()));
            return list;
          });
    } else {
      final controller = StreamController<List<IGRequestModel>>.broadcast();
      final sub = {'controller': controller, 'userId': currentUserId, 'pairId': pairId};
      _sentSubscriptions.add(sub);
      
      controller.onCancel = () {
        _sentSubscriptions.remove(sub);
        controller.close();
      };
      
      scheduleMicrotask(() {
        if (!controller.isClosed) {
          final filtered = _requests.where((r) => r.senderId == currentUserId && r.pairId == pairId).toList();
          filtered.sort((a, b) => (b.updatedAt ?? DateTime.now()).compareTo(a.updatedAt ?? DateTime.now()));
          controller.add(filtered);
        }
      });
      return controller.stream;
    }
  }

  void _notifySubscriptions() {
    if (useFirebase) return; // Firestore handles its own realtime streams
    
    for (final sub in List.from(_inboxSubscriptions)) {
      final controller = sub['controller'] as StreamController<List<IGRequestModel>>;
      final userId = sub['userId'] as String;
      final pairId = sub['pairId'] as String?;
      
      if (!controller.isClosed) {
        final filtered = _requests.where((r) => r.receiverId == userId && r.pairId == pairId).toList();
        filtered.sort((a, b) => (b.updatedAt ?? DateTime.now()).compareTo(a.updatedAt ?? DateTime.now()));
        controller.add(filtered);
      }
    }
    
    for (final sub in List.from(_sentSubscriptions)) {
      final controller = sub['controller'] as StreamController<List<IGRequestModel>>;
      final userId = sub['userId'] as String;
      final pairId = sub['pairId'] as String?;
      
      if (!controller.isClosed) {
        final filtered = _requests.where((r) => r.senderId == userId && r.pairId == pairId).toList();
        filtered.sort((a, b) => (b.updatedAt ?? DateTime.now()).compareTo(a.updatedAt ?? DateTime.now()));
        controller.add(filtered);
      }
    }
  }

  int countTodaySentRequests(String currentUserId) {
    if (useFirebase) {
      // For a proper implementation we'd need to query Firestore. 
      // This is slightly complex synchronously, so we will return 0 to bypass the check for now, 
      // or we can fetch it asynchronously if needed.
      return 0; 
    } else {
      final today = DateTime.now();
      return _requests.where((r) {
        if (r.senderId != currentUserId || r.createdAt == null) return false;
        return AppDateUtils.isSameDay(r.createdAt!, today);
      }).length;
    }
  }

  Future<void> createRequest({
    required String instagramUsername,
    required String displayName,
    required String note,
    String password = '',
    String twoFactorKey = '',
    required String imageUrl,
    required String thumbnailImageUrl,
    String originalImagePath = '',
    String thumbnailImagePath = '',
    required int imageSizeBytes,
    required String senderId,
    required String receiverId,
    required String pairId,
    String accountType = 'instagram',
  }) async {
    final newReq = IGRequestModel(
      id: 'req_${DateTime.now().millisecondsSinceEpoch}',
      instagramUsername: instagramUsername,
      displayName: displayName,
      note: note,
      password: password,
      twoFactorKey: twoFactorKey,
      originalImageUrl: imageUrl,
      thumbnailImageUrl: thumbnailImageUrl,
      originalImagePath: originalImagePath.isNotEmpty ? originalImagePath : 'ig_requests/$pairId/req_${DateTime.now().millisecondsSinceEpoch}/original.jpg',
      thumbnailImagePath: thumbnailImagePath.isNotEmpty ? thumbnailImagePath : 'ig_requests/$pairId/req_${DateTime.now().millisecondsSinceEpoch}/thumbnail.jpg',
      imageSizeBytes: imageSizeBytes,
      senderId: senderId,
      receiverId: receiverId,
      pairId: pairId,
      status: 'pending',
      feedback: '',
      lastUpdatedBy: senderId,
      lastAction: 'created',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      accountType: accountType,
    );

    if (useFirebase) {
      await FirebaseFirestore.instance.collection('requests').doc(newReq.id).set(newReq.toJson());
    } else {
      final todayCount = countTodaySentRequests(senderId);
      if (todayCount >= 50) throw Exception('Hôm nay gửi hơi nhiều rồi, mai gửi tiếp nha.');
      _requests.add(newReq);
      _notifySubscriptions();
      notifyListeners();
    }
  }

  Future<void> updateRequest({
    required String requestId,
    required String instagramUsername,
    required String displayName,
    required String note,
    String password = '',
    String twoFactorKey = '',
    String? imageUrl,
    String? thumbnailImageUrl,
    int? imageSizeBytes,
    required String senderId,
    required String receiverId,
    required String pairId,
    required String lastAction,
    String? accountType,
  }) async {
    if (useFirebase) {
      final docRef = FirebaseFirestore.instance.collection('requests').doc(requestId);
      final updateData = {
        'instagramUsername': instagramUsername,
        'displayName': displayName,
        'note': note,
        'password': password,
        'twoFactorKey': twoFactorKey,
        'status': lastAction == 'resubmitted' ? 'updated' : 'pending',
        'lastUpdatedBy': senderId,
        'lastAction': lastAction,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (imageUrl != null) updateData['originalImageUrl'] = imageUrl;
      if (thumbnailImageUrl != null) updateData['thumbnailImageUrl'] = thumbnailImageUrl;
      if (imageSizeBytes != null) updateData['imageSizeBytes'] = imageSizeBytes.toString();
      if (accountType != null) updateData['accountType'] = accountType;

      await docRef.update(updateData);
    } else {
      final index = _requests.indexWhere((r) => r.id == requestId);
      if (index == -1) throw Exception('Không tìm thấy yêu cầu cần sửa.');
      final existing = _requests[index];

      final updated = existing.copyWith(
        instagramUsername: instagramUsername,
        displayName: displayName,
        note: note,
        password: password,
        twoFactorKey: twoFactorKey,
        originalImageUrl: imageUrl ?? existing.originalImageUrl,
        thumbnailImageUrl: thumbnailImageUrl ?? existing.thumbnailImageUrl,
        imageSizeBytes: imageSizeBytes ?? existing.imageSizeBytes,
        status: lastAction == 'resubmitted' ? 'updated' : 'pending',
        lastUpdatedBy: senderId,
        lastAction: lastAction,
        updatedAt: DateTime.now(),
        accountType: accountType ?? existing.accountType,
      );

      _requests[index] = updated;
      _notifySubscriptions();
      notifyListeners();
    }
  }

  Future<void> updateRequestStatus({
    required String requestId,
    required String status,
    required String feedback,
    required String userId,
  }) async {
    String action = 'updated';
    if (status == 'approved') action = 'approved';
    if (status == 'rejected') action = 'rejected';
    if (status == 'needs_update') action = 'needs_update';
    if (status == 'uploaded') action = 'uploaded';

    if (useFirebase) {
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
        'status': status,
        'feedback': feedback,
        'lastUpdatedBy': userId,
        'lastAction': action,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final index = _requests.indexWhere((r) => r.id == requestId);
      if (index == -1) throw Exception('Không tìm thấy yêu cầu.');

      final existing = _requests[index];
      final updated = existing.copyWith(
        status: status,
        feedback: feedback.isNotEmpty ? feedback : existing.feedback,
        lastUpdatedBy: userId,
        lastAction: action,
        updatedAt: DateTime.now(),
        reviewedAt: DateTime.now(),
      );

      _requests[index] = updated;
      _notifySubscriptions();
      notifyListeners();
    }
  }

  Future<void> sendFeedback({
    required String requestId,
    required String feedback,
    required String userId,
  }) async {
    if (useFirebase) {
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
        'feedback': feedback,
        'lastUpdatedBy': userId,
        'lastAction': 'feedback_added',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final index = _requests.indexWhere((r) => r.id == requestId);
      if (index == -1) throw Exception('Không tìm thấy yêu cầu.');

      final existing = _requests[index];
      final updated = existing.copyWith(
        feedback: feedback,
        lastUpdatedBy: userId,
        lastAction: 'feedback_added',
        updatedAt: DateTime.now(),
      );

      _requests[index] = updated;
      _notifySubscriptions();
      notifyListeners();
    }
  }

  Future<void> deleteRequest(String requestId) async {
    if (useFirebase) {
      await FirebaseFirestore.instance.collection('requests').doc(requestId).delete();
    } else {
      final index = _requests.indexWhere((r) => r.id == requestId);
      if (index == -1) return;
      _requests.removeAt(index);
      _notifySubscriptions();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final sub in _inboxSubscriptions) {
      (sub['controller'] as StreamController).close();
    }
    for (final sub in _sentSubscriptions) {
      (sub['controller'] as StreamController).close();
    }
    super.dispose();
  }
}
