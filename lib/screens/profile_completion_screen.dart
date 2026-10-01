import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ProfileCompletionScreen extends StatefulWidget {
  const ProfileCompletionScreen({super.key});

  @override
  State<ProfileCompletionScreen> createState() => _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  late final TextEditingController _name;
  String? _sex;
  int? _birthYear;
  String? _dialectRegion;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = AuthService.instance;
    _name = TextEditingController(text: auth.displayName == 'Your name' ? '' : auth.displayName);
    _sex = auth.sex;
    _birthYear = auth.birthYear;
    _dialectRegion = auth.dialectRegion;
  }

  @override
  void dispose() {
    _name.dispose();
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
    setState(() => _birthYear = picked);
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    if (_sex == null) {
      setState(() => _error = 'Please choose your sex.');
      return;
    }
    if (_birthYear == null) {
      setState(() => _error = 'Please select your year of birth.');
      return;
    }
    if (_dialectRegion == null) {
      setState(() => _error = 'Please choose your dialect region.');
      return;
    }

    final auth = AuthService.instance;
    final payload = <String, dynamic>{};
    if (name != auth.displayName) payload['display_name'] = name;
    if (_sex != auth.sex) payload['sex'] = _sex;
    if (_birthYear != auth.birthYear) payload['birth_year'] = _birthYear;
    if (_dialectRegion != auth.dialectRegion) {
      payload['dialect_region'] = _dialectRegion;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final outcome = await auth.updateProfile(
      displayName: payload['display_name'] as String?,
      sex: payload['sex'] as String?,
      birthYear: payload['birth_year'] as int?,
      dialectRegion: payload['dialect_region'] as String?,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (outcome.ok) return;
    setState(() => _error = outcome.message);
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
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
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.93),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Complete your profile',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                          TextButton(
                            onPressed: () => AuthService.instance.signOut(),
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text('Sign out'),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Text(
                        'We need a few details before you can continue.',
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      _field(controller: _name, hint: 'Full name'),
                      const SizedBox(height: 10),
                      _choiceWrap(
                        value: _sex,
                        onChanged: (value) => setState(() => _sex = value),
                        items: const [
                          ('male', 'Male'),
                          ('female', 'Female'),
                          ('unspecified', 'Prefer not to say'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: _pickBirthYear,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            _birthYear == null ? 'Select year of birth' : '$_birthYear',
                            style: TextStyle(
                              fontSize: 14,
                              color: _birthYear == null ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7) : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
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
                          hintText: 'Dialect region',
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
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.amberTint,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                          child: Text(
                            _error!,
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
                              : const Text('Save and continue',
                                  style: TextStyle(fontSize: 15)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You can adjust these details later.',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 2),
                      Text('Birth year range: 1900–$currentYear',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
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

  Widget _field({required TextEditingController controller, required String hint}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
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
