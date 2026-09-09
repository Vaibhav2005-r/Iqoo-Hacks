import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khatasetu/models/ledger_transaction.dart';
import 'package:khatasetu/services/extraction/transaction_draft.dart';
import 'package:khatasetu/widgets/draft_editor.dart';

/// The confirmation card is what makes imperfect ASR and OCR safe, so it is
/// worth testing that it actually renders and actually edits.
void main() {
  Future<TransactionDraft> pump(
    WidgetTester tester,
    TransactionDraft draft, {
    List<String> knownCustomers = const [],
    String rawInputLabel = 'What I heard',
  }) async {
    var latest = draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DraftEditor(
              draft: draft,
              knownCustomers: knownCustomers,
              rawInputLabel: rawInputLabel,
              onChanged: (d) => latest = d,
            ),
          ),
        ),
      ),
    );
    return latest;
  }

  TransactionDraft sample() => TransactionDraft(
        customerName: 'Sharma',
        amount: 500,
        item: 'Rice',
        direction: TxDirection.credit,
        source: TxSource.voice,
        rawInput: 'Sharma ji ko paanch sau ka udhar diya',
      );

  testWidgets('renders the source text and the extracted fields',
      (tester) async {
    await pump(tester, sample());

    expect(find.text('What I heard'), findsOneWidget);
    expect(find.text('Sharma ji ko paanch sau ka udhar diya'), findsOneWidget);
    expect(find.text('Sharma'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
  });

  testWidgets('the source-text label is caller-supplied', (tester) async {
    await pump(tester, sample(), rawInputLabel: 'From the page');
    expect(find.text('From the page'), findsOneWidget);
    expect(find.text('What I heard'), findsNothing);
  });

  testWidgets('correcting the amount updates the draft', (tester) async {
    final draft = sample();
    await pump(tester, draft);

    await tester.enterText(find.widgetWithText(TextField, '500'), '750');
    await tester.pump();

    expect(draft.amount, 750);
  });

  testWidgets('correcting the name updates the draft', (tester) async {
    final draft = sample();
    await pump(tester, draft);

    await tester.enterText(find.widgetWithText(TextField, 'Sharma'), 'Ramesh');
    await tester.pump();

    expect(draft.customerName, 'Ramesh');
  });

  testWidgets('clearing a field marks the draft incomplete rather than zeroing it',
      (tester) async {
    final draft = sample();
    await pump(tester, draft);

    await tester.enterText(find.widgetWithText(TextField, '500'), '');
    await tester.pump();

    expect(draft.amount, isNull);
    expect(draft.isComplete, isFalse);
    expect(draft.missingFields, contains('amount'));
  });

  testWidgets('the direction toggle flips credit to payment', (tester) async {
    final draft = sample();
    await pump(tester, draft);
    expect(draft.direction, TxDirection.credit);

    await tester.tap(find.text('Payment received'));
    await tester.pump();

    expect(draft.direction, TxDirection.payment);
  });

  testWidgets('tapping a known-customer chip fills the name', (tester) async {
    final draft = TransactionDraft(
      amount: 200,
      source: TxSource.voice,
      rawInput: '200 ka udhar',
    );
    await pump(tester, draft, knownCustomers: ['Priya', 'Ramesh']);

    await tester.tap(find.widgetWithText(ActionChip, 'Ramesh'));
    await tester.pump();

    expect(draft.customerName, 'Ramesh');
  });

  testWidgets('warnings from the extractor are shown to the user',
      (tester) async {
    await pump(
      tester,
      TransactionDraft(
        amount: 500,
        source: TxSource.voice,
        rawInput: '500 diya',
        warnings: ['No customer name detected'],
      ),
    );

    expect(find.text('No customer name detected'), findsOneWidget);
  });
}
