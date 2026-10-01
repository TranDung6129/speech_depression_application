import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/audio_metrics.dart';
import '../services/auth_service.dart';
import '../services/device_context.dart';
import '../services/quality_gate.dart';
import '../services/recorder_service.dart';
import '../services/session_config.dart';
import '../services/session_metadata.dart';
import '../services/storage_service.dart';
import '../services/upload_queue.dart';
import '../theme/app_theme.dart';
import '../widgets/recording_visuals.dart';

/// Một phiên thu ba phần (WP2 mục 2):
///
///  A. 5 giây im lặng — đo nền nhiễu;
///  B. đọc văn bản cố định — cùng một đoạn cho mọi người, mọi phiên;
///  C. nói tự do theo lời nhắc của hôm nay.
///
/// Mỗi phần là một file riêng. App đếm tiếng nói thật theo thời gian thực
/// (VAD chỉ để đếm, không để cắt); nút hoàn tất chỉ bật khi phần C đã đủ.
/// Dừng sớm thì phiên vẫn được lưu kèm cờ, không bỏ.
///
/// Màn hình này không hiển thị điểm, nhãn hay mức rủi ro ở bất kỳ bước nào.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

enum _Stage { intro, partA, partB, partCReady, partC, analyzing, saved, rejected }

class _SessionScreenState extends State<SessionScreen> {
  final _recorder = RecorderService.instance;
  final _storage = StorageService.instance;

  _Stage _stage = _Stage.intro;
  RecordingContext _context = RecordingContext.home;
  SessionConfig? _config;
  bool _loadingConfig = true;
  String? _errorMessage;

  late String _sessionId;
  late Directory _dir;
  late MicSource _mic;
  late SessionPrompt _prompt;
  final Map<TaskPart, String> _paths = {};
  final Map<TaskPart, DateTime> _startedAt = {};

  StreamSubscription<double>? _dbSub;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  final List<double> _waveLevels = [];
  final List<double> _partALevels = [];
  double _noiseFloorDb = AudioMetrics.dbFloor;
  LiveSpeechCounter? _bCounter;
  LiveSpeechCounter? _cCounter;
  bool _busy = false;

  GateResult? _gate;
  int _sessionCount = 0;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    _ticker?.cancel();
    if (_recorder.isRecording) _recorder.cancel();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final results = await Future.wait([
      SessionConfigService.instance.load(),
      _storage.recordingContext(),
    ]);
    if (!mounted) return;
    setState(() {
      _config = results[0] as SessionConfig?;
      _context = results[1] as RecordingContext;
      _loadingConfig = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Luồng thu
  // ---------------------------------------------------------------------------

  Future<void> _begin() async {
    final config = _config;
    if (config == null || _busy) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    if (!await _recorder.ensurePermission()) {
      setState(() {
        _busy = false;
        _errorMessage = 'Microphone access is needed to record the session.';
      });
      return;
    }

    await _storage.setRecordingContext(_context);
    _mic = await DeviceContext.instance.pickMicSource();
    _sessionId = const Uuid().v4();
    _dir = await RecorderService.sessionDirectory(_sessionId);
    _prompt = config.promptFor(DateTime.now());

    _busy = false;
    await _startPart(TaskPart.a);
    if (!mounted || _stage != _Stage.partA) return;

    // Phần A tự kết thúc sau đúng `part_a_sec` giây.
    final ms = (config.partASec * 1000).round();
    Timer(Duration(milliseconds: ms), () async {
      if (!mounted || _stage != _Stage.partA) return;
      await _stopPart();
      _noiseFloorDb = LiveSpeechCounter.floorFrom(_partALevels);
      _bCounter = LiveSpeechCounter(_noiseFloorDb);
      await _startPart(TaskPart.b);
    });
  }

  Future<void> _startPart(TaskPart part) async {
    final path = '${_dir.path}/part_${part.code}.wav';
    try {
      await _recorder.start(path, _mic);
    } catch (e) {
      debugPrint('Recording start error: $e');
      await _abandon();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.intro;
        _errorMessage = 'Recording could not start. Please try again.';
      });
      return;
    }
    _paths[part] = path;
    _startedAt[part] = DateTime.now();
    _elapsed = Duration.zero;
    _waveLevels.clear();

    _dbSub = _recorder.dbStream.listen((db) {
      if (!mounted) return;
      setState(() {
        switch (part) {
          case TaskPart.a:
            _partALevels.add(db);
          case TaskPart.b:
            _bCounter?.add(db);
          case TaskPart.c:
            _cCounter?.add(db);
        }
        _waveLevels.add(((db + 60) / 60).clamp(0.0, 1.0));
        if (_waveLevels.length > 60) _waveLevels.removeAt(0);
      });
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });

    setState(() {
      _stage = switch (part) {
        TaskPart.a => _Stage.partA,
        TaskPart.b => _Stage.partB,
        TaskPart.c => _Stage.partC,
      };
    });
  }

  Future<void> _stopPart() async {
    await _dbSub?.cancel();
    _dbSub = null;
    _ticker?.cancel();
    await _recorder.stop();
  }

  Future<void> _finishReading() async {
    if (_busy) return;
    _busy = true;
    await _stopPart();
    _cCounter = LiveSpeechCounter(_noiseFloorDb);
    _busy = false;
    if (mounted) setState(() => _stage = _Stage.partCReady);
  }

  Future<void> _finishSession({bool stoppedEarly = false}) async {
    if (_busy) return;
    _busy = true;
    if (_recorder.isRecording) await _stopPart();
    if (mounted) setState(() => _stage = _Stage.analyzing);

    // Phần chưa kịp thu (dừng sớm) được ghi thành WAV rỗng để phiên vẫn đủ
    // ba file, kèm cờ `stopped_early`.
    for (final part in TaskPart.values) {
      if (_paths.containsKey(part)) continue;
      final path = '${_dir.path}/part_${part.code}.wav';
      await File(path).writeAsBytes(AudioMetrics.emptyWav());
      _paths[part] = path;
      _startedAt[part] = DateTime.now();
    }

    final config = _config!;
    final SessionMetrics metrics;
    try {
      metrics = await compute(
        AudioMetrics.measureSessionFiles,
        {for (final e in _paths.entries) e.key.code: e.value},
      );
    } catch (e) {
      debugPrint('Measuring failed: $e');
      await _abandon();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = _Stage.intro;
        _errorMessage = 'The recording could not be read. Please try again.';
      });
      return;
    }

    final gate = QualityGate.evaluate(
      metrics: metrics,
      config: config,
      unprocessedSource: _mic.unprocessed,
      stoppedEarly: stoppedEarly,
    );

    if (gate.rejected) {
      // Im lặng gần như toàn bộ: từ chối phiên, không tính vào lịch.
      await _abandon();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _gate = gate;
        _stage = _Stage.rejected;
      });
      return;
    }

    final device = await DeviceContext.instance.info();
    final deviceId = await DeviceContext.instance.deviceId();
    final startA = _startedAt[TaskPart.a]!;
    final metadata = buildSessionMetadata(
      sessionId: _sessionId,
      userId: AuthService.instance.userId ?? '',
      startedAt: _startedAt,
      timezone: DeviceContext.timezone(startA),
      textId: config.textId,
      promptId: _prompt.id,
      device: device,
      deviceId: deviceId,
      mic: _mic,
      context: _context,
      metrics: metrics,
      belowThreshold: gate.belowThreshold,
      qualityFlags: gate.flags,
    );

    await _storage.saveSession(LocalSession(
      id: _sessionId,
      recordedAt: startA,
      speechSec: gate.speechSec,
      minSpeechSec: config.minSpeechSec,
      qualityFlags: gate.flags,
    ));
    await UploadQueue.instance.enqueue(UploadJob(
      id: _sessionId,
      audioPaths: {for (final e in _paths.entries) e.key.code: e.value},
      metadataJson: jsonEncode(metadata),
      recordedAt: startA,
    ));

    final count = (await _storage.loadSessions()).length;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _gate = gate;
      _sessionCount = count;
      _stage = _Stage.saved;
    });
  }

  /// Bỏ phiên chưa lưu: chỉ dùng khi không có gì để đo (dừng trong phần A,
  /// phiên im lặng, lỗi thu).
  Future<void> _abandon() async {
    await _dbSub?.cancel();
    _ticker?.cancel();
    if (_recorder.isRecording) await _recorder.cancel();
    try {
      if (await _dir.exists()) {
        await _dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _onClose() async {
    switch (_stage) {
      case _Stage.intro:
      case _Stage.saved:
      case _Stage.rejected:
        Navigator.of(context).pop(_stage == _Stage.saved);
        return;
      case _Stage.analyzing:
        return;
      case _Stage.partA:
        await _abandon();
        if (mounted) Navigator.of(context).pop(false);
        return;
      case _Stage.partB:
      case _Stage.partCReady:
      case _Stage.partC:
        final stop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('End the session now?',
                style: TextStyle(fontSize: 17)),
            content: const Text(
              'What you have recorded so far will still be saved.',
              style: TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep going'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('End and save'),
              ),
            ],
          ),
        );
        if (stop == true) await _finishSession(stoppedEarly: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Giao diện
  // ---------------------------------------------------------------------------

  double get _speechSoFar =>
      (_bCounter?.speechSec ?? 0) + (_cCounter?.speechSec ?? 0);

  bool get _partCEnough {
    final c = _config;
    if (c == null) return false;
    return (_cCounter?.speechSec ?? 0) >= c.partCMinSpeechSec &&
        _speechSoFar >= c.minSpeechSec;
  }

  bool get _liveNoisy {
    final c = _config;
    final counter = _stage == _Stage.partC ? _cCounter : _bCounter;
    final snr = counter?.liveSnrDb;
    return c != null && snr != null && snr < c.minSnrDb;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onClose();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(),
                const SizedBox(height: 16),
                Expanded(child: _body()),
                if (_errorMessage != null) ...[
                  _banner(_errorMessage!),
                  const SizedBox(height: 12),
                ],
                _actions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final step = switch (_stage) {
      _Stage.partA => 0,
      _Stage.partB => 1,
      _Stage.partCReady || _Stage.partC => 2,
      _ => -1,
    };
    return Row(
      children: [
        IconButton(
          onPressed: _stage == _Stage.analyzing ? null : _onClose,
          icon: const Icon(Icons.close, size: 20),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Row(
            children: List.generate(3, (i) {
              final done = step > i || _stage == _Stage.saved;
              final active = step == i;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i == 2 ? 0 : 4),
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.blueMid
                        : active
                            ? AppColors.bluePale
                            : AppColors.coolTrack,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _body() {
    return switch (_stage) {
      _Stage.intro => _intro(),
      _Stage.partA => _partA(),
      _Stage.partB => _partB(),
      _Stage.partCReady || _Stage.partC => _partC(),
      _Stage.analyzing => const Center(child: CircularProgressIndicator()),
      _Stage.saved => _saved(),
      _Stage.rejected => _rejected(),
    };
  }

  Widget _intro() {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      children: [
        const Text("Today's session", style: TextStyle(fontSize: 22)),
        const SizedBox(height: 8),
        Text(
          'Three short steps, about two minutes in total. '
          'Find a quiet spot and hold the phone about a hand-width from your mouth.',
          style: TextStyle(fontSize: 13, height: 1.5, color: muted),
        ),
        const SizedBox(height: 20),
        _stepRow(Icons.volume_off_outlined, '1. Five seconds of quiet',
            'We measure the background sound of the room.'),
        _stepRow(Icons.menu_book_outlined, '2. Read a short passage',
            'The same passage every time, at your normal pace.'),
        _stepRow(Icons.record_voice_over_outlined, '3. Talk freely',
            'Answer a simple everyday question in your own words.'),
        const SizedBox(height: 20),
        Text('Where are you recording?',
            style: TextStyle(fontSize: 13, color: muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: RecordingContext.values
              .map((c) => ChoiceChip(
                    label: Text(c.label),
                    selected: _context == c,
                    onSelected: (_) => setState(() => _context = c),
                  ))
              .toList(),
        ),
        if (!_loadingConfig && _config == null) ...[
          const SizedBox(height: 20),
          _banner('The session setup could not be downloaded. '
              'Please connect to the internet once, then try again.'),
        ],
      ],
    );
  }

  Widget _stepRow(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.blueTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: AppColors.blueDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(body,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _partA() {
    final total = _config!.partASec.round();
    final left = (total - _elapsed.inSeconds).clamp(0, total);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Please stay quiet',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 22)),
        const SizedBox(height: 10),
        Text(
          'Measuring the background sound of the room…',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        Text('$left',
            style: const TextStyle(fontSize: 48, color: AppColors.blueDeep)),
      ],
    );
  }

  Widget _partB() {
    final c = _config!;
    return ListView(
      children: [
        _partLabel('Step 2 of 3', 'Read this aloud at your normal pace'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.structuredCard),
          ),
          child: Text(c.text, style: const TextStyle(fontSize: 18, height: 1.6)),
        ),
        const SizedBox(height: 18),
        _liveStatus(),
      ],
    );
  }

  Widget _partC() {
    final ready = _stage == _Stage.partCReady;
    return ListView(
      children: [
        _partLabel('Step 3 of 3', 'Talk freely about this'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.structuredCard),
          ),
          child: Text(_prompt.text,
              style: const TextStyle(fontSize: 18, height: 1.5)),
        ),
        const SizedBox(height: 10),
        Text(
          'There is no right or wrong answer. Pauses are fine.',
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        if (!ready) _liveStatus(),
      ],
    );
  }

  Widget _partLabel(String step, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(step,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontSize: 18)),
      ],
    );
  }

  /// Sóng, đồng hồ, số giây tiếng nói đã đếm và cảnh báo ồn — phần "cổng
  /// chất lượng chạy trực tiếp" của buổi demo (mục 13).
  Widget _liveStatus() {
    final c = _config!;
    final progress = (_speechSoFar / c.minSpeechSec).clamp(0.0, 1.0);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      children: [
        LiveWaveform(
          levels: _waveLevels,
          palette: LiveWaveform.coolPalette,
          barCount: 5,
          maxHeight: 40,
          barWidth: 3,
        ),
        const SizedBox(height: 10),
        Text('Recording · ${formatDuration(_elapsed)}',
            style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 14),
        LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
          backgroundColor: AppColors.coolTrack,
          color: AppColors.blueMid,
        ),
        const SizedBox(height: 6),
        Text(
          'Speaking time ${_speechSoFar.round()} s of ${c.minSpeechSec.round()} s',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 4),
        Text(
          'Room noise ${_noiseFloorDb.round()} dB',
          style: TextStyle(fontSize: 11, color: muted.withValues(alpha: 0.7)),
        ),
        if (_liveNoisy) ...[
          const SizedBox(height: 12),
          _banner('It seems noisy here. If you can, move somewhere quieter '
              'for your next session.'),
        ],
      ],
    );
  }

  Widget _saved() {
    final gate = _gate!;
    final tips = gate.flags.map(guidanceFor).whereType<String>().toList();
    final suggestNew = gate.flags.contains(QualityFlag.lowSnr) ||
        gate.flags.contains(QualityFlag.clipping);
    return ListView(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.blueTint),
          child: const Icon(Icons.check_rounded,
              color: AppColors.blueDeep, size: 28),
        ),
        const SizedBox(height: 16),
        const Text('Session saved, thank you',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        Text(
          'You have recorded $_sessionCount '
          '${_sessionCount == 1 ? 'session' : 'sessions'} so far.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (tips.isEmpty)
          _banner('Recording quality looked good.', positive: true)
        else
          ...tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _banner(t),
              )),
        if (suggestNew) ...[
          const SizedBox(height: 8),
          Text(
            'This session is kept as it is. If you like, you can record one '
            'more new session after moving to a better spot.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _rejected() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.mic_off_outlined, size: 40),
        const SizedBox(height: 16),
        const Text('We could not hear any speaking',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        Text(
          'This session was not saved and does not count. Please check that '
          'nothing is covering the microphone, then start a new session.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _banner(String text, {bool positive = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: positive ? AppColors.greenTint : AppColors.amberTint,
        borderRadius: BorderRadius.circular(AppRadius.structuredButton),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: positive ? AppColors.greenDeep : const Color(0xFF633806),
        ),
      ),
    );
  }

  Widget _actions() {
    final c = _config;
    final (label, onPressed) = switch (_stage) {
      _Stage.intro => (
          'Start',
          (_loadingConfig || c == null || _busy) ? null : _begin,
        ),
      _Stage.partA => ('Measuring…', null),
      _Stage.partB => ("I've finished reading", _finishReading),
      _Stage.partCReady => ('Start talking', () => _startPart(TaskPart.c)),
      _Stage.partC => (
          _partCEnough ? 'Finish' : 'Keep talking a little more',
          _partCEnough ? () => _finishSession() : null,
        ),
      _Stage.analyzing => ('Saving…', null),
      _Stage.saved => ('Done', () => Navigator.of(context).pop(true)),
      _Stage.rejected => ('Close', () => Navigator.of(context).pop(false)),
    };

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blueDeep,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.structuredButton),
          ),
          elevation: 0,
        ),
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
