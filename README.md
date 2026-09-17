# KhataSetu

**Your khata, your credit history.**

A kirana shopkeeper's paper credit ledger, turned into a digital ledger, a
transparent trust score, and a shareable Credit Passport — using voice, camera,
and on-device AI. The app has no account, no server and no network permission.
A separate static page lets a lender read a passport; it has no backend either,
because the QR carries its own data.

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
5. **Lender reads it.** A separate static page scans that QR and shows the
   ledger position and how the score was built — live at
   [khatasetu-lender.onrender.com](https://khatasetu-lender.onrender.com).

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
flutter test                 # 129 tests: parsing, extraction, scoring, QR contract, UI
flutter build apk --release --split-per-abi   # arm64 is the one you want
./scripts/setup.sh           # only if android/ is missing or broken
```

Two APK sizes, and the difference is the speech model:

| Build | Size | Voice |
|---|---|---|
| `assets/models/` empty | **33 MB** | needs `ggml-tiny.bin` pushed with adb |
| after `./scripts/bundle_model.sh` | **103 MB** | works the moment it is installed |

The model is gitignored, so a fresh clone builds the small one. Bundling is
worth it for a build you hand to someone to test — see
[docs/MODELS.md](docs/MODELS.md).

### Verified against

Flutter 3.47.2 · Dart 3.13.2 · Android SDK 36.0.0 · Gradle 9.3.1 · JDK 25.

- `flutter analyze` — no issues
- `flutter test` — **129 passing**
- `flutter build apk --release` — builds, no `INTERNET` permission
- Run on an Android 16 emulator (Pixel 7, arm64): onboarding, voice-path
  extraction, ledger, balances, trust score, Credit Passport with QR, and
  camera OCR all exercised end to end
- Lender page verified on the live Render deployment: a real passport QR
  decoded (268 bytes, exact) and rendered

whisper.cpp runs on-device — `libwhisper.so` is in the APK and the model
unpacks itself from `assets/` on first launch, so a clean install needs no adb.

**Still not verified: a physical phone.** Specifically, whisper transcribing a
real human voice (no emulator gives a usable microphone) and OCR on genuine
handwriting rather than a rendered font. Both are the first things to try on
the demo device.

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
    model_manager.dart       finds and VALIDATES model files on the device
  screens/      onboarding, home, voice entry, camera scan, customer, passport
  widgets/      AppCard, DraftEditor, EmptyState, OnDeviceBadge,
                ModelStatusSheet (tap the mic badge to see what is missing)
native_ai/      opt-in llama.cpp + whisper.cpp implementations (see below)
lender/         the lender-side passport reader (static, no build step)
design/         app_icon.html — source for the launcher icon and splash
assets/models/  gitignored; bundle_model.sh drops whisper here
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
| **Enabled** | `RuleBasedExtractor` — deterministic, on-device, zero storage | **whisper-tiny via whisper.cpp** |
| **Not shipped** | any LLM — measured worse than the rules | — |

Speech is **on**. The LLM is not, and that is now a measured decision rather
than a precaution: Gemma-2-2b, Llama-3.2-1B and Qwen2.5-0.5B were each scored
against the rule extractor on the same 13 cases, and **all three lost on every
axis** while costing 469 MB to 1.6 GB. Full table in
[docs/BENCHMARKS.md](docs/BENCHMARKS.md).

The original reason still stands too: `fllama` uses Dart native-assets hooks
that run for every build target, so enabling it breaks `flutter test` on a host
without a CMake 3.x toolchain. `./scripts/enable_native_ai.sh --asr-only` turns
on only the half that works.

`AiRuntime` chooses at startup and degrades at request time: if the LLM returns
malformed JSON, times out, or drops a field, the deterministic result fills the
gap. A model failure costs extraction quality, never the entry.

The rule-based extractor is not a stub — it is the best-scoring engine tested.
It handles:

- **Devanagari, romanised Hindi and English**, plus every Indic and
  Arabic-Indic digit block (ML Kit returns *Bengali* zeros for a Hindi page).
- **Colloquial numbers**: `dhai sau` = 250, `saade teen sau` = 350, Indian
  digit grouping.
- **Hindi grammar for direction.** The postposition decides, not the verb:
  `Sharma **ko** 500 diya` is credit, `Ramesh **ne** 500 diye` is a payment.
  Same verb, opposite meaning — reading the verb alone recorded repayments as
  fresh credit and doubled the debt.
- **Names by elimination.** Capitalisation cannot be relied on (Devanagari has
  none, and transcripts are often lower case), so a stopword list rules out
  what *cannot* be a name and what survives is scored by position.
- **Whisper's own failure modes**: it glues short words together, so `chaar
  sau` arrives as `Charso`. Glued number tokens are segmented back apart.

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

## The lender side

[khatasetu-lender.onrender.com](https://khatasetu-lender.onrender.com) —
source in [`lender/`](lender/), deployed from `render.yaml`.

A single static page. A lender scans the passport QR and sees the ledger
position and how each of the four score components was earned. It has **no
backend**, because the QR carries the figures rather than a URL — so the page
looks nothing up, stores nothing, and sends nothing anywhere.

It deliberately offers **no lending recommendation** — no loan sizing, no risk
grade. Underwriting is out of scope, and a page that invented a number would
be worse than one that does not. It states plainly that the data is
self-attested rather than bank-verified, and flags a file under five entries
as too thin to read.

The payload is a contract between two codebases that cannot import each other,
so `test/passport_qr_contract_test.dart` pins the exact keys, types, date
format and a size ceiling. Rename a field in Dart and the app would keep
emitting a valid QR while the page silently rendered blanks; that test fails
instead.

Two things found by deploying it rather than by reading it: the QR library was
being loaded from a CDN that **does not host it** (404 in production, invisible
because only the camera path was dead), and it is now vendored locally. And the
scanner was verified against a real passport QR on the live site — 268 bytes
decoded exactly.

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
- **whisper-tiny on Hindi is weak, and now measured rather than assumed.**
  Nine Hindi sentences were spoken, transcribed, and the raw output run through
  the extractor. Names survived well; amounts did not:

  | | score |
  |---|---|
  | Customer name | 7/9 |
  | Direction (credit vs payment) | 8/9 |
  | **Amount** | **4/9** |

  Whisper also returns **romanised Latin, not Devanagari**, even told the
  language is Hindi. Roughly half of spoken amounts will need a correction —
  it heard `paanch sau` as "5-10" and `do sau pachas` as "25th", neither
  recoverable. That is what the confirmation card is for: every transcript is
  shown verbatim as "what I heard", every field is editable, and a draft with
  an unreadable amount arrives **empty rather than wrong**.
- **Handwriting OCR makes mistakes**, and in more interesting ways than
  expected. On a real scan, ML Kit's Indic recogniser returned **Bengali digit
  zeros** (U+09E6) for zeros written on a Hindi page — so "500" arrived as
  `5\u09E6\u09E6`, and the tokeniser stripped the unfamiliar characters and
  read it as 5. `AmountParser` now normalises every Indic and Arabic-Indic
  digit block, not just Devanagari. It also read an `8` as Bengali `৪`, which
  no amount of parsing can fix — that one is what the correction UI is for.
  Scanned rows arrive unchecked when the pipeline is unsure, the raw OCR text
  stays one tap away, and nothing is saved without review.
- **No encryption at rest.** SQLite, unencrypted. SQLCipher was implemented
  and then reverted: the keystore reads it depends on took 4.6 s when they
  worked and timed out when they did not, and a failed key read leaves only
  two options — regenerate the key and destroy the ledger, or refuse to open
  it. See [docs/BENCHMARKS.md](docs/BENCHMARKS.md) for what it would take to
  land safely. Still the right thing to do; not something to rush.
- **No LLM.** Gemma, Llama-3.2-1B and Qwen2.5-0.5B were all benchmarked
  against the rule-based extractor on the same 13 real cases. All three
  scored worse, at 469 MB to 1.6 GB of storage — see
  [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Not built (deliberately out of scope)

Real bank/NBFC integration · payments · KYC · auth beyond one local shop
profile · cloud sync · multi-device · fraud detection · underwriting logic
beyond the transparent scorer.

---

## Team

Caffeinated Compilers — Vaibhav Rajendra Dohare, Devaansh Sharma, Nitin Singh.
