import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../models/ledger_transaction.dart';
import '../state/ledger_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';

/// One customer's running balance and full history.
///
/// Entries are grouped by day, the way the paper khata they replace is.
class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({
    super.key,
    required this.controller,
    required this.customerId,
  });

  final LedgerController controller;
  final int customerId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        CustomerBalance? found;
        for (final b in controller.balances) {
          if (b.customer.id == customerId) {
            found = b;
            break;
          }
        }
        final entry = found;

        if (entry == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Customer not found',
              message: 'This customer may have been removed.',
            ),
          );
        }

        final transactions = controller.allTransactions
            .where((t) => t.customerId == customerId)
            .toList();

        return Scaffold(
          appBar: AppBar(title: Text(entry.customer.name)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _BalanceCard(balance: entry),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    'History',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  if (transactions.isNotEmpty)
                    Text(
                      'Hold an entry to delete',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (transactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No entries yet',
                    message: 'Entries for this customer will appear here.',
                  ),
                )
              else
                ..._buildGroupedHistory(context, transactions),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildGroupedHistory(
    BuildContext context,
    List<LedgerTransaction> transactions,
  ) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    String? currentDay;

    for (final tx in transactions) {
      final day = Fmt.relativeDay(tx.createdAt);
      if (day != currentDay) {
        currentDay = day;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6, left: 4),
            child: Text(
              day,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _TransactionRow(
            transaction: tx,
            onDelete: () => _confirmDelete(context, tx),
          ),
        ),
      );
    }
    return widgets;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    LedgerTransaction tx,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(
          '${tx.direction.label} · ${Fmt.money(tx.amount)}'
          '${tx.itemDescription == null ? '' : ' · ${tx.itemDescription}'}\n\n'
          'This will change the balance and the trust score.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && tx.id != null) {
      await controller.deleteTransaction(tx.id!);
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final CustomerBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = balance.balance;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            balance.isSettled
                ? 'Balance'
                : value > 0
                    ? 'Owes you'
                    : 'You owe',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            balance.isSettled ? 'Settled' : Fmt.moneyAbs(value),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.balanceColor(value, theme.colorScheme),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${balance.transactionCount} '
            '${balance.transactionCount == 1 ? 'entry' : 'entries'}'
            '${balance.lastActivity == null ? '' : ' · last on ${Fmt.fullDate(balance.lastActivity!)}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction, required this.onDelete});

  final LedgerTransaction transaction;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCredit = transaction.direction == TxDirection.credit;
    final color = isCredit ? AppTheme.credit : AppTheme.payment;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // Long-press, not tap: deleting a ledger row changes the balance and
      // the trust score, so it should not be one stray thumb away.
      onLongPress: onDelete,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit ? Icons.arrow_upward : Icons.arrow_downward,
              size: 17,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.itemDescription ?? transaction.direction.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      Fmt.time(transaction.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _SourceChip(source: transaction.source),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '−'}${Fmt.money(transaction.amount)}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks how an entry got in. Voice and scan entries carry provenance so the
/// shopkeeper can tell which rows a machine transcribed.
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});

  final TxSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (source) {
      TxSource.voice => Icons.mic,
      TxSource.cameraScan => Icons.document_scanner_outlined,
      TxSource.manual => Icons.edit_outlined,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          source.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
