import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
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
import '../../utils/otp_helper.dart';
import 'package:dio/dio.dart';

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

  String? _importedNotepadAlias;
  String? _importedUsername;

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

  bool _isNotepadUrl(String val) {
    final clean = val.trim().toLowerCase();
    return clean.contains('note.2fa.live');
  }

  String? _parseNotepadAlias(String url) {
    try {
      final uri = Uri.parse(url.trim().startsWith('http') ? url.trim() : 'https://${url.trim()}');
      final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (pathSegments.isEmpty) return null;
      if (pathSegments.first == 'note' && pathSegments.length > 1) {
        return pathSegments[1];
      }
      return pathSegments.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _importFromNotepad(String url, {bool filterDuplicates = false}) async {
    final alias = _parseNotepadAlias(url);
    if (alias == null || alias.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đường dẫn link Notepad không hợp lệ.')),
      );
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    if (user == null || 
        user.partnerId == null || 
        user.partnerId!.isEmpty || 
        user.pairId == null || 
        user.pairId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn cần ghép đôi tài khoản trước khi thực hiện chức năng này.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(width: 20),
            Expanded(child: Text('Đang tải tài khoản từ Notepad...')),
          ],
        ),
      ),
    );

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final user = authService.currentUser;

      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      final response = await dio.get('https://note.2fa.live/note/$alias');
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }

      final data = response.data;
      String? rawContent;
      if (data is Map) {
        rawContent = data['r']?.toString();
      } else if (data is String) {
        final decoded = json.decode(data);
        rawContent = decoded['r']?.toString();
      }

      if (rawContent == null || rawContent.trim().isEmpty) {
        throw Exception('Không có dữ liệu tài khoản trong Notepad.');
      }

      final lines = rawContent.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && l.contains('|')).toList();
      if (lines.isEmpty) {
        throw Exception('Không tìm thấy tài khoản định dạng hợp lệ (dạng tài khoản|mật khẩu|2fa) trong Notepad.');
      }

      var accounts = lines.map((line) {
        final parts = line.split('|');
        return {
          'username': parts[0].trim(),
          'password': parts.length > 1 ? parts[1].trim() : '',
          'twoFactorKey': parts.length > 2 ? parts[2].trim() : '',
        };
      }).toList();

      if (filterDuplicates && user != null && user.pairId != null && user.pairId!.isNotEmpty) {
        final existingRequests = await firestoreService.getRequestsByPairId(user.pairId!);
        final existingUsernames = existingRequests.map((r) {
          final username = r.instagramUsername;
          return username.startsWith('@') ? username.substring(1).toLowerCase() : username.toLowerCase();
        }).toSet();

        accounts = accounts.where((acc) {
          final username = acc['username']!;
          final normalized = username.startsWith('@') ? username.substring(1).toLowerCase() : username.toLowerCase();
          return !existingUsernames.contains(normalized);
        }).toList();

        if (accounts.isEmpty) {
          throw Exception('Tất cả tài khoản trong Notepad đã được gửi kiểm tra trước đó rồi!');
        }
      }

      if (accounts.length == 1) {
        final acc = accounts.first;
        setState(() {
          _usernameController.text = acc['username']!;
          _passwordController.text = acc['password']!;
          _twoFactorKeyController.text = acc['twoFactorKey']!;
          _quickImportController.clear();
          _currentOtp = ''; // reset OTP
          _importedNotepadAlias = alias;
          _importedUsername = acc['username']!;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã nhập thành công tài khoản: ${acc['username']}'),
            ),
          );
        }
      } else {
        if (mounted) {
          _showAccountSelectionBottomSheet(accounts, alias);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }
      
      String errorMsg = e.toString().replaceAll('Exception: ', '');
      bool isCorsError = errorMsg.contains('XMLHttpRequest') || errorMsg.contains('connection error');

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Lỗi kết nối / CORS'),
              ],
            ),
            content: Text(isCorsError
                ? 'Không thể tải trực tiếp trên Web do chính sách CORS của trình duyệt (Lỗi này sẽ KHÔNG xảy ra khi chạy app trên điện thoại iOS/Android).\n\nBạn hãy copy nội dung note và dán trực tiếp vào ô Nhập nhanh bên trên!'
                : 'Không thể tải dữ liệu từ Notepad.\nChi tiết: $errorMsg'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    }
  }



  Future<void> _confirmAndDeleteSpecificAccountFromNotepad() async {
    final alias = _importedNotepadAlias;
    final username = _importedUsername;
    if (alias == null || username == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa tài khoản'),
        content: Text('Bạn có chắc chắn muốn xóa tài khoản $username khỏi Notepad (note.2fa.live/$alias) không? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSpecificAccountFromNotepad();
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSpecificAccountFromNotepad() async {
    final alias = _importedNotepadAlias;
    final username = _importedUsername;
    if (alias == null || alias.isEmpty || username == null || username.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.red),
            SizedBox(width: 20),
            Expanded(child: Text('Đang xóa tài khoản khỏi Notepad...')),
          ],
        ),
      ),
    );

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      final response = await dio.get('https://note.2fa.live/note/$alias');
      
      final data = response.data;
      String? rawContent;
      if (data is Map) {
        rawContent = data['r']?.toString();
      } else if (data is String) {
        final decoded = json.decode(data);
        rawContent = decoded['r']?.toString();
      }

      if (rawContent == null) {
        throw Exception('Không thể lấy nội dung từ Notepad.');
      }

      final lines = rawContent.split('\n');
      final updatedLines = <String>[];
      bool found = false;

      for (var line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) {
          updatedLines.add(line);
          continue;
        }
        final parts = trimmedLine.split('|');
        if (parts.isNotEmpty) {
          final noteUsername = parts[0].trim();
          final cleanNote = noteUsername.replaceAll('@', '').toLowerCase();
          final cleanTarget = username.replaceAll('@', '').toLowerCase();
          if (cleanNote == cleanTarget) {
            found = true;
            continue; // Bỏ qua dòng này (xóa nó)
          }
        }
        updatedLines.add(line);
      }

      if (!found) {
        throw Exception('Không tìm thấy tài khoản $username trên Notepad.');
      }

      final newContent = updatedLines.join('\n');

      final postResponse = await dio.post(
        'https://note.2fa.live/note/$alias',
        data: {'content': newContent},
        options: Options(contentType: Headers.jsonContentType),
      );

      if (mounted) {
        Navigator.pop(context); // Đóng dialog loading
      }

      if (postResponse.statusCode == 200) {
        setState(() {
          _usernameController.clear();
          _passwordController.clear();
          _twoFactorKeyController.clear();
          _currentOtp = '';
          _importedNotepadAlias = null;
          _importedUsername = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã xóa tài khoản $username khỏi Notepad thành công!')),
          );
        }
      } else {
        throw Exception('Không thể lưu nội dung mới lên Notepad.');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Đóng dialog loading
      }
      debugPrint('Lỗi xóa tài khoản khỏi Notepad: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xóa tài khoản: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    }
  }

  void _showAccountSelectionBottomSheet(List<Map<String, String>> accounts, String alias) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Chọn tài khoản muốn nhập',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: accounts.length,
                  itemBuilder: (context, index) {
                    final acc = accounts[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE8F0FE),
                        child: Icon(Icons.person, color: Colors.blue),
                      ),
                      title: Text(acc['username']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'Pass: ${acc['password']!.isNotEmpty ? "••••••" : "(trống)"} | 2FA: ${acc['twoFactorKey']!.isNotEmpty ? (acc['twoFactorKey']!.length > 8 ? "${acc['twoFactorKey']!.substring(0, 8)}..." : acc['twoFactorKey']!) : "(trống)"}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      onTap: () {
                        setState(() {
                          _usernameController.text = acc['username']!;
                          _passwordController.text = acc['password']!;
                          _twoFactorKeyController.text = acc['twoFactorKey']!;
                          _quickImportController.clear();
                          _currentOtp = ''; // reset OTP
                          _importedNotepadAlias = alias;
                          _importedUsername = acc['username']!;
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Đã nhập thành công tài khoản: ${acc['username']}'),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _parseQuickImport(String val) {
    final clean = val.trim();
    if (_isNotepadUrl(clean)) {
      _importFromNotepad(clean, filterDuplicates: true);
      return;
    }
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
      
      final isSuccess = resultName != null && resultName != 'KHÔNG ĐỌC ĐƯỢC' && !resultName.startsWith('LỖI:');
      if (isSuccess) {
        final authService = Provider.of<AuthService>(context, listen: false);
        final firestoreService = Provider.of<FirestoreService>(context, listen: false);
        final user = authService.currentUser;
        if (user != null && user.pairId != null && user.pairId!.isNotEmpty) {
          final existingRequests = await firestoreService.getRequestsByPairId(user.pairId!);
          if (!mounted) return;
          final normalizedResultName = resultName.trim().toLowerCase();
          final alreadyExists = existingRequests.any((r) => r.displayName.trim().toLowerCase() == normalizedResultName);
          if (alreadyExists) {
            setState(() {
              _isScanning = false;
              _selectedFile = null;
              _imageSize = 0;
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
        if (isSuccess) {
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
                : resultName
          ),
        ),
      );
    }
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final notifService = Provider.of<NotificationService>(context, listen: false);

    final user = authService.currentUser;
    if (user == null || user.partnerId == null || user.partnerId!.isEmpty || user.pairId == null || user.pairId!.isEmpty) {
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

    // 2. Check duplicate display name
    final targetName = _displayNameController.text.trim();
    if (targetName.isNotEmpty && user.pairId != null && user.pairId!.isNotEmpty) {
      final existingRequests = await firestoreService.getRequestsByPairId(user.pairId!);
      if (!mounted) return;
      final alreadyExists = existingRequests.any((r) => r.displayName.trim().toLowerCase() == targetName.toLowerCase());
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
      int finalSizeBytes = 0;
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
        if (urls.containsKey('imageSizeBytes')) {
          finalSizeBytes = int.tryParse(urls['imageSizeBytes']!) ?? finalSizeBytes;
        } else {
          finalSizeBytes = (_imageSize * 1024 * 1024).toInt();
        }
      }

      // Save request doc to Firestore
      // Check verified badge
      final isVerified = await notifService.checkVerificationStatus(_accountType, normalizedUsername);

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
        imageSizeBytes: finalSizeBytes,
        senderId: user.uid,
        receiverId: user.partnerId!,
        pairId: user.pairId!,
        accountType: _accountType,
        isVerified: isVerified,
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

          final pushTitle = isVerified 
              ? '🌟 Hồ sơ $serviceLabel TÍCH XANH mới!'
              : 'Hồ sơ $serviceLabel mới cần check';
          
          final pushBody = isVerified
              ? '${user.name} vừa gửi một yêu cầu check TÍCH XANH cho $normalizedUsername'
              : '${user.name} vừa gửi một yêu cầu check cho $normalizedUsername';

          notifService.simulateIncomingNotification(
            context,
            pushTitle,
            pushBody,
            mockId,
          );
          
          final telegramMsg = isVerified
              ? '🌟 <b>HỒ SƠ TÍCH XANH MỚI</b> 🌟\n'
                '${user.name} vừa gửi một yêu cầu check $serviceLabel có <b>TÍCH XANH (Verified Badge)</b> cho <code>$normalizedUsername</code>.'
              : '🔔 <b>Yêu cầu mới</b>\n'
                '${user.name} vừa gửi một yêu cầu check $serviceLabel cho <code>$normalizedUsername</code>.';

          notifService.sendTelegramMessage(
            telegramMsg,
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
                              _importedNotepadAlias = null;
                              _importedUsername = null;
                              _currentOtp = '';
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
                              _importedNotepadAlias = null;
                              _importedUsername = null;
                              _currentOtp = '';
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
                const SizedBox(height: 12),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Icon(
                          _accountType == 'instagram' ? Icons.alternate_email : Icons.facebook_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _accountType == 'instagram' 
                              ? 'Nhập danh sách từ note.2fa.live/instagram' 
                              : 'Nhập danh sách từ note.2fa.live/facebook',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.primaryColor,
                          side: BorderSide(color: theme.primaryColor),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          final url = _accountType == 'instagram' 
                              ? 'https://note.2fa.live/instagram' 
                              : 'https://note.2fa.live/facebook';
                          _importFromNotepad(url, filterDuplicates: true);
                        },
                      ),
                    ),
                    if (_importedNotepadAlias != null && _importedUsername != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.delete_forever_outlined, size: 18),
                          label: Text(
                            'Xóa tài khoản $_importedUsername khỏi note.2fa.live/$_importedNotepadAlias',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _confirmAndDeleteSpecificAccountFromNotepad,
                        ),
                      ),
                    ],
                  ],
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
                  hintText: 'Ví dụ: Clone Số 1, Clone Giá Rẻ...',
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
    ),
  );
}
}
