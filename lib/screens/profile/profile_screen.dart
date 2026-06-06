import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/image_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _telegramController = TextEditingController();
  final _imageService = ImageService();
  final StorageService _storageService = StorageService();

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _telegramController.dispose();
    super.dispose();
  }

  Future<void> _changeAvatar() async {
    final file = await _imageService.pickImage(ImageSource.gallery);
    if (file == null) return;

    setState(() => _isSaving = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser!;

    try {
      // Upload mock avatar to Storage
      final mockAvatarUrl = await _storageService.uploadOriginalImage(
        file,
        'users/${user.uid}/avatar.jpg',
      );

      authService.updateProfile(user.name, mockAvatarUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật ảnh đại diện thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _saveProfileName() {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    setState(() => _isSaving = true);
    final authService = Provider.of<AuthService>(context, listen: false);

    // Mặc định giữ lại avatarUrl cũ, chỉ sinh mock khi thật sự cần
    final user = authService.currentUser;
    final newAvatar = user?.avatarUrl ?? 'https://api.dicebear.com/7.x/avataaars/svg?seed=$newName';

    authService.updateProfile(newName, newAvatar, telegramChatId: _telegramController.text.trim());
    
    setState(() {
      _isEditing = false;
      _isSaving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã cập nhật thông tin cá nhân')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    final partner = authService.getUserById(user?.partnerId ?? '');

    if (!_isEditing && user != null) {
      _nameController.text = user.name;
      _telegramController.text = user.telegramChatId ?? '';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trang cá nhân'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Avatar edit section
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 54,
                      backgroundColor: theme.primaryColor.withOpacity(0.1),
                      backgroundImage: user?.avatarUrl != null && user!.avatarUrl.isNotEmpty
                          ? NetworkImage(user.avatarUrl)
                          : null,
                      child: user?.avatarUrl == null || user!.avatarUrl.isEmpty
                          ? Icon(Icons.person, size: 54, color: theme.primaryColor)
                          : null,
                    ),
                    if (_isSaving)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black38,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _isSaving ? null : _changeAvatar,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // User Information Form / Display
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Thông tin cá nhân',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
                      ),
                      const Divider(height: 24),
                      if (_isEditing) ...[
                        AppTextField(
                          controller: _nameController,
                          labelText: 'Tên hiển thị',
                          hintText: 'Nhập tên hiển thị mới',
                          prefixIcon: Icons.person_outline,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _telegramController,
                          labelText: 'Telegram Chat ID (để nhận thông báo)',
                          hintText: 'Nhập ID (vd: 123456789)',
                          prefixIcon: Icons.telegram,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Mẹo: Lấy Chat ID bằng cách nhắn tin cho @getmyid_bot trên Telegram.',
                          style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                text: 'Huỷ',
                                type: AppButtonType.outline,
                                onPressed: () => setState(() => _isEditing = false),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppButton(
                                text: 'Lưu',
                                isLoading: _isSaving,
                                onPressed: _saveProfileName,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        _buildProfileField('Tên hiển thị', user?.name ?? ''),
                        _buildProfileField('Email', user?.email ?? ''),
                        _buildProfileField('Telegram Chat ID', user?.telegramChatId?.isNotEmpty == true ? user!.telegramChatId! : 'Chưa thiết lập'),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => setState(() => _isEditing = true),
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Chỉnh sửa'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Partner Info Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCE4EC), // Pink background
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.favorite,
                          color: Colors.pink,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Đối tác ghép đôi',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1C1C1E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              partner != null ? partner.name : 'Chưa ghép đôi',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (partner != null)
                        Chip(
                          backgroundColor: const Color(0xFFE8F8F5),
                          side: BorderSide.none,
                          label: Text(
                            partner.email,
                            style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w500),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Logout button
              AppButton(
                text: 'Đăng xuất',
                type: AppButtonType.danger,
                icon: Icons.logout,
                onPressed: () async {
                  await authService.signOut();
                  if (mounted) {
                    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                  }
                },
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93), fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 15, color: Color(0xFF1C1C1E), fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
