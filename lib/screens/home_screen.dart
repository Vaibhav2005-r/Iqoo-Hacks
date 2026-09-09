import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../state/ledger_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import 'camera_scan_screen.dart';
import 'credit_passport_screen.dart';
import 'customer_detail_screen.dart';
import 'voice_entry_screen.dart';

/// Today's position, the two capture actions, and the customer list.
///
/// "Speak an entry" is the primary CTA and is deliberately oversized: it is
/// the action the product exists for, and the user may be holding a bag of
/// rice in the other hand.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final LedgerController controller;

  Future<void> _openVoiceEntry(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VoiceEntryScreen(controller: controller),
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry saved to your khata')),
      );
    }
  }

  Future<void> _openScan(BuildContext context) async {
    final count = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => CameraScanScreen(controller: controller),
      ),
    );
    if (count != null && count > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count ${count == 1 ? 'entry' : 'entries'} added'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final shop = controller.shop;
        final balances = controller.balances;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shop?.name ?? 'KhataSetu'),
                if (shop != null)
                  Text(
                    shop.ownerName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Credit Passport',
                icon: const Icon(Icons.badge_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CreditPassportScreen(controller: controller),
                  ),
                ),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: controller.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _SummaryCard(controller: controller),
                const SizedBox(height: 16),
                _CaptureActions(
                  onSpeak: () => _openVoiceEntry(context),
                  onScan: () => _openScan(context),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text(
                      'Customers',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    if (balances.isNotEmpty)
                      Text(
                        '${balances.length}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (balances.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.people_outline,
                      title: 'No customers yet',
                      message:
                          'Speak your first udhar entry and it will appear here.',
                      action: FilledButton.icon(
                        onPressed: () => _openVoiceEntry(context),
                        icon: const Icon(Icons.mic),
                        label: const Text('Speak an entry'),
                      ),
                    ),
                  )
                else
                  ...balances.map(
                    (b) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CustomerRow(
                        balance: b,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CustomerDetailScreen(
                              controller: controller,
                              customerId: b.customer.id!,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.controller});

  final LedgerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = controller.stats;
    final score = controller.score;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total udhar outstanding',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            Fmt.money(controller.totalOutstanding),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.credit,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat(
                label: 'Entries',
                value: '${stats?.transactionCount ?? 0}',
              ),
              _MiniStat(
                label: 'Customers',
                value: '${controller.balances.length}',
              ),
              _MiniStat(
                label: 'Trust score',
                value: score == null
                    ? '—'
                    : '${score.score.toStringAsFixed(0)}/100',
                highlight: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: highlight ? theme.colorScheme.primary : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureActions extends StatelessWidget {
  const _CaptureActions({required this.onSpeak, required this.onScan});

  final VoidCallback onSpeak;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: FilledButton.icon(
            onPressed: onSpeak,
            icon: const Icon(Icons.mic, size: 26),
            label: const Text(
              'Speak an entry',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan a khata page'),
          ),
        ),
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.balance, required this.onTap});

  final CustomerBalance balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = balance.balance;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              _initials(balance.customer.name),
              style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  balance.customer.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  balance.lastActivity == null
                      ? 'No entries yet'
                      : '${balance.transactionCount} '
                          '${balance.transactionCount == 1 ? 'entry' : 'entries'} · '
                          '${Fmt.relativeDay(balance.lastActivity!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                balance.isSettled ? 'Settled' : Fmt.moneyAbs(value),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.balanceColor(value, theme.colorScheme),
                ),
              ),
              if (!balance.isSettled)
                Text(
                  value > 0 ? 'owes you' : 'in credit',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}
