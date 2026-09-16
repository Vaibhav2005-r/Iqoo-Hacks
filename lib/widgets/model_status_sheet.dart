import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/model_manager.dart';

/// Shows where the app looked for each model and what it found.
///
/// "Speech model not loaded" is true but useless on its own — it does not say
/// which file, which path, or whether the file is there but broken. This turns
/// that into something a person can act on without a laptop and a log viewer.
class ModelStatusSheet extends StatelessWidget {
  const ModelStatusSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const ModelStatusSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      builder: (context, controller) {
        return FutureBuilder<List<ModelStatus>>(
          future: ModelManager.instance.allStatuses(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final statuses = snapshot.data!;

            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                Text(
                  'On-device models',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Speech and language models are copied onto the phone '
                  'separately — they are too large to ship inside the app. '
                  'Text recognition is built in and always works.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                ...statuses.map((s) => _StatusTile(status: s)),
                const SizedBox(height: 20),
                _PushInstructions(
                  directory: statuses.isEmpty
                      ? ''
                      : statuses.first.expectedPath
                          .substring(0, statuses.first.expectedPath.lastIndexOf('/')),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.status});

  final ModelStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = status.isUsable;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.error_outline,
                  size: 18,
                  color: ok ? const Color(0xFF1B7A43) : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  ok ? status.sizeLabel : 'not ready',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (!ok) ...[
              const SizedBox(height: 6),
              Text(
                status.problem ?? 'not found',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            SelectableText(
              status.expectedPath,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _PushInstructions extends StatelessWidget {
  const _PushInstructions({required this.directory});

  final String directory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final command = 'adb push ggml-tiny.bin $directory/';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'To add the speech model',
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceTint.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            command,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Command copied')),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
          ),
        ),
      ],
    );
  }
}
