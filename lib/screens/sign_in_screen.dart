import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'register_screen.dart';

/// Sign-in screen.
///
/// Intentionally kept short and simple, asking only for email and password.
/// This is the first thing users encounter, and a long form at this stage
/// is the easiest place to give up — especially for tired users.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

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
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters long.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    final outcome = await AuthService.instance.signIn(
      email: email,
      password: password,
    );

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _error = outcome.ok ? null : outcome.message;
    });
  }

  Future<void> _openRegister() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });

    final consentState = await AuthService.instance.checkConsentVersion();
    if (!mounted) return;

    setState(() => _isBusy = false);

    if (consentState == ConsentVersionState.ok) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RegisterScreen()),
      );
      return;
    }

    setState(() {
      _error = consentState == ConsentVersionState.mismatch
          ? 'Please update the app before creating a new account.'
          : 'Unable to verify the consent version. Please try again later.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: getJournalGradient(context)),
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
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                    ),
                    child: Icon(Icons.mic_none_rounded,
                        size: 27, color: AppColors.greenDeep),
                  ),
                  SizedBox(height: 22),
                  Text('Voice Journal', style: TextStyle(fontSize: 21)),
                  SizedBox(height: 6),
                  Text('Welcome back',
                      style: TextStyle(
                          fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 30),
                  _field(
                    controller: _email,
                    hint: 'Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    controller: _password,
                    hint: 'Password',
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
                        borderRadius: BorderRadius.circular(AppRadius.card),
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
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        elevation: 0,
                      ),
                      child: _isBusy
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Theme.of(context).colorScheme.surface),
                            )
                          : const Text('Sign in',
                              style: TextStyle(fontSize: 15)),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextButton(
                    onPressed: _isBusy ? null : _openRegister,
                    child: Text(
                      'Create a new account',
                      style: TextStyle(
                          fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 14),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
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
