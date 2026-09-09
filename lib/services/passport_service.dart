import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/shop.dart';
import '../models/trust_score.dart';
import 'scoring_service.dart';

/// Builds and shares the Credit Passport.
class PassportService {
  const PassportService();

  /// Payload encoded into the passport QR.
  ///
  /// The QR carries the data itself rather than a URL, because there is no
  /// server and the whole claim of this product is that it works offline. A
  /// lender scanning it gets the figures directly, with no lookup and nothing
  /// to trust but the code in their hand.
  ///
  /// Keys are short to keep the QR low-density and easy to scan off a cracked
  /// phone screen in a bank branch.
  static String buildQrPayload({
    required Shop shop,
    required TrustScoreSnapshot snapshot,
    required LedgerStats stats,
  }) {
    final payload = {
      'v': 1,
      'shop': shop.name,
      'owner': shop.ownerName,
      'loc': shop.location,
      'score': snapshot.score.round(),
      'display': snapshot.displayScore,
      'tx': stats.transactionCount,
      'cust': stats.customerCount,
      'days': stats.historyDays,
      'credit': stats.totalCreditExtended.round(),
      'repaid': stats.totalRepaid.round(),
      'out': stats.outstanding.round(),
      'gen': snapshot.computedAt.toIso8601String().split('T').first,
      'parts': {
        for (final c in snapshot.components) c.key: c.earned.round(),
      },
    };
    return jsonEncode(payload);
  }

  /// Decodes a scanned passport back into a readable map.
  ///
  /// Used by the lender-side view; kept here so both sides share one
  /// definition of the format.
  static Map<String, dynamic>? decodeQrPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['v'] != 1) return null;
      return decoded;
    } on FormatException {
      return null;
    }
  }

  /// Writes rasterised passport bytes to a temp file and opens the share
  /// sheet.
  Future<void> shareImage(Uint8List bytes, {required String shopName}) async {
    final dir = await getTemporaryDirectory();
    final safeName = shopName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final file = File(
      p.join(dir.path, 'credit_passport_$safeName.png'),
    );
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Credit Passport — $shopName',
      text: 'Credit Passport for $shopName, generated on-device by KhataSetu.',
    );
  }
}
