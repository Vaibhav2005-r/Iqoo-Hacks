# Credit Passport Reader (lender side)

A single static page. A lender scans the QR on a shopkeeper's Credit Passport
and sees their ledger position and how the trust score was built.

## Why there is no backend

The QR carries the figures itself. That was a deliberate choice in the app:

> The QR carries the data itself rather than a URL, because there is no server
> and the whole claim of this product is that it works offline.
> — `lib/services/passport_service.dart`

So this page looks nothing up, stores nothing, and sends nothing anywhere. It
decodes the code in the browser and renders it.

## Running it

```bash
python3 -m http.server 8765 --directory lender
```

Then open http://127.0.0.1:8765. The camera needs HTTPS or localhost — a
`file://` open will fall back to the paste box.

For testing without a phone, deep-link a payload:
`index.html?p=<url-encoded JSON>`

## Deploying

`render.yaml` at the repo root defines it as a Render static site
(publish path `./lender`, no build command). Connect the repo as a Blueprint,
or create a Static Site pointing at that directory. Every push redeploys.

## The payload contract

Read by this page and produced by `PassportService.buildQrPayload`:

| key | meaning |
|---|---|
| `v` | payload version; this reader accepts `1` only |
| `shop` `owner` `loc` | shop identity |
| `score` `display` | 0–100 score, and the 300–850 rescaling |
| `tx` `cust` `days` | entries, active customers, days of history |
| `credit` `repaid` `out` | rupees extended, repaid, outstanding |
| `gen` | date computed, `yyyy-MM-dd` |
| `parts` | `repayment` `tenure` `customers` `velocity`, points earned |

`test/passport_qr_contract_test.dart` fails if the app changes any of these,
because nothing else would catch it — the app would keep emitting a valid QR
and this page would quietly render blanks.

## What it deliberately does not do

No lending recommendation, no loan sizing, no risk grade. It presents the
shopkeeper's own figures and says plainly that they are self-attested rather
than bank-verified. Underwriting is out of scope.
