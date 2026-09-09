import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ledger_transaction.dart';
import '../services/extraction/transaction_draft.dart';
import 'app_card.dart';

/// Editable confirmation card for one extracted entry.
///
/// This widget is the product's answer to imperfect ASR and OCR. Every field
/// the pipeline guessed is a live input, so a wrong guess costs one tap to fix
/// rather than blocking the entry. It is intentionally the *only* path into
/// the ledger from voice or camera — nothing is ever written unreviewed.
class DraftEditor extends StatefulWidget {
  const DraftEditor({
    super.key,
    required this.draft,
    required this.onChanged,
    this.knownCustomers = const [],
    this.showRawInput = true,
    this.rawInputLabel = 'What I heard',
    this.dense = false,
    this.flat = false,
  });

  final TransactionDraft draft;
  final ValueChanged<TransactionDraft> onChanged;
  final List<String> knownCustomers;
  final bool showRawInput;

  /// Header over the source text. "What I heard" for voice, "From the page"
  /// for a scan — the wording has to match where the text actually came from.
  final String rawInputLabel;

  final bool dense;

  /// Drop the card chrome when already nested inside one.
  final bool flat;

  @override
  State<DraftEditor> createState() => _DraftEditorState();
}

class _DraftEditorState extends State<DraftEditor> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _item;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.draft.customerName ?? '');
    _amount = TextEditingController(
      text: widget.draft.amount == null ? '' : _formatAmount(widget.draft.amount!),
    );
    _item = TextEditingController(text: widget.draft.item ?? '');
  }

  static String _formatAmount(double value) =>
      value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(2);

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _item.dispose();
    super.dispose();
  }

  void _push() {
    widget.draft
      ..customerName = _name.text.trim().isEmpty ? null : _name.text.trim()
      ..amount = double.tryParse(_amount.text.trim())
      ..item = _item.text.trim().isEmpty ? null : _item.text.trim();
    widget.onChanged(widget.draft);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final gap = widget.dense ? 10.0 : 14.0;

    final body = Padding(
      padding: EdgeInsets.all(widget.dense ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showRawInput && draft.rawInput != null) ...[
            _HeardRow(text: draft.rawInput!, label: widget.rawInputLabel),
            SizedBox(height: gap),
          ],
          _DirectionToggle(
            direction: draft.direction,
            onChanged: (d) {
              setState(() => draft.direction = d);
              widget.onChanged(draft);
            },
          ),
          SizedBox(height: gap),
          _CustomerField(
            controller: _name,
            knownCustomers: widget.knownCustomers,
            onChanged: (_) => _push(),
          ),
          SizedBox(height: gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                  ),
                  onChanged: (_) => _push(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _item,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Item (optional)',
                  ),
                  onChanged: (_) => _push(),
                ),
              ),
            ],
          ),
          if (draft.warnings.isNotEmpty) ...[
            SizedBox(height: gap),
            ...draft.warnings.map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        w,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (widget.flat) return body;
    return AppCard(padding: EdgeInsets.zero, child: body);
  }
}

/// Source-text line. Showing the transcript verbatim is what makes a
/// mistake legible instead of mysterious.
class _HeardRow extends StatelessWidget {
  const _HeardRow({required this.text, required this.label});

  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceTint.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _DirectionToggle extends StatelessWidget {
  const _DirectionToggle({required this.direction, required this.onChanged});

  final TxDirection direction;
  final ValueChanged<TxDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TxDirection>(
      segments: const [
        ButtonSegment(
          value: TxDirection.credit,
          label: Text('Udhar given'),
          icon: Icon(Icons.arrow_upward, size: 16),
        ),
        ButtonSegment(
          value: TxDirection.payment,
          label: Text('Payment received'),
          icon: Icon(Icons.arrow_downward, size: 16),
        ),
      ],
      selected: {direction},
      showSelectedIcon: false,
      onSelectionChanged: (set) => onChanged(set.first),
    );
  }
}

/// Name field with suggestions from the existing roster, so repeat customers
/// keep one consistent spelling instead of accumulating variants.
class _CustomerField extends StatelessWidget {
  const _CustomerField({
    required this.controller,
    required this.knownCustomers,
    required this.onChanged,
  });

  final TextEditingController controller;
  final List<String> knownCustomers;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Customer',
            prefixIcon: Icon(Icons.person_outline),
          ),
          onChanged: onChanged,
        ),
        if (knownCustomers.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: knownCustomers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final name = knownCustomers[i];
                return ActionChip(
                  label: Text(name, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    controller.text = name;
                    onChanged(name);
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
