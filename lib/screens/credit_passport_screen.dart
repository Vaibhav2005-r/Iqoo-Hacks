import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';

import '../models/trust_score.dart';
import '../services/passport_service.dart';
import '../services/scoring_service.dart';
import '../state/ledger_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';

/// The shareable artefact: a score, the reasoning behind it, and a QR a lender
/// can scan.
///
/// The breakdown is not an optional detail view — it is on the same screen as
/// the number, because a score a shopkeeper cannot interrogate is exactly the
/// thing this product exists to replace.
class CreditPassportScreen extends StatefulWidget {
  const CreditPassportScreen({super.key, required this.controller});

  final LedgerController controller;

  @override
  State<CreditPassportScreen> createState() => _CreditPassportScreenState();
}

class _CreditPassportScreenState extends State<CreditPassportScreen> {
  final _screenshot = ScreenshotController();
  final _passport = const PassportService();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      // Persist a dated snapshot at the moment of sharing, so the ledger has a
      // record of exactly what was handed to a lender.
      await widget.controller.persistScoreSnapshot();

      final bytes = await _screenshot.capture(pixelRatio: 3);
      if (bytes == null) throw StateError('Could not render the passport');

      await _passport.shareImage(
        bytes,
        shopName: widget.controller.shop?.name ?? 'shop',
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final shop = widget.controller.shop;
        final score = widget.controller.score;
        final stats = widget.controller.stats;

        if (shop == null || score == null || stats == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Credit Passport')),
            body: const EmptyState(
              icon: Icons.badge_outlined,
              title: 'Nothing to show yet',
              message: 'Add a few khata entries and your passport will '
                  'build itself.',
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Credit Passport')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (widget.controller.scoreIsProvisional) ...[
                _ProvisionalNotice(count: stats.transactionCount),
                const SizedBox(height: 12),
              ],
              // Only the card itself is captured for sharing; the surrounding
              // chrome and warnings stay in the app.
              Screenshot(
                controller: _screenshot,
                child: _PassportCard(
                  shopName: shop.name,
                  ownerName: shop.ownerName,
                  location: shop.location,
                  snapshot: score,
                  stats: stats,
                  qrPayload: PassportService.buildQrPayload(
                    shop: shop,
                    snapshot: score,
                    stats: stats,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'How this score is built',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Every point comes from your own ledger. Nothing is guessed, '
                'and nothing is sent anywhere.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              ...score.components.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ComponentRow(component: c),
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.ios_share),
                label: const Text('Share passport'),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The card that actually gets rasterised and shared.
class _PassportCard extends StatelessWidget {
  const _PassportCard({
    required this.shopName,
    required this.ownerName,
    required this.location,
    required this.snapshot,
    required this.stats,
    required this.qrPayload,
  });

  final String shopName;
  final String ownerName;
  final String location;
  final TrustScoreSnapshot snapshot;
  final LedgerStats stats;
  final String qrPayload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B4965), Color(0xFF13324A)],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [ownerName, if (location.isNotEmpty) location].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'KhataSetu',
                  style: TextStyle(
                    color: Color(0xFF2A1A00),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TRUST SCORE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white60,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${snapshot.displayScore}',
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/ 850',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    snapshot.band.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // The honest 0-100 stays on the card next to the familiar
                  // 300-850 rescaling, so the presentation never hides the
                  // actual computed value.
                  Text(
                    '${snapshot.score.toStringAsFixed(0)} of 100 points earned',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: qrPayload,
                  version: QrVersions.auto,
                  size: 84,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  // Ledger figures are worth a little redundancy: medium EC
                  // survives a scuffed screen without inflating the density.
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              _PassportStat(
                label: 'Credit given',
                value: Fmt.money(stats.totalCreditExtended),
              ),
              _PassportStat(
                label: 'Repaid',
                value: Fmt.money(stats.totalRepaid),
              ),
              _PassportStat(
                label: 'Customers',
                value: '${stats.customerCount}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _PassportStat(
                label: 'Entries',
                value: '${stats.transactionCount}',
              ),
              _PassportStat(
                label: 'History',
                value: '${stats.historyDays} days',
              ),
              _PassportStat(
                label: 'Outstanding',
                value: Fmt.money(stats.outstanding),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(
                Icons.phonelink_lock_outlined,
                size: 13,
                color: Colors.white60,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Computed on-device · ${Fmt.fullDate(snapshot.computedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PassportStat extends StatelessWidget {
  const _PassportStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// One scoring component with its bar and its plain-language reason.
class _ComponentRow extends StatelessWidget {
  const _ComponentRow({required this.component});

  final ScoreComponent component;

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
              Expanded(
                child: Text(
                  component.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${component.earned.toStringAsFixed(0)}'
                ' / ${component.maxPoints.toStringAsFixed(0)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: component.ratio,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceTint.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            component.explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while the ledger is too thin for the score to mean much.
///
/// Saying so is the point: a confident-looking number built on four entries
/// would be the same dishonesty this product is meant to fix.
class _ProvisionalNotice extends StatelessWidget {
  const _ProvisionalNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Provisional score — based on only $count '
              '${count == 1 ? 'entry' : 'entries'} so far. '
              'It becomes meaningful as your khata grows.',
              style: TextStyle(
                color: scheme.onTertiaryContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
