import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/recorder_service.dart';
import '../services/storage_service.dart';
import '../services/upload_queue.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_visuals.dart';

/// Deep assessment screen.
/// Intentionally distinct from the daily journal:
/// - cool blue palette, neutral background, clear cards with edges.
/// - progress bar splits the session into four clear steps.
/// - the question stays visible while recording.
/// - draft data is auto-saved after each answer to prevent losing progress.
class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({super.key, this.resumeSession});

  /// Active draft, if the user chooses to resume a session.
  final AssessmentSession? resumeSession;

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  final _recorder = RecorderService.instance;
  final _storage = StorageService.instance;

  late AssessmentSession _session;
  StreamSubscription<double>? _levelSub;
  Timer? _ticker;

  final List<double> _levels = [];
  Duration _elapsed = Duration.zero;
  bool _isRecording = false;
  bool _isBusy = false;
  bool _isStarting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _session = widget.resumeSession ??
        AssessmentSession(
          id: const Uuid().v4(),
          startedAt: DateTime.now(),
          lastTouchedAt: DateTime.now(),
          answers: const [],
          status: SessionStatus.draft,
        );
  }

  @override
  void dispose() {
    _levelSub?.cancel();
    _ticker?.cancel();
    if (_isRecording) _recorder.cancel();
    super.dispose();
  }

  int get _currentIndex => _session.nextQuestionIndex ?? 0;
  AssessmentQuestion get _question => AssessmentQuestion.all[_currentIndex];

  Future<void> _startRecording() async {
    if (_isStarting) return;
    setState(() {
      _isStarting = true;
      _errorMessage = null;
    });

    try {
      await _recorder.start(prefix: 'assess_q$_currentIndex');
    } on RecorderPermissionDenied {
      setState(() {
        _isStarting = false;
        _errorMessage = 'I need microphone access to record your answer.';
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

  Future<void> _finishQuestion() async {
    setState(() => _isBusy = true);

    await _levelSub?.cancel();
    _ticker?.cancel();

    final result = await _recorder.stop();
    if (!mounted) return;

    if (!result.isUsable) {
      setState(() {
        _isRecording = false;
        _isBusy = false;
        _elapsed = Duration.zero;
        _levels.clear();
        _errorMessage = result.check.message;
      });
      return;
    }

    final answer = AssessmentAnswer(
      questionIndex: _currentIndex,
      audioPath: result.path,
      duration: result.duration,
      answeredAt: DateTime.now(),
    );

    _session = _session.copyWith(answers: [..._session.answers, answer]);

    await _storage.saveDraft(_session);

    await UploadQueue.instance.enqueue(
      UploadJob(
        id: '${_session.id}_q${answer.questionIndex}',
        audioPath: answer.audioPath,
        recordedAt: answer.answeredAt,
        kind: 'assessment',
        questionIndex: answer.questionIndex,
        sessionId: _session.id,
      ),
    );

    if (!mounted) return;

    if (_session.isComplete) {
      await _storage.completeDraft();
      if (!mounted) return;
      await _showCompletionSheet();
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isRecording = false;
      _isBusy = false;
      _elapsed = Duration.zero;
      _levels.clear();
    });
  }

  Future<void> _confirmExit() async {
    if (_isRecording) {
      await _recorder.cancel();
    }

    if (!mounted) return;

    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.coolSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.structuredCard)),
        title: const Text('Pause here?', style: TextStyle(fontSize: 17)),
        content: Text(
          _session.answeredCount == 0
              ? 'You have not answered any questions yet. You can come back later.'
              : 'Your ${_session.answeredCount} recorded answers have been saved. '
                  'When you return, you can continue from where you left off.',
          style: const TextStyle(
              fontSize: 13, color: AppColors.coolTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pause'),
          ),
        ],
      ),
    );

    if (leave == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _showCompletionSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.blueTint,
              ),
              child: const Icon(Icons.check_rounded,
                  color: AppColors.blueDeep, size: 26),
            ),
            const SizedBox(height: 16),
            const Text('All done, thank you',
                style: TextStyle(fontSize: 17)),
            const SizedBox(height: 8),
            const Text(
              'All four answers have been saved. You do not need to do anything else.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppColors.coolTextSecondary),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blueDeep,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppRadius.structuredButton),
                  ),
                  elevation: 0,
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: AppColors.coolCanvas,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              children: [
                _progressBar(),
                const SizedBox(height: 22),
                _questionCard(),
                const SizedBox(height: 14),
                _recordingCard(),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  _errorBanner(),
                ],
                const Spacer(),
                _actionButton(),
                const SizedBox(height: 12),
                _autosaveNote(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressBar() {
    return Row(
      children: [
        GestureDetector(
          onTap: _confirmExit,
          child: const Icon(Icons.close,
              size: 20, color: AppColors.coolTextSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: List.generate(AssessmentQuestion.total, (i) {
              final done = i < _session.answeredCount;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(
                      right: i == AssessmentQuestion.total - 1 ? 0 : 4),
                  decoration: BoxDecoration(
                    color: done ? AppColors.blueMid : AppColors.coolTrack,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _questionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.coolSurface,
        borderRadius: BorderRadius.circular(AppRadius.structuredCard),
        border: Border.all(color: AppColors.coolBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.blueTint,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Text('${_currentIndex + 1}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.blueDeep,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 7),
              Text('of ${AssessmentQuestion.total} questions',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.coolTextSecondary)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _question.text,
            style: const TextStyle(
              fontSize: 17,
              height: 1.45,
              color: AppColors.coolTextPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _question.hint,
            style: const TextStyle(
                fontSize: 12, color: AppColors.coolTextMuted),
          ),
        ],
      ),
    );
  }

  Widget _recordingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.coolSurface,
        borderRadius: BorderRadius.circular(AppRadius.structuredCard),
        border: Border.all(color: AppColors.coolBorder, width: 0.5),
      ),
      child: Column(
        children: [
          if (_isRecording) ...[
            LiveWaveform(
              levels: _levels,
              palette: LiveWaveform.coolPalette,
              barCount: 5,
              maxHeight: 40,
              barWidth: 3,
            ),
            const SizedBox(height: 12),
            Text('Recording · ${formatDuration(_elapsed)}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.coolTextSecondary)),
          ] else ...[
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.blueTint,
              ),
              child: const Icon(Icons.mic_none_rounded,
                  size: 23, color: AppColors.blueDeep),
            ),
            const SizedBox(height: 10),
            const Text('Tap to answer',
                style: TextStyle(
                    fontSize: 12, color: AppColors.coolTextSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.amberTint,
        borderRadius: BorderRadius.circular(AppRadius.structuredButton),
      ),
      child: Text(
        _errorMessage!,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Color(0xFF633806)),
      ),
    );
  }

  Widget _actionButton() {
    final isLast = _currentIndex == AssessmentQuestion.total - 1;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _isBusy
            ? null
            : _isRecording
                ? _finishQuestion
                : _startRecording,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blueDeep,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.structuredButton),
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
            : Text(
                _isRecording
                    ? (isLast ? 'Complete' : 'Done with this question')
                    : 'Start answering',
                style: const TextStyle(fontSize: 14),
              ),
      ),
    );
  }

  Widget _autosaveNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.save_outlined,
            size: 13, color: AppColors.coolTextMuted),
        const SizedBox(width: 5),
        const Text('Auto-saved — you can leave anytime',
            style: TextStyle(fontSize: 11, color: AppColors.coolTextMuted)),
      ],
    );
  }
}
