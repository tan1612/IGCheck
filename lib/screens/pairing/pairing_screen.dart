import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _errorMessage = '';
  bool _isConnecting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _errorMessage = '';
      _isConnecting = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Simulate connecting process
      await Future.delayed(const Duration(milliseconds: 1500));
      
      await authService.mockPairWith(_emailController.text);
      
      if (mounted) {
        // Show success sheet/dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE8F8F5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.redAccent,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Kết nối thành công!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Hai bạn đã được kết nối với nhau. Bắt đầu gửi hồ sơ kiểm tra ngay nhé!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      text: 'Bắt đầu',
                      onPressed: () {
                        Navigator.pop(context); // Close dialog
                        Navigator.pushReplacementNamed(context, '/dashboard');
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghép đôi tài khoản'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.favorite_border_rounded,
                      size: 64,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Kết nối hai người',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Để bắt đầu sử dụng app, bạn cần ghép đôi tài khoản của mình với người yêu.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                // Display own info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E5EA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Email kết nối của bạn:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1C1C1E),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Partner Input
                AppTextField(
                  controller: _emailController,
                  labelText: 'Nhập email của người kia',
                  hintText: 'Ví dụ: partner@igcheck.com',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Vui lòng nhập email của người kia';
                    }
                    if (val.trim().toLowerCase() == user?.email.toLowerCase()) {
                      return 'Không thể kết nối với chính mình';
                    }
                    return null;
                  },
                ),
                if (_errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
                const SizedBox(height: 32),
                AppButton(
                  text: 'Kết nối ngay',
                  isLoading: _isConnecting,
                  onPressed: _connect,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
