import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/ai_runtime.dart';
import 'state/ledger_controller.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KhataSetuApp());
}

class KhataSetuApp extends StatefulWidget {
  const KhataSetuApp({super.key});

  @override
  State<KhataSetuApp> createState() => _KhataSetuAppState();
}

class _KhataSetuAppState extends State<KhataSetuApp> {
  final _controller = LedgerController();
  late final Future<void> _boot;

  @override
  void initState() {
    super.initState();
    _boot = _bootstrap();
  }

  /// Model loading and the first DB read happen together, behind one splash.
  ///
  /// AiRuntime.initialise() never throws — a missing model degrades the app to
  /// the rule-based extractor rather than blocking startup.
  Future<void> _bootstrap() async {
    await Future.wait([
      _controller.load(),
      AiRuntime.instance.initialise(),
    ]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KhataSetu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: FutureBuilder<void>(
        future: _boot,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _SplashScreen();
          }
          return ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (_controller.loading) return const _SplashScreen();
              return _controller.isOnboarded
                  ? HomeScreen(controller: _controller)
                  : OnboardingScreen(controller: _controller);
            },
          );
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'KhataSetu',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your khata, your credit history',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
