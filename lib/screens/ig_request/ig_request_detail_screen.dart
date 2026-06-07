import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import '../../models/ig_request_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/status_chip.dart';
import '../../utils/date_utils.dart';
import '../../services/ai_service.dart';
import '../../utils/otp_helper.dart';

class IGRequestDetailScreen extends StatefulWidget {
  const IGRequestDetailScreen({super.key});

  @override
  State<IGRequestDetailScreen> createState() => _IGRequestDetailScreenState();
}

class _IGRequestDetailScreenState extends State<IGRequestDetailScreen> {
  final _feedbackController = TextEditingController();
  bool _isSubmitting = false;
  bool _isPasswordObscured = true;
  
  String? _aiExtractedName;
  bool _isScanning = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(IGRequestModel request, String newStatus) async {
    setState(() => _isSubmitting = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final notifService = Provider.of<NotificationService>(context, listen: false);
    final user = authService.currentUser!;

    try {
      await firestoreService.updateRequestStatus(
        requestId: request.id,
        status: newStatus,
        feedback: _feedbackController.text.trim(),
        userId: user.uid,
      );

      // Trigger mock push notification to the sender
      final sender = authService.getUserById(request.senderId);
      if (sender != null) {
        String notifTitle = '';
        String notifBody = '';

        if (newStatus == 'approved') {
          notifTitle = 'Hồ sơ đã được duyệt';
          notifBody = '${user.name} đã đánh dấu OK cho ${request.instagramUsername}';
        } else if (newStatus == 'rejected') {
          notifTitle = 'Hồ sơ chưa ổn';
          notifBody = '${user.name} đã đánh dấu Không OK cho ${request.instagramUsername}';
        } else if (newStatus == 'needs_update') {
          notifTitle = 'Cần cập nhật lại';
          notifBody = '${user.name} yêu cầu sửa ${request.instagramUsername}';
        }

        if (mounted) {
          notifService.simulateIncomingNotification(
            context,
            notifTitle,
            notifBody,
            request.id,
          );
        }

        notifService.sendTelegramMessage(
          '🔔 <b>$notifTitle</b>\n$notifBody',
          targetChatId: sender.telegramChatId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật trạng thái thành công')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitFeedbackOnly(IGRequestModel request) async {
    final feedbackText = _feedbackController.text.trim();
    if (feedbackText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập phản hồi trước khi gửi')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final notifService = Provider.of<NotificationService>(context, listen: false);
    final user = authService.currentUser!;

    try {
      await firestoreService.sendFeedback(
        requestId: request.id,
        feedback: feedbackText,
        userId: user.uid,
      );

      // Trigger mock push notification to the sender
      final sender = authService.getUserById(request.senderId);
      if (sender != null) {
        if (mounted) {
          notifService.simulateIncomingNotification(
            context,
            'Có phản hồi mới',
            '${user.name} vừa gửi phản hồi cho ${request.instagramUsername}',
            request.id,
          );
        }

        notifService.sendTelegramMessage(
          '💬 <b>Có phản hồi mới</b>\n${user.name} vừa gửi phản hồi cho <code>${request.instagramUsername}</code>.',
          targetChatId: sender.telegramChatId,
        );
      }

      if (mounted) {
        _feedbackController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi phản hồi thành công')),
        );
        // Refresh details by using local updated copy to avoid crash when provider list is empty in Firebase
        final updatedRequest = request.copyWith(
          feedback: feedbackText,
          lastUpdatedBy: user.uid,
          lastAction: 'feedback_added',
          updatedAt: DateTime.now(),
        );
        Navigator.pushReplacementNamed(context, '/ig_request_detail', arguments: updatedRequest);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteRequest(String requestId) async {
    setState(() => _isSubmitting = true);
    try {
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      await firestoreService.deleteRequest(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa hồ sơ (Đã bán)!')),
        );
        Navigator.pop(context); // Go back to inbox
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xóa: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _downloadImage(String imageUrl) async {
    if (imageUrl.isEmpty) return;
    
    setState(() => _isSubmitting = true);
    try {
      final dio = Dio();
      final response = await dio.get(
        imageUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36'},
        ),
      );
      
      final result = await ImageGallerySaver.saveImage(
        Uint8List.fromList(response.data),
        quality: 100,
        name: "IGCheck_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (mounted) {
        if (result != null && result['isSuccess'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã tải ảnh gốc thành công và lưu vào thư viện ảnh.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lỗi: Không thể lưu ảnh vào máy.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải ảnh: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _scanNameAI() async {
    // Read the passed request object from arguments to get the image URL
    final argRequest = ModalRoute.of(context)!.settings.arguments as IGRequestModel;
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final request = firestoreService.requests.firstWhere(
      (r) => r.id == argRequest.id,
      orElse: () => argRequest,
    );

    if (request.originalImageUrl.isEmpty) return;

    setState(() {
      _isScanning = true;
      _aiExtractedName = null;
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
              'AI đang quét đối chiếu họ tên...',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    // If mock data, just use mock
    String? resultName;
    if (request.originalImageUrl.startsWith('http')) {
      resultName = await AIService().extractNameFromImageUrl(request.originalImageUrl);
    } else {
      // Mock result because it's a local mock URL
      await Future.delayed(const Duration(milliseconds: 1500));
      final names = ['NGUYỄN VĂN TẤN', 'ĐỖ THỊ VY', 'TRẦN VĂN A', 'LÊ THỊ B'];
      resultName = names[Random().nextInt(names.length)];
    }

    if (mounted) {
      Navigator.pop(context);
      setState(() {
        _isScanning = false;
        if (resultName == null) {
          final names = ['NGUYỄN VĂN TẤN', 'ĐỖ THỊ VY', 'TRẦN VĂN A', 'LÊ THỊ B'];
          _aiExtractedName = '${names[Random().nextInt(names.length)]} (MOCK)';
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chưa cấu hình API Key. Dùng dữ liệu giả lập.')),
          );
        } else {
          _aiExtractedName = resultName;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read the passed request object from arguments
    final argRequest = ModalRoute.of(context)!.settings.arguments as IGRequestModel;
    
    // Listen to firestore service updates to get the realtime version of this request
    final firestoreService = Provider.of<FirestoreService>(context);
    final request = firestoreService.requests.firstWhere(
      (r) => r.id == argRequest.id,
      orElse: () => argRequest,
    );

    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isSender = request.senderId == user?.uid;
    final isReceiver = request.receiverId == user?.uid;

    final senderName = authService.getUserById(request.senderId)?.name ?? 'Người gửi';
    final receiverName = authService.getUserById(request.receiverId)?.name ?? 'Người nhận';

    // Populate feedback field on load if empty and we have existing feedback
    if (_feedbackController.text.isEmpty && request.feedback.isNotEmpty) {
      _feedbackController.text = request.feedback;
    }

    final isInstagram = request.accountType == 'instagram';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(request.instagramUsername),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              final shareText = '${isInstagram ? "Instagram" : "Facebook"}: ${request.instagramUsername}\nPass: ${request.password}\n2FA: ${request.twoFactorKey}';
              Clipboard.setData(ClipboardData(text: shareText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã sao chép toàn bộ thông tin đăng nhập!'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            tooltip: 'Chia sẻ thông tin đăng nhập',
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Info Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Thông tin hồ sơ',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
                          ),
                          StatusChip(status: request.status),
                        ],
                      ),
                      const Divider(height: 24),
                      _buildInfoRow(
                        isInstagram ? 'Tài khoản IG' : 'UID Facebook', 
                        request.instagramUsername,
                      ),
                      if (request.displayName.isNotEmpty)
                        _buildInfoRow('Tên hiển thị', request.displayName),
                      _buildInfoRow('Người gửi', senderName),
                      _buildInfoRow('Người nhận', receiverName),
                      _buildInfoRow('Ghi chú', request.note.isNotEmpty ? request.note : '(Không có ghi chú)'),
                      _buildInfoRow(
                        'Thời gian gửi',
                        AppDateUtils.formatDateTime(request.createdAt),
                      ),
                      _buildInfoRow(
                        'Cập nhật cuối',
                        AppDateUtils.formatDateTime(request.updatedAt),
                      ),
                    ],
                  ),
                ),
              ),
              // Attachment Card
              if (request.originalImageUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tệp đính kèm',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
                        ),
                        const Divider(height: 24),
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
                                  const Icon(Icons.image_outlined, color: Colors.blue, size: 24),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'anh_xac_minh.jpg (Size: ${(request.imageSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB)',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.download_rounded, color: Colors.blue, size: 20),
                                    onPressed: _isSubmitting ? null : () => _downloadImage(request.originalImageUrl),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  )
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.scanner_rounded, size: 18),
                                  label: const Text('AI quét họ tên đối chiếu'),
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
                              if (_aiExtractedName != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                                          SizedBox(width: 6),
                                          Text('[Kết quả quét AI]', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '- Họ tên trên giấy tờ: $_aiExtractedName',
                                        style: TextStyle(color: Colors.green.shade800, fontSize: 13, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              // 2. Credentials Card
              if (request.password.isNotEmpty || request.twoFactorKey.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Thông tin đăng nhập clone',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
                        ),
                        const Divider(height: 24),
                        // Username Field
                        _buildCredentialField(
                          label: isInstagram ? 'Tài khoản' : 'UID',
                          value: (isInstagram && request.instagramUsername.startsWith('@'))
                              ? request.instagramUsername.substring(1)
                              : request.instagramUsername,
                          obscured: false,
                        ),
                        if (request.password.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          // Password Field
                          _buildCredentialField(
                            label: 'Mật khẩu',
                            value: request.password,
                            obscured: _isPasswordObscured,
                            onToggleObscure: () {
                              setState(() {
                                _isPasswordObscured = !_isPasswordObscured;
                              });
                            },
                          ),
                        ],
                        if (request.twoFactorKey.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          // 2FA Key Field
                          _buildCredentialField(
                            label: 'Mã bảo mật 2FA',
                            value: request.twoFactorKey,
                            obscured: false,
                            isTwoFactor: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // 3. Feedback Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Phản hồi kiểm tra',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
                      ),
                      const Divider(height: 20),
                      if (request.feedback.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            request.feedback,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1C1C1E),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else if (!isReceiver) ...[
                        const Text(
                          'Chưa có phản hồi nào.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Receiver input for feedback
                      if (isReceiver && request.status != 'approved') ...[
                        TextField(
                          controller: _feedbackController,
                          maxLines: 3,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Nhập ý kiến phản hồi tại đây...',
                            fillColor: const Color(0xFFF8F9FA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE5E5EA)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppButton(
                          text: 'Gửi phản hồi',
                          type: AppButtonType.secondary,
                          isLoading: _isSubmitting,
                          onPressed: () => _submitFeedbackOnly(request),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // 4. Role Action Buttons
              // IF current user is RECEIVER: show review action CTAs
              if (isReceiver && request.status != 'approved') ...[
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: 'Đã tạch',
                        type: AppButtonType.danger,
                        isLoading: _isSubmitting,
                        onPressed: () => _updateStatus(request, 'rejected'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        text: 'Đã up',
                        type: AppButtonType.secondary,
                        isLoading: _isSubmitting,
                        onPressed: () => _updateStatus(request, 'uploaded'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppButton(
                  text: 'Đã xanh',
                  isLoading: _isSubmitting,
                  onPressed: () => _updateStatus(request, 'approved'),
                ),
              ],
              // IF current user is SENDER and request is rejected / needs update: show edit button
              if (isSender && (request.status == 'rejected' || request.status == 'needs_update')) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFEEBA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          request.status == 'needs_update'
                              ? 'Hồ sơ này cần sửa lại theo phản hồi.'
                              : 'Hồ sơ này đã tạch (Lần ${request.rejectionCount}/3). Vui lòng sửa thông tin và đính kèm ảnh khác. Nếu tạch 3 lần sẽ tự động bị xóa!',
                          style: const TextStyle(fontSize: 13, color: Colors.brown, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppButton(
                  text: request.status == 'rejected' ? 'Sửa & Gửi ảnh khác' : 'Sửa thông tin tài khoản',
                  icon: Icons.edit_outlined,
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/edit_ig_request',
                      arguments: request,
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
              // Nút xóa (Đã bán)
              AppButton(
                text: 'Đã bán (Xóa hồ sơ)',
                type: AppButtonType.danger,
                icon: Icons.delete_outline,
                isLoading: _isSubmitting,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Xác nhận xóa'),
                      content: const Text('Bạn có chắc chắn tài khoản này đã bán và muốn xóa hồ sơ vĩnh viễn khỏi hệ thống không?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Hủy'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteRequest(request.id);
                          },
                          child: const Text('Xóa ngay', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF8E8E93)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1C1C1E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialField({
    required String label,
    required String value,
    required bool obscured,
    VoidCallback? onToggleObscure,
    bool isTwoFactor = false,
  }) {
    final displayValue = obscured ? '••••••••' : value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93), fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E5EA)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayValue,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Courier',
                    color: Color(0xFF1C1C1E),
                  ),
                ),
              ),
              if (onToggleObscure != null)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: const Color(0xFF8E8E93),
                  ),
                  onPressed: onToggleObscure,
                ),
              if (onToggleObscure != null) const SizedBox(width: 12),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 20,
                  color: Color(0xFF8E8EF8),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã sao chép $label vào bộ nhớ tạm.'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
              if (isTwoFactor) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => OtpHelper.showOtpDialog(context, value),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
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
            ],
          ),
        ),
      ],
    );
  }
}
