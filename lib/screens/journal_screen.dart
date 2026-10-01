import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/recorder_service.dart';
import '../services/upload_queue.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_visuals.dart';

/// Daily journal screen.
///
/// The design is intentionally different from the deeper assessment screen:
///  - warm gradient background, fully rounded cards, soft breathing motion.
///  - a daily prompt stays visible while recording so users can stay in flow.
///  - start recording immediately without any extra preparation steps.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _recorder = RecorderService.instance;
  final _storage = StorageService.instance;

  StreamSubscription<double>? _levelSub;
  Timer? _ticker;

  final List<double> _levels = [];
  Duration _elapsed = Duration.zero;
  bool _isRecording = false;
  bool _isSaving = false;
  bool _isStarting = false;
  String? _errorMessage;

  late final String _prompt = DailyPrompt.forDate(DateTime.now());

  @override
  void dispose() {
    _levelSub?.cancel();
    _ticker?.cancel();
    if (_isRecording) _recorder.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_isStarting) return;
    setState(() {
      _isStarting = true;
      _errorMessage = null;
    });

    try {
      await _recorder.start(prefix: 'journal');
    } on RecorderPermissionDenied {
      setState(() {
        _isStarting = false;
        _errorMessage = 'I need microphone access to record your voice.';
      });
      return;
    } catch (e, stack) {
      print('Recording start error: $e\n$stack');
      setState(() {
        _isStarting = false;
        _errorMessage = 'Recording could not start. Please try again.';
      });
      return;
    }

    _levelSub = _recorder.levelStream.listen((level) {
      if (!mounted) return;
      setState(() {
        _levels.add(level);
        if (_levels.length > 60) _levels.removeAt(0);
      });
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });

    setState(() {
      _isStarting = false;
      _isRecording = true;
      _elapsed = Duration.zero;
      _levels.clear();
    });
  }

  Future<void> _finish() async {
    setState(() => _isSaving = true);

    await _levelSub?.cancel();
    _ticker?.cancel();

    final result = await _recorder.stop();

    if (!mounted) return;

    // Kiểm tra kỹ thuật chạy ngầm. Chỉ khi có lỗi thật mới yêu cầu ghi lại —
    // không mở đường cho việc ghi lại vì không ưng nội dung.
    if (!result.isUsable) {
      setState(() {
        _isRecording = false;
        _isSaving = false;
        _elapsed = Duration.zero;
        _levels.clear();
        _errorMessage = result.check.message;
      });
      return;
    }

    final entry = JournalEntry(
      id: const Uuid().v4(),
      recordedAt: DateTime.now(),
      audioPath: result.path,
      duration: result.duration,
    );
    await _storage.saveEntry(entry);

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isSaving = false;
    });

    final tag = await _showTagSheet(entry);

    // Đưa vào hàng đợi thay vì gọi API ngay: người dùng thường ghi ở nơi
    // sóng yếu, và mất bản ghi vì rớt mạng là mất dữ liệu không tái tạo được.
    await UploadQueue.instance.enqueue(
      UploadJob(
        id: entry.id,
        audioPath: entry.audioPath,
        recordedAt: entry.recordedAt,
        kind: 'journal',
        selfTag: tag?.id,
      ),
    );

    if (mounted) Navigator.of(context).pop(true);
  }

  /// After recording, prompt the user to tag their entry with a mood.
  /// This step is optional and not scoring-based.
  Future<MoodTag?> _showTagSheet(JournalEntry entry) async {
    final tag = await showModalBottomSheet<MoodTag>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MoodTagSheet(),
    );

    if (tag != null) {
      await _storage.updateEntry(entry.copyWith(selfTag: tag));
    }
    return tag;
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        DateFormat("EEEE, d MMMM", 'en').format(DateTime.now());

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: getJournalGradient(context)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              children: [
                _header(dateLabel),
                const Spacer(flex: 2),
                _promptBlock(),
                const Spacer(flex: 2),
                _visual(),
                const SizedBox(height: 18),
                _timer(),
                Spacer(flex: 3),
                if (_errorMessage != null) _errorBanner(),
                _actionButton(),
                SizedBox(height: 12),
                Text(
                  _isRecording
                      ? 'Take your time — it is okay to pause'
                      : 'About a minute is enough',
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(String dateLabel) {
    return Row(
      children: [
        IconButton(
          onPressed: () async {
            if (_isRecording) await _recorder.cancel();
            if (mounted) Navigator.of(context).pop(false);
          },
          icon: Icon(Icons.chevron_left,
              color: Theme.of(context).colorScheme.onSurfaceVariant, size: 26),
        ),
        Expanded(
          child: Text(
            dateLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _promptBlock() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome,
                  size: 13, color: Color(0xFFB07D3F)),
              const SizedBox(width: 6),
              const Text('Today\'s prompt',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.amberInk,
                    letterSpacing: 0.2,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _prompt,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ],
    );
  }

  Widget _visual() {
    return BreathingCircle(
      active: _isRecording,
      child: _isRecording
          ? LiveWaveform(
              levels: _levels,
              palette: LiveWaveform.warmPalette,
            )
          : Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
              ),
              child: const Icon(Icons.mic_none_rounded,
                  size: 27, color: AppColors.greenDeep),
            ),
    );
  }

  Widget _timer() {
    return AnimatedOpacity(
      duration: Duration(milliseconds: 250),
      opacity: _isRecording ? 1 : 0,
      child: Text(
        formatDuration(_elapsed),
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.amberTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(
        _errorMessage!,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Color(0xFF633806)),
      ),
    );
  }

  Widget _actionButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _isSaving
            ? null
            : _isRecording
                ? _finish
                : _start,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.greenDeep,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          elevation: 0,
        ),
        child: _isSaving
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Theme.of(context).colorScheme.surface),
              )
            : Text(
                _isRecording ? 'I am done recording' : 'Start',
                style: const TextStyle(fontSize: 15),
              ),
      ),
    );
  }
}

/// Bảng chọn nhãn cảm xúc, hiện sau khi ghi xong.
class _MoodTagSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: 20),
          Text('Entry saved for today',
              style: TextStyle(fontSize: 17)),
          SizedBox(height: 6),
          Text(
            'Would you like to add a quick mood tag for today?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: MoodTag.all
                .map((tag) => ActionChip(
                      avatar: Icon(tag.icon,
                          size: 16, color: AppColors.greenDeep),
                      label: Text(tag.label,
                          style: const TextStyle(fontSize: 13)),
                      backgroundColor: AppColors.greenTint,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                      ),
                      onPressed: () => Navigator.of(context).pop(tag),
                    ))
                .toList(),
          ),
          SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Save for later',
                style: TextStyle(
                    fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
          ),
        ],
      ),
    );
  }
}
