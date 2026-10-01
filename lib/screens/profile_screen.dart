import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/upload_queue.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = StorageService.instance;

  int _reminderHour = 20;
  int _reminderMinute = 0;
  int _intervalDays = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (h, m) = await _storage.reminderTime();
    final days = await _storage.assessmentIntervalDays();
    if (!mounted) return;
    setState(() {
      _reminderHour = h;
      _reminderMinute = m;
      _intervalDays = days;
    });
  }

  Future<void> _pickReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
    );
    if (picked == null) return;
    await _storage.setReminderTime(picked.hour, picked.minute);
    if (!mounted) return;
    setState(() {
      _reminderHour = picked.hour;
      _reminderMinute = picked.minute;
    });
  }

  Future<void> _pickInterval() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(22, 16, 22, 30),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How often should we remind you?',
                style: TextStyle(fontSize: 16)),
            SizedBox(height: 4),
            Text('You can still do it whenever you want.',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            ...[
              (3, 'Every 3 days'),
              (7, 'Every week'),
              (14, 'Every 2 weeks'),
              (0, 'No reminder — I will check in myself'),
            ].map((opt) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(opt.$2, style: const TextStyle(fontSize: 14)),
                  trailing: _intervalDays == opt.$1
                      ? const Icon(Icons.check_rounded,
                          size: 18, color: AppColors.greenDeep)
                      : null,
                  onTap: () => Navigator.of(context).pop(opt.$1),
                )),
          ],
        ),
      ),
    );

    if (picked == null) return;
    await _storage.setAssessmentIntervalDays(picked);
    if (!mounted) return;
    setState(() => _intervalDays = picked);
  }

  Future<void> _confirmWipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        title: const Text('Delete all recordings?',
            style: TextStyle(fontSize: 17)),
        content: const Text(
          'All recordings and assessments stored on this device will be deleted. This action cannot be undone.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep them'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete all',
                style: TextStyle(color: AppColors.riskHigh)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _storage.wipeAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All recordings have been deleted.')),
    );
  }

  String get _intervalLabel => switch (_intervalDays) {
        3 => 'Every 3 days',
        7 => 'Every week',
        14 => 'Every 2 weeks',
        _ => 'No reminder',
      };

  @override
  Widget build(BuildContext context) {
    final time =
        '${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')}';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
        children: [
          _profileHeader(),
          const SizedBox(height: 18),
          _syncCard(),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: AuthService.instance,
            builder: (context, _) {
              if (AuthService.instance.clinicId != null) {
                return const SizedBox.shrink();
              }
              return SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _joinClinic,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.borderStrong),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  child: const Text('Enter clinic code'),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          _sectionCard([
            _row(
              icon: Icons.notifications_none_rounded,
              title: 'Journal reminder',
              subtitle: 'Daily · $time',
              onTap: _pickReminder,
            ),
            _divider(),
            _row(
              icon: Icons.assignment_outlined,
              title: 'Assessment frequency',
              subtitle: 'You choose · $_intervalLabel',
              onTap: _pickInterval,
            ),
            _divider(),
            _row(
              icon: Icons.lock_outline_rounded,
              title: 'Privacy & data',
              subtitle: 'View, download, or delete',
              onTap: _confirmWipe,
            ),
          ]),
          SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Coming soon',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
          ),
          _sectionCard([
            _lockedRow(Icons.chat_bubble_outline_rounded, 'AI chat'),
            _divider(),
            _lockedRow(Icons.spa_outlined, 'Relaxation & music'),
            _divider(),
            _lockedRow(Icons.bedtime_outlined, 'Sleep & energy'),
            _divider(),
            _lockedRow(Icons.medical_services_outlined, 'Care team connection'),
          ]),
          SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: _confirmSignOut,
              child: Text('Sign out',
                  style: TextStyle(
                      fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _syncCard() {
    return AnimatedBuilder(
      animation: UploadQueue.instance,
      builder: (context, _) {
        final pending = UploadQueue.instance.pendingCount;
        final failed = UploadQueue.instance.failedCount;
        final allClear = pending == 0 && failed == 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: failed > 0 ? AppColors.amberTint : Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                allClear
                    ? Icons.cloud_done_outlined
                    : failed > 0
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_sync_outlined,
                size: 18,
                color: failed > 0
                    ? const Color(0xFF854F0B)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  allClear
                      ? 'All recordings are safely stored'
                      : failed > 0
                          ? '$failed recordings could not be uploaded'
                          : 'Uploading $pending recordings',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (failed > 0)
                TextButton(
                  onPressed: () => UploadQueue.instance.retryFailed(),
                  child: const Text('Retry', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmSignOut() async {
    final pending = UploadQueue.instance.pendingCount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        title: const Text('Sign out?', style: TextStyle(fontSize: 17)),
        content: Text(
          pending > 0
              ? 'There are $pending recordings not yet uploaded. They will stay on this device and be sent when you sign back in.'
              : 'Your recordings on this device will remain saved.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.instance.signOut();
    }
  }

  Future<void> _joinClinic() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        title: const Text('Enter clinic code', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Invite code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (code == null || code.isEmpty) return;

    final outcome = await AuthService.instance.joinClinic(code);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome.ok
              ? 'Clinic code saved.'
              : outcome.message ?? 'Could not save clinic code.',
        ),
      ),
    );
  }

  Widget _profileHeader() {
    return Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.greenTint,
          ),
          alignment: Alignment.center,
          child: const Text('MD',
              style: TextStyle(
                  fontSize: 19,
                  color: AppColors.greenDeep,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: AuthService.instance,
          builder: (context, _) {
            return Text(AuthService.instance.displayName,
                style: TextStyle(fontSize: 16));
          },
        ),
        SizedBox(height: 3),
        Text('Connected with clinic',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
      ],
    );
  }

  Widget _sectionCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() => const Divider(
      height: 0.5, thickness: 0.5, color: AppColors.border, indent: 14);

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }

  Widget _lockedRow(IconData icon, String title) {
    return Opacity(
      opacity: 0.5,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            SizedBox(width: 12),
            Expanded(
              child: Text(title, style: TextStyle(fontSize: 13)),
            ),
            Text('Coming soon',
                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}
