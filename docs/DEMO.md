# Demo runbook

Target: 3–5 minutes. One real, live cycle beats a longer feature list that
only half works.

Everything below is written around what was actually measured, not what we
hoped for. Read [docs/BENCHMARKS.md](BENCHMARKS.md) once before the day so the
numbers are in your head when a judge asks.

---

## Before you go on stage

**On the phone**

- [ ] Install a **bundled-model** build — `./scripts/bundle_model.sh` then
      `flutter build apk --release --split-per-abi`. Voice then works the
      moment it installs; no adb push, nothing to forget.
- [ ] Launch it once and confirm the mic badge reads **"Speech recognised on
      your phone"**. If it says the model is missing, *tap the badge* — it
      shows the exact path it looked in.
- [ ] **Pre-seed ~3 weeks of ledger history, the day before.** The trust score
      is the emotional payoff and it needs real history. Built live from four
      entries it correctly labels itself *provisional*, which is honest but
      not the story you want.
- [ ] Airplane mode ON.
- [ ] Brightness up, notifications silenced, auto-rotate off.

**On the laptop**

- [ ] [khatasetu-lender.onrender.com](https://khatasetu-lender.onrender.com)
      open in a tab, camera permission already granted.
- [ ] Screen mirroring from the phone working (Office Kit).
- [ ] A handwritten khata page ready to photograph.

**Rehearse the actual sentences.** Whisper gets roughly half of spoken amounts
wrong (4/9 measured). Find two or three phrasings that transcribe well *in
your own voice* and use those — then break it on purpose once, deliberately.

---

## The loop

The eight beats below run **4:50**, which is tight against a 5-minute cap. If
you need to cut, drop step 5 (the scan) — steps 3 and 7 carry more weight, and
the scan is the slowest thing on stage. Do not cut step 4; the correction beat
is what makes the rest credible.

### 1. Frame it — 30s

> "This is a kirana shopkeeper's khata. Years of credit history, on paper,
> invisible to every lender in the country."

### 2. Speak an entry — 45s

Airplane mode visible. Speak a rehearsed Hindi sentence. Show the transcript
appear as **"what I heard"**, the fields fill in, save.

### 3. The grammar beat — 30s

This one is worth rehearsing, because it looks like magic and is actually
linguistics. Say these two back to back:

| Say | Lands on |
|---|---|
| `Sharma ko paanch sau diya` | **Udhar given** |
| `Ramesh ne paanch sau diye` | **Payment received** |

> "Same verb — *diya*. Opposite meaning. Hindi marks who did what on the
> postposition, not the verb: *ko* means the shopkeeper gave, *ne* means the
> customer did. Read the verb alone and you record a repayment as fresh
> credit — you double the debt instead of clearing it."

### 4. Break it on purpose — 30s

The most valuable 30 seconds in the demo. Speak something you know it will
mangle — a number, an unusual name. When the wrong value appears, fix it in
one tap.

> "It mishears about half the amounts. So it never writes to the ledger
> unreviewed — every field is editable, and when it can't read a number it
> leaves the field *empty* rather than guessing. That's not a workaround,
> that's the design."

Judges have seen a hundred demos that hide their failure modes. Showing yours,
with an answer ready, reads as engineering maturity.

### 5. Scan a page — 45s

Photograph the paper khata. Show the batch of candidate rows — some
pre-checked, some not. Open **"what the phone read"** (☰, top right) to show
the raw OCR. Confirm and save.

If a row is wrong, that is the point again: the shopkeeper sees exactly what
the phone read and fixes it.

### 6. The passport — 45s

Open it. Big number, then **immediately scroll to the breakdown**.

> "This isn't a black box. Repayment consistency: 34 of 40, because 85% of the
> udhar he gives comes back. Every point traces to his own ledger."

### 7. The lender side — 45s

**This is the Office Kit moment.** Phone mirrored showing the passport;
laptop showing the lender page. Scan the QR with the laptop webcam.

> "No server. The QR carries the figures themselves, which is why this works
> in a village with no signal. And the lender sees the same breakdown he
> does — plus a line saying this is self-attested, not bank-verified, because
> a lender needs telling."

### 8. Close — 20s

> "Everything you just watched ran on the phone, in airplane mode. The release
> build doesn't even declare the internet permission."

---

## Proof points to keep in your pocket

**"Is it really on-device?"**

```bash
$ANDROID_HOME/build-tools/36.0.0/aapt2 dump permissions \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

RECORD_AUDIO, CAMERA, READ_MEDIA_IMAGES, READ_EXTERNAL_STORAGE. **No
INTERNET.** The app cannot make a network call.

Worth adding: ML Kit pulls in Google's telemetry uploader transitively, which
put `INTERNET` back into the merged manifest. We strip it in the release
manifest. Finding that took building the APK and reading the merger report.

**"Why no LLM? Everyone's using one."**

We benchmarked three on the same 13 real cases. All lost to the rules:

| Engine | Storage | Name | Amount | Direction |
|---|---|---|---|---|
| **Rules** | **0 MB** | **11/13** | **8/13** | **12/13** |
| Llama-3.2-1B | 770 MB | 3/13 | 2/13 | 9/13 |
| Gemma-2-2b | 1.6 GB | 7/13 | 4/13 | 11/13 |

> "A general 2-billion-parameter model doesn't know that *dhai sau* is 250, or
> that *ne* plus a giving verb is a repayment. We measured instead of
> assuming, and shipped the thing that won."

**"How accurate is the speech?"** Don't oversell it. Names 7/9, direction 8/9,
amounts 4/9 — and say the correction UI is why that is survivable.

---

## Say these accurately

- **"On-device inference"**, never "NPU accelerated". It is CPU/GPU via
  llama.cpp and whisper.cpp. The claim is checkable.
- The extraction is **a deterministic parser we wrote for Hindi khata
  phrasing**, not an LLM. Say so — it is a stronger story than pretending,
  and the benchmark backs it.
- The ledger is **not encrypted at rest**. If asked: SQLCipher was implemented
  and reverted because a failed keystore read would have destroyed the ledger.
  Documented in [BENCHMARKS.md](BENCHMARKS.md).

---

## If something breaks live

| Breaks | Do this |
|---|---|
| Voice | The same screen has a text field. Type the sentence; everything downstream is identical. |
| Camera / OCR | Skip to the passport. Steps 3 and 6 carry the story. |
| Lender webcam | The page has a paste box — paste the payload and carry on. |
| App crashes | Relaunch. The ledger is in SQLite; nothing is lost. Say so and continue. |

The first scan after a fresh install may take a moment while ML Kit loads its
model. Opening the scan screen starts that warm-up in the background, so it is
usually hidden behind you choosing a photo — but do not make the very first
scan of the day the one on stage.
