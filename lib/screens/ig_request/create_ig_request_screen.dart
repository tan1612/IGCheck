import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../../services/ai_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../utils/validators.dart';

class CreateIGRequestScreen extends StatefulWidget {
  const CreateIGRequestScreen({super.key});

  @override
  State<CreateIGRequestScreen> createState() => _CreateIGRequestScreenState();
}

class _CreateIGRequestScreenState extends State<CreateIGRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _noteController = TextEditingController();
  final _passwordController = TextEditingController();
  final _twoFactorKeyController = TextEditingController();
  final _quickImportController = TextEditingController();
  
  String _accountType = 'instagram'; // 'instagram' or 'facebook'
  bool _isSubmitting = false;

  XFile? _selectedFile;
  double _imageSize = 0;
  bool _isScanning = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _noteController.dispose();
    _passwordController.dispose();
    _twoFactorKeyController.dispose();
    _quickImportController.dispose();
    super.dispose();
  }

  void _parseQuickImport(String val) {
    final clean = val.trim();
    if (clean.contains('|')) {
      final parts = clean.split('|');
      if (parts.isNotEmpty) {
        _usernameController.text = parts[0].trim();
      }
      if (parts.length > 1) {
        _passwordController.text = parts[1].trim();
      }
      if (parts.length > 2) {
        _twoFactorKeyController.text = parts[2].trim();
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source, imageQuality: 70);
      if (pickedFile != null) {
        final sizeBytes = await pickedFile.length();
        final sizeMb = sizeBytes / (1024 * 1024);
        
        setState(() {
          _selectedFile = pickedFile;
          _imageSize = sizeMb;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _showImageSourceActionSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Chọn ảnh đính kèm'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
            child: const Text('Chụp ảnh'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
            child: const Text('Chọn từ thư viện'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          isDestructiveAction: true,
          child: const Text('Hủy'),
        ),
      ),
    );
  }

  Future<void> _scanNameAI() async {
    if (_selectedFile == null) return;
    
    setState(() {
      _isScanning = true;
    });

    // Show radar overlay dialogue
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'AI đang quét họ tên trên giấy tờ...',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    // Call real AI Service
    final resultName = await AIService().extractNameFromImage(_selectedFile!);

    if (mounted) {
      // Dismiss dialog
      Navigator.pop(context);
      
      setState(() {
        _isScanning = false;
        if (resultName != null && resultName != 'KHÔNG ĐỌC ĐƯỢC' && resultName != 'LỖI QUÉT ẢNH') {
          _displayNameController.text = resultName;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resultName == null 
              ? 'Chưa cấu hình API Key, vui lòng kiểm tra lại.'
              : 'AI đã nhận diện: $resultName'
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final notifService = Provider.of<NotificationService>(context, listen: false);

    final user = authService.currentUser;
    if (user == null || user.partnerId == null || user.pairId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tài khoản chưa được ghép đôi.')),
      );
      return;
    }

    // 1. Check daily requests limit
    final todayCount = firestoreService.countTodaySentRequests(user.uid);
    if (todayCount >= 50) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Giới hạn hàng ngày'),
          content: const Text('Hôm nay gửi hơi nhiều rồi, mai gửi tiếp nha.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đồng ý'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final mockId = 'req_${DateTime.now().millisecondsSinceEpoch}';

      // Normalize username based on account type
      final rawUsername = _usernameController.text;
      final normalizedUsername = _accountType == 'instagram'
          ? Validators.normalizeInstagramUsername(rawUsername)
          : rawUsername.trim();

      String imageUrl = '';
      String thumbnailImageUrl = '';
      String originalImagePath = '';
      String thumbnailImagePath = '';
      if (_selectedFile != null) {
        final storageService = StorageService();
        final pathBase = 'ig_requests/${user.pairId!}/$mockId';
        
        final urls = await storageService.replaceImageSafely(
          newFile: _selectedFile!,
          oldOriginalPath: '',
          oldThumbnailPath: '',
          newBasePath: pathBase,
        );
        imageUrl = urls['originalImageUrl'] ?? '';
        thumbnailImageUrl = urls['thumbnailImageUrl'] ?? '';
        originalImagePath = urls['originalImagePath'] ?? '';
        thumbnailImagePath = urls['thumbnailImagePath'] ?? '';
      }

      // Save request doc to Firestore
      await firestoreService.createRequest(
        instagramUsername: normalizedUsername,
        displayName: _displayNameController.text.trim(),
        note: _noteController.text.trim(),
        password: _passwordController.text.trim(),
        twoFactorKey: _twoFactorKeyController.text.trim(),
        imageUrl: imageUrl,
        thumbnailImageUrl: thumbnailImageUrl,
        originalImagePath: originalImagePath,
        thumbnailImagePath: thumbnailImagePath,
        imageSizeBytes: _selectedFile != null ? (_imageSize * 1024 * 1024).toInt() : 0,
        senderId: user.uid,
        receiverId: user.partnerId!,
        pairId: user.pairId!,
        accountType: _accountType,
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        
        // Trigger simulated FCM push notification for the other user
        final partner = authService.getUserById(user.partnerId!);
        if (partner != null) {
          final serviceLabel = _accountType == 'instagram' ? 'Instagram' : 'Facebook';
          final normalizedUsername = _accountType == 'instagram'
              ? Validators.normalizeInstagramUsername(_usernameController.text)
              : _usernameController.text.trim();

          notifService.simulateIncomingNotification(
            context,
            'Hồ sơ $serviceLabel mới cần check',
            '${user.name} vừa gửi một yêu cầu check cho $normalizedUsername',
            mockId,
          );
          
          notifService.sendTelegramMessage(
            '🔔 <b>Yêu cầu mới</b>\n'
            '${user.name} vừa gửi một yêu cầu check $serviceLabel cho <code>$normalizedUsername</code>.',
            targetChatId: partner.telegramChatId,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi hồ sơ cho người kia thành công!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Gửi hồ sơ mới'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Account Type Selector
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _accountType = 'instagram';
                              _quickImportController.clear();
                              _usernameController.clear();
                              _passwordController.clear();
                              _twoFactorKeyController.clear();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _accountType == 'instagram' ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: _accountType == 'instagram'
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                'Instagram',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _accountType == 'instagram' ? theme.primaryColor : const Color(0xFF8E8E93),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _accountType = 'facebook';
                              _quickImportController.clear();
                              _usernameController.clear();
                              _passwordController.clear();
                              _twoFactorKeyController.clear();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _accountType == 'facebook' ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: _accountType == 'facebook'
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                'Facebook',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _accountType == 'facebook' ? theme.primaryColor : const Color(0xFF8E8E93),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Quick import tool
                AppTextField(
                  controller: _quickImportController,
                  labelText: _accountType == 'instagram' 
                      ? 'Nhập nhanh Instagram (dạng tài khoản|mật khẩu|2fa)'
                      : 'Nhập nhanh Facebook (dạng UID|mật khẩu|2fa)',
                  hintText: _accountType == 'instagram'
                      ? 'Ví dụ: turtle.8670143|cloneig@0605|CY72Q...'
                      : 'Ví dụ: 100084729103841|cloneig@0605|CY72Q...',
                  prefixIcon: Icons.bolt_outlined,
                  onChanged: _parseQuickImport,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                // Username/UID field
                AppTextField(
                  controller: _usernameController,
                  labelText: _accountType == 'instagram'
                      ? 'Tài khoản Instagram (@username)'
                      : 'UID Facebook (hoặc tên đăng nhập)',
                  hintText: _accountType == 'instagram'
                      ? 'Ví dụ: @abcxyz hoặc abcxyz'
                      : 'Ví dụ: 100084729103841',
                  prefixIcon: _accountType == 'instagram' ? Icons.alternate_email : Icons.facebook_outlined,
                  validator: _accountType == 'instagram' 
                      ? Validators.validateUsername 
                      : (val) => (val == null || val.trim().isEmpty) ? 'Vui lòng nhập UID Facebook' : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _passwordController,
                  labelText: 'Mật khẩu clone',
                  hintText: 'Nhập mật khẩu tài khoản',
                  prefixIcon: Icons.lock_outline,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _twoFactorKeyController,
                  labelText: 'Khóa bảo mật 2FA',
                  hintText: 'Ví dụ: CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G',
                  prefixIcon: Icons.security_outlined,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _displayNameController,
                  labelText: 'Tên hiển thị (Tùy chọn)',
                  hintText: 'Ví dụ: Clone Số 1, Clone Giá Rẻ...',
                  prefixIcon: Icons.badge_outlined,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _noteController,
                  labelText: 'Ghi chú thêm',
                  hintText: 'Ví dụ: Anh check giúp em acc này nha...',
                  prefixIcon: Icons.chat_bubble_outline_rounded,
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                
                // Attachment section
                if (_selectedFile == null)
                  InkWell(
                    onTap: _showImageSourceActionSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.05),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, color: theme.primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Đính kèm ảnh xác minh (Tùy chọn)',
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: kIsWeb 
                              ? Image.network(_selectedFile!.path, fit: BoxFit.cover, width: double.infinity, height: 150)
                              : Image.file(File(_selectedFile!.path), fit: BoxFit.cover, width: double.infinity, height: 150),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.insert_drive_file, color: Colors.grey, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Tệp đính kèm: anh_xac_minh.jpg (Size: ${_imageSize.toStringAsFixed(2)} MB)',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red, size: 20),
                              onPressed: () {
                                setState(() {
                                  _selectedFile = null;
                                  _imageSize = 0;
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.face_retouching_natural, size: 18),
                            label: const Text('AI đọc họ tên'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple.shade50,
                              foregroundColor: Colors.purple,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _isScanning ? null : _scanNameAI,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 32),
                AppButton(
                  text: 'Gửi cho người kia',
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
