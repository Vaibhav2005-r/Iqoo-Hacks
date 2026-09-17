# Measured, not assumed

Two decisions on this project were made by measurement rather than intuition,
and both came out against the obvious choice. Recorded here because the
results are the argument.

## 1. No LLM beats the rule-based extractor

The brief planned Gemma-2B for entity extraction. Before shipping a 1.6 GB
model, three candidates were benchmarked against the **same 13 cases** — nine
of them verbatim whisper-tiny output from real Hindi audio, four typed.

| Engine | Storage | Valid JSON | Name | Amount | Direction | Per case |
|---|---|---|---|---|---|---|
| **RuleBasedExtractor** | **0 MB** | n/a | **11/13** | **8/13** | **12/13** | **0.73 ms** |
| Qwen2.5-0.5B-Instruct Q4_K_M | 469 MB | 0/13 | 0/13 | 0/13 | 0/13 | 0.2 s |
| Llama-3.2-1B-Instruct Q4_K_M | 770 MB | 13/13 | 3/13 | 2/13 | 9/13 | 0.7 s |
| Gemma-2-2b-it Q4_K_M | 1.6 GB | 13/13 | 7/13 | 4/13 | 11/13 | 1.8 s |

LLM timings are on an Apple Silicon GPU; on a phone's CPU they are several
times slower. The rule timing is on the Dart VM.

Qwen at 0.5B could not produce parseable JSON at all — output like
`{ and }` and `{5, 10}`. Llama-3.2-1B produced valid JSON but read
`"amount": "hasa"` and called the customer "Sharma **ji**". Even Gemma, the
originally planned model, scored below rules that cost nothing.

That is not surprising in hindsight. The task is narrow, and the rules encode
things no general small model knows: that `dhai sau` is 250, that `ne` plus a
giving verb is a repayment while `ko` plus the same verb is credit, that
whisper glues `chaar sau` into `Charso`.

**The honest caveat:** those rules were tuned against this corpus, so they are
fitted to it. An LLM's real advantage would be generalising to phrasings not
in the sample, which cannot be measured without more real speech. On
everything observed so far, rules win decisively — at zero storage, ~1000x
faster, and with no airplane-mode compromise.

**Decision: ship no LLM.**

## 2. Encryption at rest was attempted and reverted

SQLCipher plus `flutter_secure_storage` was implemented and did work at the
file level — verified on device, the database header was random bytes rather
than `SQLite format 3`, and the shop name appeared zero times in the file.

It was reverted, for a reason worth recording.

On the test device, `flutter_secure_storage` reads took **4.6 seconds** when
they succeeded and **timed out** when they did not. The key is the only thing
that can decrypt the ledger, so a read failure has exactly two possible
handlings:

- generate a new key — which makes the existing ledger **permanently
  unreadable**, destroying every entry the shopkeeper recorded; or
- refuse to open — which means the app shows an error instead of the khata.

The first was implemented as a fallback and is a data-loss bug: a transient
storage delay silently wipes the ledger. The second is survivable but could
not be validated on real hardware in the time available.

Encryption at rest is still the right thing for this app — the realistic
threat to an offline ledger is a lost or stolen phone. It needs to come back
with:

- no key regeneration, ever, when a read *fails* as opposed to returning
  empty — those two cases must be distinguished;
- the key read done once at startup, off the critical path, not twice;
- validation on a physical device, where keystore access should be far faster
  than an emulator's.

**Decision: not shipped. Ledger remains unencrypted at rest, as the README
states.**
