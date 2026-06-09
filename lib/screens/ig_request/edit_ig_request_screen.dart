import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/ig_request_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../../services/ai_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../utils/validators.dart';
import '../../utils/otp_helper.dart';

class EditIGRequestScreen extends StatefulWidget {
  const EditIGRequestScreen({super.key});

  @override
  State<EditIGRequestScreen> createState() => _EditIGRequestScreenState();
}

class _EditIGRequestScreenState extends State<EditIGRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _noteController = TextEditingController();
  final _passwordController = TextEditingController();
  final _twoFactorKeyController = TextEditingController();

  bool _isUploading = false;
  bool _isInitialized = false;
  
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
    super.dispose();
  }

  String _currentOtp = '';

  Future<void> _generateOtpInline(String secret) async {
    if (secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập khóa bảo mật 2FA trước.')),
      );
      return;
    }
    try {
      final otp = await OtpHelper.fetchOtp(secret);
      setState(() {
        _currentOtp = otp;
      });
      await Clipboard.setData(ClipboardData(text: otp));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã lấy và sao chép mã OTP: $otp'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _submit(IGRequestModel request) async {
    if (!_formKey.currentState!.validate()) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final notifService = Provider.of<NotificationService>(context, listen: false);

    final user = authService.currentUser;
    if (user == null) return;

    if (request.status == 'rejected' && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hồ sơ đã tạch. Vui lòng đính kèm ảnh xác minh mới để gửi lại.')),
      );
      return;
    }

    // Check duplicate display name (excluding current request)
    final targetName = _displayNameController.text.trim();
    if (targetName.isNotEmpty && user.pairId != null) {
      final existingRequests = await firestoreService.getRequestsByPairId(user.pairId!);
      if (!mounted) return;
      final alreadyExists = existingRequests.any((r) => 
        r.id != request.id && r.displayName.trim().toLowerCase() == targetName.toLowerCase()
      );
      if (alreadyExists) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Hồ sơ đã tồn tại'),
            content: Text('Họ tên "$targetName" đã tồn tại trong danh sách yêu cầu. Vui lòng tải lên ảnh xác minh khác.'),
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
    }

    setState(() => _isUploading = true);

    try {
      final normalizedUsername = request.accountType == 'instagram'
          ? Validators.normalizeInstagramUsername(_usernameController.text)
          : _usernameController.text.trim();

      String? newImageUrl;
      String? newThumbnailImageUrl;
      int? newImageSizeBytes;

      if (_selectedFile != null) {
        final storageService = StorageService();
        final pathBase = 'ig_requests/${user.pairId!}/${request.id}';
        
        final urls = await storageService.replaceImageSafely(
          newFile: _selectedFile!,
          oldOriginalPath: request.originalImagePath,
          oldThumbnailPath: request.thumbnailImagePath,
          newBasePath: pathBase,
        );
        newImageUrl = urls['originalImageUrl'];
        newThumbnailImageUrl = urls['thumbnailImageUrl'];
        newImageSizeBytes = (_imageSize * 1024 * 1024).toInt();
      }

      await firestoreService.updateRequest(
        requestId: request.id,
        instagramUsername: normalizedUsername,
        displayName: _displayNameController.text.trim(),
        note: _noteController.text.trim(),
        password: _passwordController.text.trim(),
        twoFactorKey: _twoFactorKeyController.text.trim(),
        imageUrl: newImageUrl,
        thumbnailImageUrl: newThumbnailImageUrl,
        imageSizeBytes: newImageSizeBytes,
        senderId: user.uid,
        receiverId: user.partnerId!,
        pairId: user.pairId!,
        lastAction: 'resubmitted',
        accountType: request.accountType,
      );

      if (mounted) {
        setState(() => _isUploading = false);
        
        // Trigger simulated FCM push notification to receiver
        final partner = authService.getUserById(user.partnerId!);
        if (partner != null) {
          final serviceLabel = request.accountType == 'instagram' ? 'Instagram' : 'Facebook';
          notifService.simulateIncomingNotification(
            context,
            'Đã cập nhật lại hồ sơ $serviceLabel',
            '${user.name} vừa gửi lại bản cập nhật cho $normalizedUsername',
            request.id,
          );
          
          notifService.sendTelegramMessage(
            '🔔 <b>Cập nhật hồ sơ</b>\n'
            '${user.name} vừa gửi lại bản cập nhật hồ sơ $serviceLabel cho <code>$normalizedUsername</code>.',
            targetChatId: partner.telegramChatId,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi lại cập nhật thành công!')),
        );
        Navigator.pop(context); // Go back to details
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source, imageQuality: 70);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final sizeBytes = bytes.length;
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
        title: const Text('Chọn ảnh đính kèm mới'),
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
      Navigator.pop(context);
      
      final isSuccess = resultName != null && resultName != 'KHÔNG ĐỌC ĐƯỢC' && !resultName.startsWith('LỖI:');
      if (isSuccess) {
        final authService = Provider.of<AuthService>(context, listen: false);
        final firestoreService = Provider.of<FirestoreService>(context, listen: false);
        final user = authService.currentUser;
        final request = ModalRoute.of(context)!.settings.arguments as IGRequestModel;
        if (user != null && user.pairId != null) {
          final existingRequests = await firestoreService.getRequestsByPairId(user.pairId!);
          if (!mounted) return;
          final normalizedResultName = resultName.trim().toLowerCase();
          final alreadyExists = existingRequests.any((r) => 
            r.id != request.id && r.displayName.trim().toLowerCase() == normalizedResultName
          );
          if (alreadyExists) {
            setState(() {
              _isScanning = false;
              _selectedFile = null;
            });
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Hồ sơ đã tồn tại'),
                content: Text('Họ tên "$resultName" đã tồn tại trong danh sách yêu cầu. Vui lòng tải lên ảnh xác minh khác.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Đồng ý'),
                  ),
                ],
              ),
            );
            return;
          }
        }
        await Clipboard.setData(ClipboardData(text: resultName));
      }

      if (!mounted) return;

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
              : isSuccess
                ? 'AI đã nhận diện & sao chép: $resultName'
                : 'AI đã nhận diện: $resultName'
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = ModalRoute.of(context)!.settings.arguments as IGRequestModel;

    // Initialize values on first load
    if (!_isInitialized) {
      _usernameController.text = request.instagramUsername;
      _displayNameController.text = request.displayName;
      _noteController.text = request.note;
      _passwordController.text = request.password;
      _twoFactorKeyController.text = request.twoFactorKey;
      _isInitialized = true;
    }

    final isInstagram = request.accountType == 'instagram';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(isInstagram ? 'Sửa lại hồ sơ IG' : 'Sửa lại hồ sơ Facebook'),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: _usernameController,
                  labelText: isInstagram
                      ? 'Tài khoản Instagram (@username)'
                      : 'UID Facebook (hoặc tên đăng nhập)',
                  hintText: isInstagram ? 'Ví dụ: @abcxyz' : 'Ví dụ: 100084729103841',
                  prefixIcon: isInstagram ? Icons.alternate_email : Icons.facebook_outlined,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Color(0xFF8E8EF8), size: 20),
                    onPressed: () {
                      final val = _usernameController.text.trim();
                      if (val.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: val));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Đã sao chép tài khoản!'), duration: Duration(seconds: 1)),
                        );
                      }
                    },
                  ),
                  validator: isInstagram
                      ? Validators.validateUsername
                      : (val) => (val == null || val.trim().isEmpty) ? 'Vui lòng nhập UID Facebook' : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _passwordController,
                  labelText: 'Mật khẩu clone',
                  hintText: 'Nhập mật khẩu tài khoản',
                  prefixIcon: Icons.lock_outline,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Color(0xFF8E8EF8), size: 20),
                    onPressed: () {
                      final val = _passwordController.text.trim();
                      if (val.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: val));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Đã sao chép mật khẩu!'), duration: Duration(seconds: 1)),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _twoFactorKeyController,
                  labelText: 'Khóa bảo mật 2FA',
                  hintText: 'Ví dụ: CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G',
                  prefixIcon: Icons.security_outlined,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Color(0xFF8E8EF8), size: 20),
                        onPressed: () {
                          final val = _twoFactorKeyController.text.trim();
                          if (val.isNotEmpty) {
                            Clipboard.setData(ClipboardData(text: val));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã sao chép khóa 2FA!'), duration: Duration(seconds: 1)),
                            );
                          }
                        },
                      ),
                      TextButton(
                        onPressed: () => _generateOtpInline(_twoFactorKeyController.text),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.only(right: 12),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Lấy OTP',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_currentOtp.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: TextEditingController(text: _currentOtp),
                    labelText: 'Mã OTP 2FA hiện tại',
                    prefixIcon: Icons.vpn_key_outlined,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, color: Color(0xFF8E8EF8), size: 20),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _currentOtp));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã sao chép mã OTP!'), duration: Duration(seconds: 1)),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, color: Colors.blue, size: 20),
                          onPressed: () => _generateOtpInline(_twoFactorKeyController.text),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AppTextField(
                  controller: _displayNameController,
                  labelText: 'Tên hiển thị (Tùy chọn)',
                  hintText: 'Ví dụ: Cửa hàng A',
                  prefixIcon: Icons.badge_outlined,
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _displayNameController,
                    builder: (context, value, child) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Color(0xFF8E8EF8), size: 20),
                        onPressed: () {
                          final val = _displayNameController.text.trim();
                          if (val.isNotEmpty) {
                            Clipboard.setData(ClipboardData(text: val));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã sao chép tên hiển thị!'), duration: Duration(seconds: 1)),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _noteController,
                  labelText: 'Ghi chú thêm',
                  hintText: 'Nhập nội dung sửa lại...',
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
                        color: request.status == 'rejected' ? Colors.red.withValues(alpha: 0.05) : Colors.blue.withValues(alpha: 0.05),
                        border: Border.all(color: request.status == 'rejected' ? Colors.red.withValues(alpha: 0.3) : Colors.blue.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, color: request.status == 'rejected' ? Colors.red : Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            request.status == 'rejected' ? 'Đính kèm ảnh xác minh mới (Bắt buộc)' : 'Đính kèm ảnh xác minh thay thế',
                            style: TextStyle(
                              color: request.status == 'rejected' ? Colors.red : Theme.of(context).primaryColor,
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: kIsWeb
                              ? Image.network(_selectedFile!.path, fit: BoxFit.cover, width: double.infinity, height: 150)
                              : Image.file(File(_selectedFile!.path), fit: BoxFit.cover, width: double.infinity, height: 150),
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
                  text: 'Gửi cập nhật lại',
                  isLoading: _isUploading,
                  onPressed: () => _submit(request),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
