import 'package:flutter/material.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _inviteCode = TextEditingController();

  String? _sex;
  String? _dialectRegion;
  int? _birthYear;
  bool _consentAccepted = false;
  bool _busy = false;
  String? _generalError;
  final Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _pickBirthYear() async {
    final currentYear = DateTime.now().year;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select year of birth', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: currentYear - 1899,
                itemBuilder: (context, index) {
                  final year = currentYear - index;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('$year'),
                    trailing: _birthYear == year
                        ? const Icon(Icons.check_rounded,
                            size: 18, color: AppColors.greenDeep)
                        : null,
                    onTap: () => Navigator.of(context).pop(year),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (picked == null) return;
    setState(() {
      _birthYear = picked;
      _fieldErrors.remove('birth_year');
    });
  }

  Future<void> _openConsentText() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Consent text'),
        content: const SingleChildScrollView(
          child: Text(
            'By continuing, you agree that this app may collect and store your voice recordings, profile information, and consent status for research and care workflows. You can contact the study team if you have questions about how your data is used.\n\nVersion: v1',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final confirm = _confirmPassword.text;
    final inviteCode = _inviteCode.text.trim();

    setState(() {
      _generalError = null;
      _fieldErrors.clear();
    });

    if (name.isEmpty) {
      _fieldErrors['display_name'] = 'Please enter your full name.';
    }
    if (email.isEmpty || !email.contains('@')) {
      _fieldErrors['email'] = 'Please enter a valid email address.';
    }
    if (password.length < 8) {
      _fieldErrors['password'] = 'Password must be at least 8 characters long.';
    }
    if (confirm != password) {
      _fieldErrors['password_confirmation'] = 'Passwords do not match.';
    }
    if (!_consentAccepted) {
      _fieldErrors['consent_version'] = 'You must agree to the consent text.';
    }
    if (_sex == null) {
      _fieldErrors['sex'] = 'Please choose your sex.';
    }
    if (_birthYear == null) {
      _fieldErrors['birth_year'] = 'Please select your year of birth.';
    }
    if (_fieldErrors.isNotEmpty) {
      setState(() {});
      return;
    }

    setState(() => _busy = true);

    final result = await AuthService.instance.register(
      email: email,
      password: password,
      displayName: name,
      consentVersion: AppConfig.consentVersion,
      sex: _sex!,
      birthYear: _birthYear!,
      dialectRegion: _dialectRegion,
      inviteCode: inviteCode.isEmpty ? null : inviteCode,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (result.ok) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _generalError = result.message;
      _fieldErrors
        ..clear()
        ..addAll(result.fieldErrors);
    });
  }

  String? _errorFor(String key) => _fieldErrors[key];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: getJournalGradient(context)),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: _busy ? null : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          SizedBox(width: 4),
                          Text('Create account',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Please fill in all required details to create your account.',
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      _input(
                        controller: _name,
                        hint: 'Full name',
                        errorText: _errorFor('display_name'),
                      ),
                      const SizedBox(height: 10),
                      _input(
                        controller: _email,
                        hint: 'Email',
                        keyboardType: TextInputType.emailAddress,
                        errorText: _errorFor('email'),
                      ),
                      const SizedBox(height: 10),
                      _input(
                        controller: _password,
                        hint: 'Password',
                        obscure: true,
                        errorText: _errorFor('password'),
                      ),
                      const SizedBox(height: 10),
                      _input(
                        controller: _confirmPassword,
                        hint: 'Confirm password',
                        obscure: true,
                        errorText: _errorFor('password_confirmation'),
                      ),
                      const SizedBox(height: 12),
                      _sectionLabel('Consent'),
                      const SizedBox(height: 6),
                      _consentRow(),
                      if (_errorFor('consent_version') != null) ...[
                        const SizedBox(height: 6),
                        Text(_errorFor('consent_version')!,
                            style: const TextStyle(fontSize: 12, color: Color(0xFFC0392B))),
                      ],
                      const SizedBox(height: 12),
                      _sectionLabel('Sex'),
                      const SizedBox(height: 6),
                      _choiceWrap(
                        value: _sex,
                        onChanged: (value) => setState(() {
                          _sex = value;
                          _fieldErrors.remove('sex');
                        }),
                        items: const [
                          ('male', 'Male'),
                          ('female', 'Female'),
                          ('unspecified', 'Prefer not to say'),
                        ],
                      ),
                      if (_errorFor('sex') != null) ...[
                        const SizedBox(height: 6),
                        Text(_errorFor('sex')!,
                            style: const TextStyle(fontSize: 12, color: Color(0xFFC0392B))),
                      ],
                      const SizedBox(height: 12),
                      _sectionLabel('Year of birth'),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickBirthYear,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color: _errorFor('birth_year') == null
                                  ? AppColors.border
                                  : const Color(0xFFC0392B),
                            ),
                          ),
                          child: Text(
                            _birthYear == null ? 'Select year' : '$_birthYear',
                            style: TextStyle(
                              fontSize: 14,
                              color: _birthYear == null ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7) : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      if (_errorFor('birth_year') != null) ...[
                        const SizedBox(height: 6),
                        Text(_errorFor('birth_year')!,
                            style: const TextStyle(fontSize: 12, color: Color(0xFFC0392B))),
                      ],
                      const SizedBox(height: 12),
                      _sectionLabel('Dialect region'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _dialectRegion,
                        items: const [
                          DropdownMenuItem(value: 'north', child: Text('North')),
                          DropdownMenuItem(value: 'central', child: Text('Central')),
                          DropdownMenuItem(value: 'south', child: Text('South')),
                          DropdownMenuItem(value: 'other', child: Text('Other')),
                        ],
                        onChanged: (value) => setState(() => _dialectRegion = value),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionLabel('Clinic invite code (optional)'),
                      const SizedBox(height: 6),
                      _input(
                        controller: _inviteCode,
                        hint: 'Invite code',
                        errorText: _errorFor('invite_code'),
                      ),
                      if (_generalError != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.amberTint,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                          child: Text(
                            _generalError!,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF633806)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.greenDeep,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            elevation: 0,
                          ),
                          child: _busy
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(context).colorScheme.surface,
                                  ),
                                )
                              : const Text('Create account', style: TextStyle(fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    TextInputType? keyboardType,
    String? errorText,
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
        errorText: errorText,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(label,
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant));
  }

  Widget _consentRow() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _busy
          ? null
          : () => setState(() {
                _consentAccepted = !_consentAccepted;
                _fieldErrors.remove('consent_version');
              }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _consentAccepted,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _consentAccepted = value ?? false;
                        _fieldErrors.remove('consent_version');
                      }),
            ),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'I agree to the consent text',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _openConsentText,
                    child: const Text('Read text'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceWrap({
    required String? value,
    required ValueChanged<String> onChanged,
    required List<(String, String)> items,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => ChoiceChip(
              label: Text(item.$2),
              selected: value == item.$1,
              onSelected: _busy ? null : (_) => onChanged(item.$1),
            ),
          )
          .toList(),
    );
  }
}
