import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'dart:async';

class AuthService extends ChangeNotifier {
  UserModel? _currentUser;
  UserModel? _partnerUser;
  bool _isLoading = false;

  UserModel? get currentUser => _currentUser;
  UserModel? get partnerUser => _partnerUser;
  bool get isLoading => _isLoading;

  bool get useFirebase => Firebase.apps.isNotEmpty;
  bool get isUserSignedIn => useFirebase ? FirebaseAuth.instance.currentUser != null : _currentUser != null;

  // Preset mock accounts
  static final List<UserModel> _mockUsers = [
    UserModel(
      uid: 'uid_tan',
      name: 'Tấn',
      email: 'tan@igcheck.com',
      avatarUrl: 'https://api.dicebear.com/7.x/avataaars/svg?seed=tan',
      partnerId: 'uid_vy',
      pairId: 'pair_tan_vy',
      fcmToken: 'mock_token_tan',
      telegramChatId: '1710308922',
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      updatedAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
    UserModel(
      uid: 'uid_vy',
      name: 'Vy',
      email: 'vy@igcheck.com',
      avatarUrl: 'https://api.dicebear.com/7.x/avataaars/svg?seed=vy',
      partnerId: 'uid_tan',
      pairId: 'pair_tan_vy',
      fcmToken: 'mock_token_vy',
      telegramChatId: '1710308922',
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      updatedAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
  ];

  AuthService() {
    if (useFirebase) {
      FirebaseAuth.instance.authStateChanges().listen((User? user) async {
        if (user != null) {
          await _fetchUserData(user.uid);
        } else {
          _currentUser = null;
          notifyListeners();
        }
      });
    }
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;

  Future<void> _fetchUserData(String uid) async {
    try {
      _userSubscription?.cancel();
      _userSubscription = FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((doc) async {
        if (doc.exists && doc.data() != null) {
          _currentUser = UserModel.fromJson(doc.data()!);
          if (_currentUser!.partnerId != null && _currentUser!.partnerId!.isNotEmpty) {
            try {
              final pDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUser!.partnerId).get();
              if (pDoc.exists && pDoc.data() != null) {
                _partnerUser = UserModel.fromJson(pDoc.data()!);
              }
            } catch (e) {
              debugPrint('Error fetching partner data: $e');
            }
          }
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('Error setting up user listener: $e');
    }
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (useFirebase) {
        final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        await _fetchUserData(credential.user!.uid);
      } else {
        await Future.delayed(const Duration(milliseconds: 800));
        final matched = _mockUsers.firstWhere(
          (u) => u.email.toLowerCase() == email.trim().toLowerCase() && password == '123456',
          orElse: () => throw Exception('Tài khoản hoặc mật khẩu không đúng.'),
        );
        _currentUser = matched.copyWith(lastSeenAt: DateTime.now());
      }
      return true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signUp(String name, String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (useFirebase) {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        final user = credential.user!;
        
        final newUser = UserModel(
          uid: user.uid,
          name: name.trim(),
          email: email.trim().toLowerCase(),
          avatarUrl: 'https://api.dicebear.com/7.x/avataaars/svg?seed=${name.trim()}',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(newUser.toJson());
        _currentUser = newUser;
      } else {
        await Future.delayed(const Duration(milliseconds: 800));
        final exists = _mockUsers.any((u) => u.email.toLowerCase() == email.trim().toLowerCase());
        if (exists) throw Exception('Email đã được đăng ký.');

        final newUser = UserModel(
          uid: 'uid_${DateTime.now().millisecondsSinceEpoch}',
          name: name.trim(),
          email: email.trim().toLowerCase(),
          avatarUrl: 'https://api.dicebear.com/7.x/avataaars/svg?seed=${name.trim()}',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        _mockUsers.add(newUser);
        _currentUser = newUser;
      }
      return true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      _userSubscription?.cancel();
      _userSubscription = null;
      if (useFirebase) {
        await FirebaseAuth.instance.signOut();
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      _currentUser = null;
      _partnerUser = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateProfile(String name, String avatarUrl, {String? telegramChatId}) {
    if (_currentUser == null) return;
    final updated = _currentUser!.copyWith(
      name: name,
      avatarUrl: avatarUrl,
      telegramChatId: telegramChatId,
      updatedAt: DateTime.now(),
    );

    if (useFirebase) {
      FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).update(updated.toJson());
    } else {
      final index = _mockUsers.indexWhere((u) => u.uid == _currentUser!.uid);
      if (index != -1) _mockUsers[index] = updated;
    }
    
    _currentUser = updated;
    notifyListeners();
  }

  void updateFcmToken(String? token) {
    if (_currentUser == null || token == null) return;
    final updated = _currentUser!.copyWith(fcmToken: token);

    if (useFirebase) {
      FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).update({'fcmToken': token});
    } else {
      final index = _mockUsers.indexWhere((u) => u.uid == _currentUser!.uid);
      if (index != -1) _mockUsers[index] = updated;
    }
    
    _currentUser = updated;
    notifyListeners();
  }

  Future<void> mockPairWith(String partnerEmail) async {
    if (_currentUser == null) return;

    if (useFirebase) {
      final query = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: partnerEmail.trim().toLowerCase()).get();
      if (query.docs.isEmpty) throw Exception('Không tìm thấy người dùng với email này trên Firebase.');
      
      final partnerDoc = query.docs.first;
      final partnerId = partnerDoc.id;

      if (partnerId == _currentUser!.uid) throw Exception('Không thể ghép đôi với chính mình.');

      final pairId = 'pair_${_currentUser!.uid}_$partnerId';

      await FirebaseFirestore.instance.collection('users').doc(partnerId).update({
        'partnerId': _currentUser!.uid,
        'pairId': pairId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).update({
        'partnerId': partnerId,
        'pairId': pairId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _fetchUserData(_currentUser!.uid);
    } else {
      final partner = _mockUsers.firstWhere(
        (u) => u.email.toLowerCase() == partnerEmail.trim().toLowerCase(),
        orElse: () => throw Exception('Không tìm thấy người dùng với email này trong dữ liệu ảo.'),
      );

      if (partner.uid == _currentUser!.uid) throw Exception('Không thể ghép đôi với chính mình.');

      final pairId = 'pair_${_currentUser!.uid}_${partner.uid}';

      final partnerIdx = _mockUsers.indexWhere((u) => u.uid == partner.uid);
      _mockUsers[partnerIdx] = partner.copyWith(partnerId: _currentUser!.uid, pairId: pairId, updatedAt: DateTime.now());

      _currentUser = _currentUser!.copyWith(partnerId: partner.uid, pairId: pairId, updatedAt: DateTime.now());
      final userIdx = _mockUsers.indexWhere((u) => u.uid == _currentUser!.uid);
      _mockUsers[userIdx] = _currentUser!;
      notifyListeners();
    }
  }

  // Get user profile by ID
  UserModel? getUserById(String uid) {
    if (!useFirebase) {
      try {
        return _mockUsers.firstWhere((u) => u.uid == uid);
      } catch (_) {
        return null;
      }
    }
    // For Firebase, we cache the partner when fetching current user.
    if (uid == _currentUser?.uid) return _currentUser;
    if (uid == _partnerUser?.uid) return _partnerUser;
    return null; 
  }
}
