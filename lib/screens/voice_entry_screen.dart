import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../models/ledger_transaction.dart';
import '../services/ai_runtime.dart';
import '../services/asr/asr_service.dart';
import '../services/asr/audio_recorder_service.dart';
import '../services/extraction/transaction_draft.dart';
import '../state/ledger_controller.dart';
import '../utils/formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/draft_editor.dart';
import '../widgets/on_device_badge.dart';

enum _Stage { idle, recording, transcribing, extracting, review }

/// Record -> on-device transcript -> on-device extraction -> editable
/// confirmation -> save.
///
/// Every stage is visible and every stage is recoverable: if speech isn't
/// available the same screen accepts typed input, and if extraction guesses
/// wrong the confirmation card is already editable.
class VoiceEntryScreen extends StatefulWidget {
  const VoiceEntryScreen({super.key, required this.controller});

  final LedgerController controller;

  @override
  State<VoiceEntryScreen> createState() => _VoiceEntryScreenState();
}

class _VoiceEntryScreenState extends State<VoiceEntryScreen> {
  final _recorder = AudioRecorderService();
  final _typed = TextEditingController();

  _Stage _stage = _Stage.idle;
  TransactionDraft? _draft;
  String? _error;
  String _language = 'hi';

  Duration? _asrTime;
  Duration? _extractTime;
  String? _transcript;

  StreamSubscription<Amplitude>? _amplitudeSub;
  double _amplitude = 0;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  bool get _asrAvailable => AiRuntime.instance.hasAsr;

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _elapsedTimer?.cancel();
    _recorder.dispose();
    _typed.dispose();
    super.dispose();
  }

  // --- Recording -----------------------------------------------------------

  Future<void> _startRecording() async {
    setState(() {
      _error = null;
      _draft = null;
      _transcript = null;
      _elapsed = Duration.zero;
    });

    try {
      await _recorder.start();
      if (!mounted) return;
      setState(() => _stage = _Stage.recording);

      _amplitudeSub = _recorder.amplitudeStream().listen((amp) {
        if (!mounted) return;
        // Map roughly -45..0 dBFS onto 0..1 for the waveform.
        final normalised = ((amp.current + 45) / 45).clamp(0.0, 1.0);
        setState(() => _amplitude = normalised);
      });

      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
      });
    } on AudioRecordingException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = 'Could not start recording: $e';
      });
    }
  }

  Future<void> _stopAndProcess() async {
    _amplitudeSub?.cancel();
    _elapsedTimer?.cancel();
    _amplitudeSub = null;
    _elapsedTimer = null;

    final path = await _recorder.stop();
    if (!mounted) return;

    if (path == null) {
      setState(() {
        _stage = _Stage.idle;
        _error = 'That recording was too short. Hold on a moment longer.';
      });
      return;
    }

    await _transcribeAndExtract(path);
  }

  Future<void> _transcribeAndExtract(String wavPath) async {
    setState(() => _stage = _Stage.transcribing);

    final asr = AiRuntime.instance.asr;
    if (asr == null) {
      setState(() {
        _stage = _Stage.idle;
        _error = 'Speech model is not loaded. Type the entry instead.';
      });
      return;
    }

    try {
      final result = await asr.transcribe(wavPath, language: _language);
      if (!mounted) return;

      if (result.isEmpty) {
        setState(() {
          _stage = _Stage.idle;
          _error = "I couldn't hear anything. Try again, a little closer.";
        });
        return;
      }

      setState(() {
        _transcript = result.text;
        _asrTime = result.processingTime;
      });
      await _extract(result.text);
    } on AsrException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = e.message;
      });
    } finally {
      // The clip has served its purpose; no audio is retained.
      unawaited(File(wavPath).delete().catchError((_) => File(wavPath)));
    }
  }

  Future<void> _extract(String text) async {
    setState(() => _stage = _Stage.extracting);
    final stopwatch = Stopwatch()..start();

    final draft = await AiRuntime.instance.extractSingle(
      text,
      knownCustomers: widget.controller.knownCustomerNames,
      source: TxSource.voice,
    );
    stopwatch.stop();
    if (!mounted) return;

    setState(() {
      _draft = draft;
      _extractTime = stopwatch.elapsed;
      _stage = _Stage.review;
    });
  }

  Future<void> _submitTyped() async {
    final text = _typed.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _transcript = text;
      _asrTime = null;
      _error = null;
    });
    await _extract(text);
  }

  // --- Saving --------------------------------------------------------------

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || !draft.isComplete) return;

    try {
      await widget.controller.saveDraft(draft);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  void _reset() {
    setState(() {
      _stage = _Stage.idle;
      _draft = null;
      _transcript = null;
      _error = null;
      _typed.clear();
    });
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speak an entry'),
        actions: [
          if (_stage == _Stage.idle || _stage == _Stage.review)
            PopupMenuButton<String>(
              icon: const Icon(Icons.translate),
              tooltip: 'Language',
              initialValue: _language,
              onSelected: (v) => setState(() => _language = v),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'hi', child: Text('हिंदी (Hindi)')),
                PopupMenuItem(value: 'en', child: Text('English')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                _ErrorBanner(message: _error!),
                const SizedBox(height: 16),
              ],
              if (_stage == _Stage.review)
                ..._buildReview()
              else
                ..._buildCapture(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCapture() {
    final theme = Theme.of(context);
    final busy = _stage == _Stage.transcribing || _stage == _Stage.extracting;

    return [
      const SizedBox(height: 12),
      Center(
        child: Text(
          switch (_stage) {
            _Stage.recording => 'Listening…',
            _Stage.transcribing => 'Reading your words…',
            _Stage.extracting => 'Understanding the entry…',
            _ => 'Tap and say the entry',
          },
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Center(
        child: Text(
          _stage == _Stage.recording
              ? _formatElapsed(_elapsed)
              : 'For example: "Sharma ji ko paanch sau ka udhar diya"',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 32),
      Center(
        child: _RecordButton(
          stage: _stage,
          amplitude: _amplitude,
          enabled: _asrAvailable && !busy,
          onTap: _stage == _Stage.recording ? _stopAndProcess : _startRecording,
        ),
      ),
      const SizedBox(height: 28),
      Center(
        child: OnDeviceBadge(
          label: _asrAvailable
              ? 'Speech recognised on your phone'
              : 'Speech model not loaded',
          icon: _asrAvailable ? Icons.mic_none : Icons.mic_off_outlined,
        ),
      ),
      const SizedBox(height: 32),
      // Always available, not just as an error path: typing is faster than
      // speaking in a noisy shop, and it keeps the flow usable when the
      // speech model isn't on the device.
      const Row(
        children: [
          Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('or type it', style: TextStyle(fontSize: 12)),
          ),
          Expanded(child: Divider()),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _typed,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'Sharma ji ko 500 ka udhar diya',
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: busy ? null : _submitTyped,
          ),
        ),
        onSubmitted: (_) => busy ? null : _submitTyped(),
      ),
    ];
  }

  List<Widget> _buildReview() {
    final draft = _draft!;
    final theme = Theme.of(context);

    return [
      DraftEditor(
        draft: draft,
        knownCustomers: widget.controller.knownCustomerNames,
        onChanged: (d) => setState(() => _draft = d),
      ),
      const SizedBox(height: 16),
      _PipelineTrace(
        transcript: _transcript,
        asrTime: _asrTime,
        extractTime: _extractTime,
        asrEngine: AiRuntime.instance.asrEngineName,
        extractEngine: AiRuntime.instance.extractionEngineName,
      ),
      const SizedBox(height: 20),
      if (!draft.isComplete)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Add the ${draft.missingFields.join(' and ')} to save.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      FilledButton.icon(
        onPressed: draft.isComplete ? _save : null,
        icon: const Icon(Icons.check),
        label: const Text('Save to khata'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _reset,
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      ),
    ];
  }

  static String _formatElapsed(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Large tap target with a live amplitude ring — the shopkeeper needs to see
/// at a glance that the phone is actually hearing them.
class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.stage,
    required this.amplitude,
    required this.enabled,
    required this.onTap,
  });

  final _Stage stage;
  final double amplitude;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recording = stage == _Stage.recording;
    final busy = stage == _Stage.transcribing || stage == _Stage.extracting;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 148 + (recording ? amplitude * 36 : 0),
        height: 148 + (recording ? amplitude * 36 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: !enabled
              ? scheme.surfaceTint.withValues(alpha: 0.08)
              : recording
                  ? scheme.error
                  : scheme.primary,
          boxShadow: recording
              ? [
                  BoxShadow(
                    color: scheme.error.withValues(alpha: 0.25),
                    blurRadius: 24 + amplitude * 20,
                    spreadRadius: amplitude * 8,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  recording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 58,
                  color: enabled ? Colors.white : scheme.outline,
                ),
        ),
      ),
    );
  }
}

/// Shows exactly what ran and how long it took.
///
/// Kept in the shipped UI rather than behind a debug flag: it is the honest
/// evidence that inference happened on the phone, and it is what makes the
/// "no cloud call" claim checkable rather than asserted.
class _PipelineTrace extends StatelessWidget {
  const _PipelineTrace({
    required this.transcript,
    required this.asrTime,
    required this.extractTime,
    required this.asrEngine,
    required this.extractEngine,
  });

  final String? transcript;
  final Duration? asrTime;
  final Duration? extractTime;
  final String asrEngine;
  final String extractEngine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.memory_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'On-device pipeline',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (asrTime != null)
            _TraceRow(
              label: 'Speech to text',
              value: asrEngine,
              time: Fmt.duration(asrTime!),
            ),
          if (extractTime != null)
            _TraceRow(
              label: 'Entry extraction',
              value: extractEngine,
              time: Fmt.duration(extractTime!),
            ),
        ],
      ),
    );
  }
}

class _TraceRow extends StatelessWidget {
  const _TraceRow({
    required this.label,
    required this.value,
    required this.time,
  });

  final String label;
  final String value;
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            flex: 4,
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            time,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
