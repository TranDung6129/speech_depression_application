import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Màn đăng nhập.
///
/// Cố tình để ít chữ và không hỏi gì ngoài email với mật khẩu. Đây là thứ
/// đầu tiên người dùng gặp, và một biểu mẫu dài ở bước này là chỗ dễ bỏ cuộc
/// nhất — nhất là với người đang mệt.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _isRegistering = false;
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Bạn nhập lại email giúp mình nhé.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Mật khẩu cần ít nhất 8 ký tự.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    final auth = AuthService.instance;
    final outcome = _isRegistering
        ? await auth.register(email: email, password: password)
        : await auth.signIn(email: email, password: password);

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _error = outcome.ok ? null : outcome.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kJournalGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    child: const Icon(Icons.mic_none_rounded,
                        size: 27, color: AppColors.greenDeep),
                  ),
                  const SizedBox(height: 22),
                  const Text('Nhật ký giọng nói',
                      style: TextStyle(fontSize: 21)),
                  const SizedBox(height: 6),
                  Text(
                    _isRegistering
                        ? 'Tạo tài khoản để bắt đầu'
                        : 'Chào bạn quay lại',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 30),
                  _field(
                    controller: _email,
                    hint: 'Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    controller: _password,
                    hint: 'Mật khẩu',
                    obscure: true,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.amberTint,
                        borderRadius:
                            BorderRadius.circular(AppRadius.card),
                      ),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF633806)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isBusy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.greenDeep,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                        elevation: 0,
                      ),
                      child: _isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              _isRegistering ? 'Tạo tài khoản' : 'Đăng nhập',
                              style: const TextStyle(fontSize: 15),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isBusy
                        ? null
                        : () => setState(() {
                              _isRegistering = !_isRegistering;
                              _error = null;
                            }),
                    child: Text(
                      _isRegistering
                          ? 'Mình đã có tài khoản'
                          : 'Mình chưa có tài khoản',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: !obscure,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.7),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
