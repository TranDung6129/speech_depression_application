import 'package:flutter/material.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _accepted = false;
  bool _busy = false;
  String? _error;

  Future<void> _readConsent() async {
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
    if (!_accepted) {
      setState(() => _error = 'Please agree to continue.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final outcome = await AuthService.instance.acceptConsent();
    if (!mounted) return;

    setState(() => _busy = false);
    if (outcome.ok) return;

    setState(() => _error = outcome.message);
  }

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
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.93),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Consent update required',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      SizedBox(height: 10),
                      Text(
                        'The consent text has been updated. Please review and accept it to continue.',
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _accepted,
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                      _accepted = value ?? false;
                                      _error = null;
                                    }),
                          ),
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text(
                                    'I agree to the updated consent text',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _busy ? null : _readConsent,
                                  child: const Text('Read text'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!,
                            style: const TextStyle(fontSize: 12, color: Color(0xFFC0392B))),
                      ],
                      const SizedBox(height: 18),
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
                              : const Text('Agree and continue',
                                  style: TextStyle(fontSize: 15)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Consent version: ${AppConfig.consentVersion}',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
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
}
