# Blueprint extraction

The requirements blueprint defines `pdftextsearch` as a private, local-first Julia CLI whose primary goal is a trustworthy answer to "where does this phrase occur?" with enough evidence to verify it.

## User-facing scope

- `inspect`: metadata, PDF health, page count, text/image presence, and optional page/object detail.
- `extract`: immutable-source, deterministic page records, normalized text, spans, offsets, optional geometry, and a versioned manifest.
- `index`: a reopenable local SQLite/FTS5 index with atomic publication and freshness checks.
- `search`: words, phrases, AND terms, snippets, page filters, stable ordering, JSON, offsets, and optional boxes.
- `status`, `unpack`, and `doctor`: freshness explanation, safe asset export, and environment diagnostics.

## Product constraints carried into the implementation

- Preserve source path, source SHA-256, page identity, character offsets, and coordinates when available.
- Normalize with NFKC, casefold, whitespace collapse, and hyphenated-line-break joining.
- Never mutate the source PDF or silently overwrite derived output.
- Keep machine output on stdout and diagnostics on stderr; no-result search is successful.
- Treat PDFs as untrusted input and keep OCR, deep object inspection, custom indexes, and ranking extensible rather than mandatory for the first slice.

## Release gates from the blueprint

The MVP must install with a useful help screen, inspect the fixture matrix, emit deterministic artifacts, reopen its index, return page-bounded evidence, refuse stale indexes, preserve safe failure state, and document limitations. The repository includes unit and vertical-slice tests for the implemented core; the remaining hardening work is tracked by the explicit extension points in `docs/architecture.md` and the README.
