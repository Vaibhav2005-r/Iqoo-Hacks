# Demo runbook

Target: 3–5 minutes. The loop below beats a longer feature list that only half
works — a jury watching one real, live cycle is the whole goal.

## Before you go on stage

- [ ] Models pushed and verified (`docs/MODELS.md`), if native AI is enabled
- [ ] App launched once already, so the DB and model dir exist
- [ ] **Ledger pre-seeded with ~3 weeks of history.** The trust score needs
      real history to be interesting; a score built live from three entries
      shows as provisional, correctly. Seed it the day before by using the app.
- [ ] A printed/handwritten khata page ready to photograph
- [ ] Airplane mode ON — and say so out loud
- [ ] Screen mirroring to the laptop working (Office Kit)
- [ ] Phone brightness up, notifications silenced

## The loop

**1. Frame it (30s).** "This is a kirana shopkeeper's khata. Years of credit
history, on paper, invisible to every lender in the country."

**2. Speak an entry (45s).** Airplane mode visible. Speak a real Hindi
sentence. Show the transcript appear as "what I heard", the fields fill in, and
save.

**3. Break it on purpose (30s).** This is the most valuable 30 seconds of the
demo. Speak an entry you *know* transcribes imperfectly — a noisy phrase, an
unusual name. When the wrong value appears, correct it in one tap.

> "It mishears sometimes. So we never let it write to the ledger unreviewed —
> every field is editable, and correcting it takes one tap. That's not a
> workaround, that's the design."

Judges have seen a hundred demos that hide their failure modes. Showing yours,
and having an answer, reads as engineering maturity.

**4. Scan a page (45s).** Photograph the paper khata. Show the batch of
candidate rows, some pre-checked and some not. Open "what the phone read" to
show the raw OCR. Confirm and save.

**5. Credit Passport (60s).** Open it. Big number, then immediately scroll to
the breakdown.

> "This isn't a black box. Repayment consistency: 34 out of 40, because 85% of
> the udhar he gives comes back. Every point traces to his own ledger."

Show the QR. "A lender scans this and gets the figures directly — there's no
server behind it, which is why it works in a village with no signal."

**6. Close (30s).** "Everything you just watched ran on this phone, in airplane
mode. The release build doesn't even declare the internet permission."

## The proof point worth keeping in your pocket

If a judge asks whether it really runs on-device:

```bash
$ANDROID_HOME/build-tools/36.0.0/aapt2 dump permissions \
  build/app/outputs/flutter-apk/app-release.apk
```

No `android.permission.INTERNET`. The app *cannot* make a network call.

The story behind it is worth telling if a judge is technical: ML Kit pulls in
Google's telemetry uploader transitively, which adds `INTERNET` to the merged
manifest. We strip it in the release manifest. Finding that took actually
building the APK and reading the merger report — it is not visible in source.

## Things to say accurately

- "On-device inference" — **not** "NPU accelerated". It is CPU/GPU via
  llama.cpp. See `docs/NATIVE_AI.md`.
- If running rules-only, say so: "the extraction is a deterministic parser we
  wrote for Hindi khata phrasing; the LLM path is the same interface." Do not
  claim an LLM is running if it is not — the fallback is a legitimate
  engineering decision and describes well.

## If something breaks live

- **Voice fails** → the same screen has a text field. Type the sentence; the
  extraction and the rest of the demo are unaffected.
- **Camera/OCR fails** → skip to the passport. Steps 2 and 5 carry the story.
- **App crashes** → relaunch; the ledger is in SQLite and nothing is lost. Say
  "the ledger is on the phone, so nothing's gone" and continue.
