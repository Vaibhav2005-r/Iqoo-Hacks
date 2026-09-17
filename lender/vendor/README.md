# Vendored dependencies

**jsQR 1.4.0** — Apache-2.0 — https://github.com/cozmo/jsQR

Copied here deliberately rather than loaded from a CDN. The page originally
pointed at cdnjs, which does not host jsQR at all; the 404 was invisible
because the page still rendered and only the camera path was dead. Vendoring
makes the lender view self-contained, which also matches the rest of the
product: nothing it needs comes from somewhere else at runtime.

To update: `curl -L -o jsQR.js https://unpkg.com/jsqr@<version>/dist/jsQR.js`
