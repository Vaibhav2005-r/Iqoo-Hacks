import 'dart:async';
import 'dart:convert';

import 'package:fllama/fllama.dart';

import '../models/ledger_transaction.dart';
import '../services/extraction/transaction_draft.dart';
import '../services/llm/transaction_extractor.dart';
import '../services/model_manager.dart';

/// On-device LLM extraction via llama.cpp (Gemma-2B-it, Q4_K_M GGUF).
///
/// Lives outside lib/ until `scripts/enable_native_ai.sh` copies it in, so an
/// NDK/ABI build failure in `fllama` cannot break compilation of the app.
///
/// NOTE: verify this against the `fllama` revision you actually pin — it is a
/// community package and its API has moved before. The three things to check
/// are the `OpenAiRequest` field names, the `fllamaChat` callback arity, and
/// whether `grammar` is honoured on your build.
class FllamaExtractor implements TransactionExtractor {
  FllamaExtractor({this.contextSize = 2048, this.maxTokens = 256});

  final int contextSize;
  final int maxTokens;

  String? _modelPath;

  @override
  String get engineName => 'Gemma-2B (on-device)';

  @override
  Future<bool> isAvailable() async {
    final status = await ModelManager.instance.llmStatus();
    if (!status.exists) return false;
    _modelPath = status.expectedPath;
    return true;
  }

  /// GBNF grammar pinning the output to exactly the JSON we can parse.
  ///
  /// Constraining the decoder is strictly better than prompting for JSON and
  /// hoping: it removes malformed-JSON failures by construction rather than
  /// catching them afterwards.
  static const _singleGrammar = r'''
root   ::= "{" ws "\"customer_name\":" ws string "," ws "\"amount\":" ws number "," ws "\"item\":" ws (string | "null") "," ws "\"direction\":" ws direction ws "}"
direction ::= "\"CREDIT\"" | "\"PAYMENT\""
string ::= "\"" ([^"\\] | "\\" ["\\/bfnrt])* "\""
number ::= [0-9]+ ("." [0-9]+)?
ws     ::= [ \t\n]*
''';

  static const _batchGrammar = r'''
root   ::= "[" ws (entry (ws "," ws entry)*)? ws "]"
entry  ::= "{" ws "\"customer_name\":" ws string "," ws "\"amount\":" ws number "," ws "\"item\":" ws (string | "null") "," ws "\"direction\":" ws direction ws "}"
direction ::= "\"CREDIT\"" | "\"PAYMENT\""
string ::= "\"" ([^"\\] | "\\" ["\\/bfnrt])* "\""
number ::= [0-9]+ ("." [0-9]+)?
ws     ::= [ \t\n]*
''';

  static const _systemPrompt = '''
You extract shop ledger transactions from spoken Hindi/English text.
Output ONLY valid JSON, no prose.
"CREDIT" means the shopkeeper gave goods or money on credit (udhar) to the customer.
"PAYMENT" means the customer paid back money they owed.
Never invent a customer name that was not mentioned. If a name is not stated, use "".
Amounts are in rupees. Return only the number, no currency symbol.
''';

  @override
  Future<TransactionDraft> extractSingle(
    String text, {
    List<String> knownCustomers = const [],
    TxSource source = TxSource.voice,
  }) async {
    final raw = await _run(
      systemPrompt: _systemPrompt,
      userPrompt: _singlePrompt(text, knownCustomers),
      grammar: _singleGrammar,
    );

    final json = _decodeObject(raw);
    if (json == null) {
      throw const FormatException('LLM returned unparseable JSON');
    }
    return _draftFromJson(json, rawInput: text, source: source);
  }

  @override
  Future<List<TransactionDraft>> extractBatch(
    String text, {
    List<String> knownCustomers = const [],
    TxSource source = TxSource.cameraScan,
  }) async {
    final raw = await _run(
      systemPrompt: _systemPrompt,
      userPrompt: _batchPrompt(text, knownCustomers),
      grammar: _batchGrammar,
      // A page holds many rows, so it needs a bigger budget than one utterance.
      maxTokensOverride: 768,
    );

    final list = _decodeArray(raw);
    if (list == null) {
      throw const FormatException('LLM returned unparseable JSON array');
    }

    return list
        .whereType<Map<String, dynamic>>()
        .map((json) => _draftFromJson(json, rawInput: text, source: source))
        .where((d) => d.amount != null && d.amount! > 0)
        .toList();
  }

  String _singlePrompt(String text, List<String> knownCustomers) {
    final buffer = StringBuffer();
    if (knownCustomers.isNotEmpty) {
      // Showing the existing roster stops the model coining a new spelling
      // for a customer who is already in the ledger.
      buffer.writeln(
        'Existing customers: ${knownCustomers.take(40).join(', ')}.',
      );
      buffer.writeln(
        'If the text refers to one of them, reuse that exact spelling.',
      );
    }
    buffer.writeln('Extract one transaction from this text:');
    buffer.writeln(text);
    return buffer.toString();
  }

  String _batchPrompt(String text, List<String> knownCustomers) {
    final buffer = StringBuffer();
    if (knownCustomers.isNotEmpty) {
      buffer.writeln(
        'Existing customers: ${knownCustomers.take(40).join(', ')}.',
      );
    }
    buffer.writeln(
      'The following is OCR text from a handwritten shop ledger page. '
      'It is noisy. Extract every transaction row you can read as a JSON '
      'array. Skip headers, totals, and rows you cannot read.',
    );
    buffer.writeln(text);
    return buffer.toString();
  }

  Future<String> _run({
    required String systemPrompt,
    required String userPrompt,
    required String grammar,
    int? maxTokensOverride,
  }) async {
    final modelPath = _modelPath;
    if (modelPath == null) {
      throw StateError('Call isAvailable() before extracting');
    }

    final completer = Completer<String>();

    final request = OpenAiRequest(
      modelPath: modelPath,
      maxTokens: maxTokensOverride ?? maxTokens,
      contextSize: contextSize,
      messages: [
        Message(Role.system, systemPrompt),
        Message(Role.user, userPrompt),
      ],
      // Extraction is not a creative task; greedy decoding is both more
      // accurate here and faster.
      temperature: 0.0,
      topP: 1.0,
      presencePenalty: 0.0,
      frequencyPenalty: 0.0,
      // llama.cpp on Android is CPU/Vulkan, not the phone's NPU. Offloading
      // is best-effort and silently ignored when no GPU backend is compiled.
      numGpuLayers: 0,
      grammar: grammar,
    );

    await fllamaChat(request, (response, responseJson, done) {
      if (done && !completer.isCompleted) {
        completer.complete(response);
      }
    });

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('LLM took too long'),
    );
  }

  // --- Parsing -------------------------------------------------------------

  /// Models sometimes wrap JSON in prose or a code fence even when told not
  /// to, so slice to the outermost braces before decoding.
  static Map<String, dynamic>? _decodeObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static List<dynamic>? _decodeArray(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      return decoded is List ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static TransactionDraft _draftFromJson(
    Map<String, dynamic> json, {
    required String rawInput,
    required TxSource source,
  }) {
    final name = (json['customer_name'] as String?)?.trim();
    final rawAmount = json['amount'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse('${rawAmount ?? ''}');
    final item = (json['item'] as String?)?.trim();
    final direction =
        (json['direction'] as String?)?.toUpperCase() == 'PAYMENT'
            ? TxDirection.payment
            : TxDirection.credit;

    return TransactionDraft(
      customerName: (name == null || name.isEmpty) ? null : name,
      amount: (amount != null && amount > 0) ? amount : null,
      item: (item == null || item.isEmpty || item == 'null') ? null : item,
      direction: direction,
      source: source,
      rawInput: rawInput,
      confidence: DraftConfidence.medium,
    );
  }
}
