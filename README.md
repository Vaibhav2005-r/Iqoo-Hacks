# KhataSetu

**Your khata, your credit history.**

A kirana shopkeeper's paper credit ledger, turned into a digital ledger, a
transparent trust score, and a shareable Credit Passport — using voice, camera,
and on-device AI. No account, no server, no network.

Built for the iQOO Hackathon 2026 (Hyderabad), FinTech & Commerce track, by
**Caffeinated Compilers**.

---

## The problem

India's kirana shopkeepers extend informal credit (*udhar*) to regular
customers and track it by hand in a notebook. They have years of consistent,
trackable credit behaviour — and no formal credit history, because it lives on
paper instead of in a database. So they can't get a working-capital loan.

KhataSetu is the bridge (*setu*) between the two.

---

## What it does

1. **Speak an entry.** *"Sharma ji ko paanch sau ka udhar diya"* → transcribed
   and structured on the phone → an editable confirmation card → saved.
2. **Scan a khata page.** Photograph a paper ledger page → on-device OCR →
   structured into a checkable batch of candidate entries.
3. **See a trust score.** Rule-based, computed from the shopkeeper's own
   ledger, with every point explained in plain language.
4. **Share a Credit Passport.** A card with the score, its breakdown, summary
   stats, and a QR a lender can scan — the QR carries the data itself, so it
   works with no server behind it.

---

## Running it

```bash
git clone https://github.com/Vaibhav2005-r/Iqoo-Hacks.git
cd Iqoo-Hacks
flutter pub get
flutter run
```

`android/` is committed and is the exact project verified to build — including
R8 keep rules and the release manifest overlay, both of which took an actual
APK build to discover. See [docs/ANDROID.md](docs/ANDROID.md).

```bash
flutter test                 # 61 tests: amount parsing, extraction, scoring, UI
flutter build apk --release  # ~84 MB, or --split-per-abi for arm64 only
./scripts/setup.sh           # only if android/ is missing or broken
```

### Verified against

Flutter 3.47.2 · Dart 3.13.2 · Android SDK 36.0.0 · Gradle 9.3.1 · JDK 25.

- `flutter analyze` — no issues
- `flutter test` — 71 passing
- `flutter build apk --release` — builds, no `INTERNET` permission
- Run on an Android 16 emulator (Pixel 7, arm64): onboarding, voice-path
  extraction, ledger, balances, trust score, Credit Passport with QR, and
  camera OCR all exercised end to end

Not yet verified: **a physical phone**, and the voice path with a real whisper
model (the typed input path shares everything downstream of the transcript).

---

## Architecture

```
lib/
  models/       Shop, Customer, LedgerTransaction, TrustScoreSnapshot
  db/           sqflite schema + LedgerRepository (all reads and writes)
  state/        LedgerController (ChangeNotifier, single source of truth)
  services/
    ai_runtime.dart          picks engines, merges and repairs their output
    native_ai_bindings.dart  the one file that swaps rules <-> native models
    extraction/              TransactionDraft, Hindi/English AmountParser
    llm/                     extractor interface + RuleBasedExtractor
    asr/                     ASR interface + microphone capture
    ocr_service.dart         ML Kit text recognition
    scoring_service.dart     the trust score
    passport_service.dart    QR payload + share
  screens/      onboarding, home, voice entry, camera scan, customer, passport
  widgets/      AppCard, DraftEditor, EmptyState, OnDeviceBadge
native_ai/      opt-in llama.cpp + whisper.cpp implementations (see below)
```

### Why the AI layer is built the way it is

`fllama` and the whisper.cpp Flutter bindings are community-maintained packages
whose native NDK/ABI build is the most likely thing in this stack to break —
and a broken native build breaks compilation of the *entire app*. Discovering
that the night before a demo would be fatal.

So the native implementations live in `native_ai/`, outside `lib/`, and are
copied in by a script. The app always compiles and always runs end-to-end:

| | Extraction | Speech |
|---|---|---|
| **Default** | `RuleBasedExtractor` — deterministic, on-device, zero deps | falls back to typed input |
| **Native enabled** | Gemma-2B GGUF via llama.cpp | whisper-tiny via whisper.cpp |

`AiRuntime` chooses at startup and degrades at request time: if the LLM returns
malformed JSON, times out, or drops a field, the deterministic result fills the
gap. A model failure costs extraction quality, never the entry.

The rule-based extractor is not a stub. It handles Devanagari and romanised
Hindi plus English, colloquial number forms (`dhai sau` = 250, `saade teen sau`
= 350), Indian digit grouping, direction detection with correct precedence
(`paise wapas diye` is a payment, not credit), and name resolution against the
existing customer roster. It is what keeps the demo alive on stage.

To turn the real models on:

```bash
./scripts/enable_native_ai.sh   # and ./scripts/disable_native_ai.sh to revert
```

See [docs/NATIVE_AI.md](docs/NATIVE_AI.md) and [docs/MODELS.md](docs/MODELS.md).

---

## The trust score

Rule-based and fully transparent, out of 100:

| Component | Max | Basis |
|---|---|---|
| Repayment consistency | 40 | rupees repaid ÷ rupees extended, averaged per customer |
| Ledger history | 20 | days from first to latest entry (180 = full marks) |
| Active customers | 20 | distinct customers with entries (15 = full marks) |
| Recent activity | 20 | entries in the last 30 days (40 = full marks) |

Deliberately not ML. Someone being shown a number that gates their loan should
be able to be told exactly why it is what it is, and what raises it. Every
component carries its own plain-language explanation, and the passport renders
those verbatim.

**One deviation from the original spec, on purpose:** repayment is weighted by
*money*, not by transaction count. Counts are trivially misleading — one ₹5,000
udhar settled by one ₹10 payment would score a perfect 1.0. Rupees repaid
against rupees extended is what a lender actually cares about.

Below 5 entries the score is labelled provisional, in the UI and on the
passport. A confident-looking number built on four entries would be the same
dishonesty this product exists to fix.

---

## Privacy

- No ledger data, audio, or image leaves the device. Ever.
- Audio clips are deleted immediately after transcription.
- **The release build declares no `INTERNET` permission**, so the app
  physically cannot make a network call.

That last point took work, and the reason is worth knowing. ML Kit pulls in
`com.google.android.datatransport:transport-backend-cct` transitively — a
Google *telemetry uploader* — and that library's manifest contributes
`INTERNET` and `ACCESS_NETWORK_STATE` to the merged manifest. Left alone, a
release APK ships with network access and a component that wants to phone home.

`android/app/src/release/AndroidManifest.xml` strips both with
`tools:node="remove"`. Release only — Flutter injects `INTERNET` into the debug
manifest for hot reload, and removing it there would break `flutter run`.

Verify it yourself on a release build:

```bash
$ANDROID_HOME/build-tools/36.0.0/aapt2 dump permissions \
  build/app/outputs/flutter-apk/app-release.apk
```

Confirmed output — RECORD_AUDIO, CAMERA, READ_MEDIA_IMAGES,
READ_EXTERNAL_STORAGE, and nothing else.

OCR still works because the Devanagari recogniser is the *bundled* ML Kit
artefact: the model ships inside the APK and is never downloaded. **Smoke-test
a scan on the device after any dependency change** — this is the one behaviour
that a permission strip could plausibly break, and no static check will catch
it.

---

## Honest limitations

- **This is on-device inference, not NPU acceleration.** llama.cpp on Android
  runs on CPU (and GPU via Vulkan where available), not the Hexagon NPU. Real
  NPU delegation would mean Qualcomm's QNN SDK — a much larger integration than
  a 30-hour build allows. The UI and this README say "on-device" and mean it.
- **whisper-tiny multilingual is mediocre on Hindi.** Community reports are
  consistent on this and we are not going to pretend otherwise. The product
  answer is the confirmation card: every transcription is shown verbatim as
  "what I heard" and every field is editable, so a mishearing is a one-tap fix
  rather than a wrong ledger entry.
- **Handwriting OCR makes mistakes**, and in more interesting ways than
  expected. On a real scan, ML Kit's Indic recogniser returned **Bengali digit
  zeros** (U+09E6) for zeros written on a Hindi page — so "500" arrived as
  `5\u09E6\u09E6`, and the tokeniser stripped the unfamiliar characters and
  read it as 5. `AmountParser` now normalises every Indic and Arabic-Indic
  digit block, not just Devanagari. It also read an `8` as Bengali `৪`, which
  no amount of parsing can fix — that one is what the correction UI is for.
  Scanned rows arrive unchecked when the pipeline is unsure, the raw OCR text
  stays one tap away, and nothing is saved without review.
- **No encryption at rest.** SQLite, unencrypted. A real deployment needs
  SQLCipher; that is a roadmap item, not something to rush under time pressure.

## Not built (deliberately out of scope)

Real bank/NBFC integration · payments · KYC · auth beyond one local shop
profile · cloud sync · multi-device · fraud detection · underwriting logic
beyond the transparent scorer.

---

## Team

Caffeinated Compilers — Vaibhav Rajendra Dohare, Devaansh Sharma, Nitin Singh.
