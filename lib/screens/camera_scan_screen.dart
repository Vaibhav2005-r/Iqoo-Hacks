import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/ledger_transaction.dart';
import '../services/ai_runtime.dart';
import '../services/extraction/transaction_draft.dart';
import '../services/ocr_service.dart';
import '../state/ledger_controller.dart';
import '../utils/formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/draft_editor.dart';
import '../widgets/empty_state.dart';
import '../widgets/on_device_badge.dart';

enum _Stage { idle, reading, review }

/// Photograph a paper khata page -> on-device OCR -> on-device structuring ->
/// a checkable, editable batch.
///
/// Handwriting OCR gets things wrong; that is expected rather than hidden.
/// Every row arrives unchecked-if-doubtful and fully editable, and the raw
/// OCR text stays one tap away so the shopkeeper can see what the phone read.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key, required this.controller});

  final LedgerController controller;

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> {
  final _picker = ImagePicker();
  final _ocr = OcrService();

  _Stage _stage = _Stage.idle;
  String? _imagePath;
  OcrResult? _ocrResult;
  Duration? _extractTime;
  String? _error;
  bool _saving = false;

  final List<TransactionDraft> _drafts = [];
  final Set<int> _selected = {};

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);

    try {
      final file = await _picker.pickImage(
        source: source,
        // Full-resolution photos slow ML Kit down noticeably without helping
        // recognition on a page of handwriting.
        maxWidth: 2000,
        imageQuality: 90,
      );
      if (file == null) return;
      await _process(file.path);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the camera: $e');
    }
  }

  Future<void> _process(String imagePath) async {
    setState(() {
      _stage = _Stage.reading;
      _imagePath = imagePath;
      _drafts.clear();
      _selected.clear();
    });

    try {
      final ocr = await _ocr.recognise(imagePath);
      if (!mounted) return;

      if (ocr.isEmpty) {
        setState(() {
          _stage = _Stage.idle;
          _error = "I couldn't read any text. Try a straighter, brighter photo.";
        });
        return;
      }

      final stopwatch = Stopwatch()..start();
      final drafts = await AiRuntime.instance.extractBatch(
        // Line structure is the signal on a ledger page, so the line-joined
        // text is passed rather than ML Kit's block-ordered blob.
        ocr.lines.join('\n'),
        knownCustomers: widget.controller.knownCustomerNames,
        source: TxSource.cameraScan,
      );
      stopwatch.stop();
      if (!mounted) return;

      setState(() {
        _ocrResult = ocr;
        _extractTime = stopwatch.elapsed;
        _drafts.addAll(drafts);
        // Only rows the pipeline is actually confident about start checked.
        // Pre-selecting a doubtful row invites a wrong entry saved by reflex.
        for (var i = 0; i < drafts.length; i++) {
          if (drafts[i].isComplete &&
              drafts[i].confidence != DraftConfidence.low) {
            _selected.add(i);
          }
        }
        _stage = _Stage.review;
      });
    } on OcrException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = e.message;
      });
    }
  }

  Future<void> _save() async {
    final chosen = _selected
        .map((i) => _drafts[i])
        .where((d) => d.isComplete)
        .toList();
    if (chosen.isEmpty) return;

    setState(() => _saving = true);
    try {
      final count = await widget.controller.saveDrafts(chosen);
      if (!mounted) return;
      Navigator.of(context).pop(count);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  void _showRawOcr() {
    final ocr = _ocrResult;
    if (ocr == null) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text(
              'What the phone read',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Raw text from on-device OCR, before it was structured.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              ocr.lines.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectableCount = _drafts.where((d) => d.isComplete).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan a khata page'),
        actions: [
          if (_stage == _Stage.review && _ocrResult != null)
            IconButton(
              tooltip: 'See raw OCR text',
              icon: const Icon(Icons.notes_outlined),
              onPressed: _showRawOcr,
            ),
        ],
      ),
      body: SafeArea(
        child: switch (_stage) {
          _Stage.idle => _buildIdle(),
          _Stage.reading => _buildReading(),
          _Stage.review => _buildReview(),
        },
      ),
      bottomNavigationBar: _stage != _Stage.review
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed:
                      (_selected.isEmpty || _saving) ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    _selected.isEmpty
                        ? 'Select entries to add'
                        : 'Add ${_selected.length} of $selectableCount '
                            '${selectableCount == 1 ? 'entry' : 'entries'}',
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildIdle() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_error != null) ...[
          _ErrorBanner(message: _error!),
          const SizedBox(height: 20),
        ],
        const SizedBox(height: 20),
        EmptyState(
          icon: Icons.photo_camera_outlined,
          title: 'Photograph a khata page',
          message: 'Lay the page flat and fill the frame. '
              'Text is read on your phone — the photo never leaves it.',
          action: Column(
            children: [
              SizedBox(
                width: 240,
                child: FilledButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Take a photo'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 240,
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from gallery'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Center(child: OnDeviceBadge(label: 'OCR runs on your phone')),
      ],
    );
  }

  Widget _buildReading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_imagePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_imagePath!),
                width: 160,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Reading the page…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildReview() {
    final theme = Theme.of(context);

    if (_drafts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          EmptyState(
            icon: Icons.search_off,
            title: 'No entries found on this page',
            message: 'The text was read but no rows looked like transactions. '
                'You can check what the phone read, or try another photo.',
            action: OutlinedButton.icon(
              onPressed: () => setState(() => _stage = _Stage.idle),
              icon: const Icon(Icons.refresh),
              label: const Text('Try another photo'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Found ${_drafts.length} possible '
                  '${_drafts.length == 1 ? 'entry' : 'entries'}. '
                  'Check each one before adding.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        if (_ocrResult != null) ...[
          const SizedBox(height: 8),
          Text(
            'Read in ${Fmt.duration(_ocrResult!.processingTime)} · '
            'structured in ${Fmt.duration(_extractTime ?? Duration.zero)} · '
            '${AiRuntime.instance.extractionEngineName}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: 16),
        for (var i = 0; i < _drafts.length; i++) ...[
          _ScanRow(
            index: i,
            draft: _drafts[i],
            selected: _selected.contains(i),
            knownCustomers: widget.controller.knownCustomerNames,
            onSelectedChanged: (value) => setState(() {
              if (value) {
                _selected.add(i);
              } else {
                _selected.remove(i);
              }
            }),
            onDraftChanged: (d) => setState(() {
              _drafts[i] = d;
              // A row completed by hand should not stay silently unchecked.
              if (d.isComplete) _selected.add(i);
            }),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ScanRow extends StatefulWidget {
  const _ScanRow({
    required this.index,
    required this.draft,
    required this.selected,
    required this.knownCustomers,
    required this.onSelectedChanged,
    required this.onDraftChanged,
  });

  final int index;
  final TransactionDraft draft;
  final bool selected;
  final List<String> knownCustomers;
  final ValueChanged<bool> onSelectedChanged;
  final ValueChanged<TransactionDraft> onDraftChanged;

  @override
  State<_ScanRow> createState() => _ScanRowState();
}

class _ScanRowState extends State<_ScanRow> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Rows that need attention open by default; clean rows stay collapsed so
    // a good scan is a fast scroll-and-confirm.
    _expanded = !widget.draft.isComplete ||
        widget.draft.confidence == DraftConfidence.low;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;

    return AppCard(
      padding: EdgeInsets.zero,
      borderColor: widget.selected ? theme.colorScheme.primary : null,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
              child: Row(
                children: [
                  Checkbox(
                    value: widget.selected,
                    onChanged: draft.isComplete
                        ? (v) => widget.onSelectedChanged(v ?? false)
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          draft.customerName ?? 'Name needed',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: draft.customerName == null
                                ? theme.colorScheme.error
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            draft.amount == null
                                ? 'Amount needed'
                                : Fmt.money(draft.amount!),
                            draft.direction.label,
                            if (draft.item != null) draft.item!,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: DraftEditor(
                draft: draft,
                knownCustomers: widget.knownCustomers,
                onChanged: widget.onDraftChanged,
                rawInputLabel: 'From the page',
                dense: true,
                flat: true,
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
