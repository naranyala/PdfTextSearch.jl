# PdfTextSearch.jl TODOs

This backlog is derived from the attached `pdftextsearch_software_requirements_blueprint.pdf` and audited against the current repository. The user request is to make the codebase progress toward that blueprint; statements below are implementation work items, not instructions embedded in the PDF for the user to follow.

## Separation from `webview-app-with-julia`

`PdfTextSearch.jl` is the reusable PDF processing and evidence engine. It owns:

- PDF validation, metadata inspection, text/geometry extraction, normalization, and evidence offsets;
- artifact and index schemas, freshness, rebuild, crash-recovery, and parser safety;
- query parsing, deterministic search, snippets, page filters, boxes, and machine-readable results;
- backend-neutral Julia APIs, CLI behavior, fixtures, benchmarks, and compatibility guarantees.

`PdfTextSearch.jl` does not own the desktop window, WebView/Preact UI, file chooser,
application notes or quiz data, user-facing job state, app settings, or persistence
outside its extraction/index artifacts. Those responsibilities belong to the
integrating application, especially `../webview-app-with-julia`.

### Integration contract

The WebView application should consume only the exported API from
`src/PdfTextSearch.jl` (`inspect_pdf`, `extract_pdf`, `index_directory`,
`open_index`, `search`, `status`, and related public models). It should add this
repository as a Julia path dependency, keep application cache paths outside the
library checkout, run long operations through its own job manager, and translate
library errors into its stable frontend error envelope. The library must remain
usable without WebView, JSON3, LinuxCompanion, or application state.

Cross-project changes belong in both TODO files only when they cross this
boundary: the library defines the processing contract; the WebView application
defines the adapter, lifecycle, and presentation contract.

## High-leverage next steps

These are the smallest slices that unlock the largest amount of downstream
work. Complete them in order before expanding into broad enrichment features.

### HL-1 Freeze the embeddable API

- [x] Add `examples/embed.jl` showing inspect → extract → index → status → search without the CLI.
- [x] Publish a small API contract covering exported names, constructor arguments, result fields, schema versions, and error codes.
- [x] Replace duplicated version literals with package metadata and expose a capability/version report for callers.
- [x] Add a downstream-style test project that loads `PdfTextSearch` as a path dependency and serializes a real result.

Acceptance: a clean external Julia project can add the package, process one fixture, reopen its index, and consume results without importing private helpers or parsing human CLI output.

### HL-2 Build the regression harness before adding features

- [ ] Add a compact generated fixture matrix: Unicode, hyphenation, empty/image-only page, repeated matches, punctuation, geometry, malformed input, and a multi-page document.
- [ ] Store intentional golden outputs for inspect, manifest, page/span records, search results, snippets, boxes, and status transitions.
- [ ] Add subprocess tests for CLI stdout/stderr separation, exit codes, help, paths with spaces, no-result success, and interrupt/failure behavior.
- [ ] Add a single `julia --project=. test/` entry point that runs unit, integration, golden, safety, and benchmark-smoke checks.

Acceptance: any parser, storage, query, or schema change produces a focused diff and cannot silently change evidence semantics.

### HL-3 Isolate tools and enforce bounded execution

- [x] Introduce a narrow `ToolRunner` interface for Poppler and SQLite commands with timeout, cancellation, environment, stdout/stderr, and exit-status capture.
- [x] Introduce an `IndexBackend` interface so the search/query layer does not depend directly on SQL strings or the `sqlite3` executable.
- [ ] Add configurable page, byte, object, asset, and wall-clock budgets with typed limit errors and incomplete-artifact reporting.
- [ ] Add tests for missing tools, non-zero child exit, truncated output, cancellation, and cleanup of child processes/partial files.

Acceptance: an embedding host can impose limits and replace or disable an external backend without changing query or evidence behavior.

### HL-4 Make extraction a durable, reusable cache

- [x] Define a content/configuration cache key using source hash, parser version, normalization version, artifact schema, and extraction options.
- [x] Add cache lookup, lock acquisition, stale detection, no-op reuse, and safe concurrent-build behavior as library APIs.
- [x] Preserve the last known-good artifact/index until replacement validation succeeds; make recovery and cleanup explicit.
- [ ] Add resumable phase metadata and progress counters for inspect, extract, and index.

Acceptance: repeated imports avoid reparsing unchanged PDFs, concurrent callers never publish mixed artifacts, and interrupted work is visibly recoverable.

### HL-5 Preserve evidence through richer extraction

- [x] Define one offset model and add source-to-normalized mappings for Unicode, ligatures, whitespace, and hyphenated line breaks.
- [ ] Add stable page/block/line/span identities and explicit `unknown`/`partial` geometry semantics.
- [ ] Version a result envelope that carries document, page, source text, normalized text, offsets, boxes, warnings, and provenance.
- [ ] Add a citation/evidence export that downstream applications can display or persist without reinterpreting internal artifacts.

Acceptance: every match remains traceable to source-page evidence after normalization and can support a viewer highlight or reproducible citation.

### HL-6 Add enrichment behind optional provider boundaries

- [x] Define extension seams and capability reporting for optional OCR and enrichment providers; keep the deterministic native-text path unchanged.
- [ ] Add concrete provider interfaces and adapters for OCR, language detection, structured blocks, and optional ranking.
- [ ] Add corpus/collection indexing only after the single-document cache and freshness contracts are stable.
- [ ] Add fuzzy, semantic, or relevance search only as opt-in query versions with benchmarked limits and explainable ranking.
- [ ] Add tables, links, annotations, attachments, forms, and bookmarks as bounded evidence-bearing resources rather than unbounded object dumps.

Acceptance: enriched capabilities can be enabled, measured, and version-negotiated independently without destabilizing baseline extraction or search.

## Definition of done for the MVP

The MVP is complete when all P0 and P1 items below are closed and a fresh checkout can:

1. install a working `pdftextsearch` command and show useful command-specific help;
2. inspect text-native, scanned, encrypted, annotated, form, embedded-asset, malformed, and large fixtures;
3. extract deterministic page records, normalized spans, offsets, optional geometry, and a versioned manifest without touching the source PDF;
4. build and reopen a portable SQLite/FTS5 index with atomic publication and trustworthy freshness state;
5. search words, quoted phrases, and AND terms with page-bounded, stable, explainable evidence results;
6. pass the full golden, integration, CLI, safety, and performance suites; and
7. document installation, schemas, limitations, troubleshooting, and published benchmark results.

## Current slice already implemented

- [x] Julia package skeleton and public API in `src/`.
- [x] CLI commands: `inspect`, `extract`, `index`, `search`, `status`, `unpack`, and `doctor`.
- [x] Poppler-backed PDF metadata and text/geometry adapter.
- [x] Source SHA-256, normalized page text, page boundaries, spans, character offsets, original text, and optional bounding boxes.
- [x] Deterministic `manifest.json`, `inspect.json`, `pages.jsonl`, `spans.jsonl`, page text views, `build-report.json`, and `assets/` layout.
- [x] SQLite/FTS5 index schema, source-order search, phrase matching, AND-term candidates, snippets, page filters, JSON output, and `--explain` metadata.
- [x] Freshness checks against source hash and manifest state; stale indexes are rejected.
- [x] No-result searches return exit code 0; stable user-facing exit codes are documented.
- [x] Output overwrite refusal, recoverable forced-extraction backup, and failed-build state reporting.
- [x] Dependency diagnostics and a passing unit/vertical-slice test suite.
- [x] Embedded API contract, runnable example, downstream path-dependency smoke test, capability report, and deterministic result serialization.
- [x] Bounded external-tool runner with timeout/cancellation capture and a replaceable SQLite index-backend seam.
- [x] Content/configuration cache keys, cache inspection, atomic extraction locks, no-op reuse, and source-to-normalized evidence mapping.
- [x] Optional OCR/enrichment provider extension seams with capability negotiation that leaves native-text extraction unchanged.
- [x] Initial requirements extraction, architecture notes, README, and `.gitignore`.

## P0 - release blockers

### P0.1 Make the storage backend portable

- [ ] Replace the `sqlite3` subprocess implementation with a maintained Julia SQLite binding, or formalize a tested backend interface with a portable binding as the default and the CLI adapter as an optional fallback.
- [ ] Validate FTS5 availability at startup with a clear exit-code-5/10 distinction and an actionable doctor message.
- [ ] Add schema migrations, schema compatibility checks, and a migration test from every released schema version.
- [ ] Add prepared statements/batched transactions so user text never becomes ad-hoc SQL and indexing scales without constructing one unbounded script.

Acceptance: `index.sqlite` can be created, reopened, queried, and migrated on Linux, macOS, and Windows without requiring a shell-specific SQLite executable.

### P0.2 Establish a real parser boundary and safety boundary

- [ ] Evaluate maintained Julia PDF reader candidates against the fixture matrix and record the decision in an M0 benchmark/decision note.
- [ ] Keep `src/adapters/PDFReader.jl` as the only parser-specific layer; expose page/object events, metadata, dimensions, rotation, text, and geometry through an adapter interface.
- [ ] Add process-boundary timeouts, cancellation, and bounded output handling for Poppler/native parser calls.
- [ ] Enforce configurable page, object, text-byte, asset-byte/count, decompression, and wall-clock budgets.
- [ ] Make tolerant mode produce an incomplete-but-labeled artifact with counters for skipped objects, truncation, and warnings; strict mode must fail only on configured fatal errors.

Acceptance: adversarial or oversized input cannot cause an unbounded operation, and every limit-triggered result states what was skipped and how to raise the limit intentionally.

### P0.3 Finish the release-quality command contract

- [ ] Add command-specific help and one human/machine example for every command.
- [ ] Make `--config`, `--jobs`, `--quiet`, and `--verbose` functional instead of merely accepted by the parser.
- [ ] Route all progress/diagnostics to stderr, suppress ANSI color whenever stdout is redirected or not a TTY, and keep JSON stdout parseable.
- [ ] Handle SIGINT by closing subprocesses/transactions and publishing `failed` or `stale` state rather than leaving an apparently fresh build.
- [ ] Add `--debug` or a log-file option for technical traces while keeping ordinary user errors concise.
- [ ] Verify paths with spaces, non-ASCII names, symlinks, missing permissions, and output paths that already contain files.

Acceptance: CLI end-to-end tests assert stdout, stderr, exit codes, signals, help, and path behavior for every command.

### P0.4 Make installation reproducible

- [ ] Add a supported install path for Julia users and a packaged/precompiled CLI path appropriate to each supported platform.
- [x] Add a version command sourced from package metadata rather than a duplicated literal.
- [ ] Add CI for supported Julia versions, Poppler availability, SQLite/FTS5, clean installation, tests, and CLI smoke tests.
- [ ] Publish a compatibility matrix for Julia, parser adapter, Poppler, SQLite, and operating systems.

Acceptance: a clean machine following the README can run `pdftextsearch --help`, `doctor`, `inspect`, and the full test suite without repository-specific load-path tricks.

### P0.5 Integration-ready library surface

- [x] Document the supported embedded-library call sequence: inspect, extract, index, status, and search without invoking the CLI.
- [x] Mark the stable exported API and public result fields; keep implementation helpers and SQL details private.
- [x] Define a machine-readable error taxonomy and mapping guidance for callers that expose errors through another protocol.
- [ ] Add cancellation-safe operation boundaries and explicit progress events suitable for an application-owned background job manager.
- [x] Add a compatibility fixture suite that a downstream application can run against a path dependency or released package.
- [x] Document artifact ownership, cache-key strategy, source-path behavior, cleanup, and concurrent-build rules for embedding applications.

Acceptance: an external Julia application can add `PdfTextSearch` as a path or registry dependency, process a PDF without the CLI, serialize the result, recover from failure, and upgrade across a documented compatibility boundary.

## P1 - blueprint requirements still missing or partial

### P1.1 Inspection completeness (FR-003 to FR-010)

- [ ] Report linearization when detectable independently of parser success and preserve an explicit `unknown` value when unavailable.
- [ ] Report effective per-page width, height, and rotation rather than applying the document-level `pdfinfo` page size to every page.
- [ ] Count annotations, forms, and other page-level objects through the parser adapter; distinguish zero from unavailable.
- [ ] Implement bounded `inspect --objects` inventory by object type with suspicious/malformed reference diagnostics.
- [ ] Implement real font, image, attachment, XMP, AcroForm, annotation, JavaScript-action, and named-destination reporting.
- [ ] Detect image-only pages without requiring a full text extraction or silently invoking OCR.
- [ ] Add inspect contract fixtures and golden JSON; bump `schema_version` intentionally when the contract changes.

Acceptance: inspect returns useful partial diagnostics for damaged, encrypted, huge, and image-only PDFs and never dumps unbounded raw objects.

### P1.2 Extraction and evidence mapping (FR-011 to FR-019)

- [x] Preserve source-to-normalized offset mappings rather than relying only on normalized offsets; define whether offsets are Unicode scalar, grapheme, or byte offsets and test Unicode cases.
- [ ] Preserve reliable reading-order metadata, line/block identity, source text, and geometry for every span; explicitly label missing geometry.
- [ ] Verify that ligatures, combining marks, Unicode NFKC, whitespace collapse, and hyphenated line breaks map matches back to sensible source spans.
- [ ] Define selected-page semantics: default output must contain every source page including empty pages; targeted selection must record the selection and source page count without implying omitted pages were absent.
- [ ] Implement object-class and output-field selection to reduce targeted investigations.
- [ ] Support documented text, JSONL, and SQLite-derived export modes without making convenience text files the source of truth.
- [ ] Make failed extraction preserve a recoverable manifest/build report even when failure happens before the temporary directory is created.
- [ ] Add atomic directory publication tests for overwrite refusal, forced replacement, interrupted extraction, and recovery from `.previous-*` backups.

Acceptance: identical source bytes, parser version, and configuration produce byte-stable derived artifacts, and every result can be traced to a page/span with offsets and optional boxes.

### P1.3 Asset unpacking (FR-015)

- [ ] Export embedded images, attachments, fonts, and selected resources, not only Poppler image files.
- [ ] Generate collision-safe names from object identity/type/hash; never use an embedded filename directly as a path component.
- [ ] Record object references, hashes, sizes, MIME/type information, and manifest links for every exported asset.
- [ ] Enforce asset count/size budgets and verify exports stay below the requested destination after path normalization.
- [ ] Add traversal, duplicate-name, malformed-attachment, and large-asset tests.

Acceptance: `unpack` is safe on adversarial embedded names and produces a complete, hash-addressed asset manifest.

### P1.4 Search correctness and query contract (FR-020 to FR-029)

- [ ] Publish a versioned query grammar covering a word, quoted phrase, multiple-term AND semantics, literal mode, case sensitivity, regex, whitespace, punctuation, and invalid syntax.
- [ ] Ensure unquoted multi-term queries have documented AND semantics while quoted phrases require token order and adjacency after normalization.
- [ ] Keep phrases page-bounded and prevent accidental matches assembled across pages, lines, unrelated spans, or token boundaries.
- [ ] Return a single consistent JSON shape across releases; document whether `search --json` emits an array or JSONL and include schema version/query metadata.
- [ ] Return source path, page number, match count, snippet, stable source-order ranking, normalized/source match text, offsets, and optional coordinates consistently.
- [ ] Add page-range, document, file-glob, result-limit, and OCR-confidence filters; reject invalid ranges before querying.
- [ ] Add bounded regex post-filtering with an explicit performance warning; keep fuzzy search opt-in and out of the default grammar.
- [ ] Make `--literal` safe for punctuation such as `C++`, and ensure `--case-sensitive` uses a case-preserving representation for both matching and offsets.
- [ ] Ensure `--boxes` returns only reliable boxes and clearly represents partial geometry for multi-word matches.
- [ ] Make `--explain` report index path, index/schema version, parser version, normalization mode, query interpretation, and every applied filter.
- [ ] Verify first-result latency and warm search latency with a reference corpus; do not reopen or reparse the original PDF on the hot path.

Acceptance: golden searches cover repeated terms, line-break joins, ligatures, Unicode, punctuation, phrases split across pages, page filters, no hits, invalid queries, regex, and deterministic ordering.

### P1.5 Freshness, incremental rebuilds, and crash recovery

- [ ] Hash and compare source bytes, parser version, normalization version/config hash, artifact schema, and index schema on every relevant command.
- [ ] Implement true incremental/no-op indexing for unchanged pages and affected-document rebuilds when source/config changes.
- [ ] Validate page/span/FTS counts and manifest compatibility before marking fresh; never claim freshness after any failed phase.
- [ ] Publish a temporary database atomically, preserve the last known-good index until replacement validates, and recover safely from stale partial files.
- [ ] Store build phase timings/counters in `build_events` and surface them in `status` and benchmark reports.
- [ ] Add corruption detection and a repair/rebuild path for missing or invalid SQLite indexes.

Acceptance: source/config changes are detected without silent mixing, unchanged indexing is within the no-op target, and crashes leave an explicit stale/failed state with the prior good index recoverable.

### P1.6 Data model and API hardening

- [ ] Replace broad `Dict{String,Any}` public results with typed public models plus explicit serialization adapters where practical.
- [ ] Add stable constructors and validation for `Document`, `Page`, `Span`, `Asset`, `Match`, `InspectionReport`, `BuildReport`, and `QuerySpec`.
- [ ] Define null/unknown semantics for dimensions, boxes, annotations, OCR confidence, and parser warnings.
- [ ] Add a public backend-neutral `IndexStore` interface so SQLite/FTS5 can be replaced by a measured custom backend later.
- [ ] Ensure `close(index)` is a real public lifecycle operation if the final backend owns resources.
- [ ] Add API docs and doctests for the public usage shown in the blueprint.

Acceptance: downstream Julia callers can use the API without depending on CLI implementation details or undocumented dictionary keys.

## P1 - quality, safety, and operational coverage

### P1.7 Required fixture matrix

- [ ] Add committed or reproducibly generated small text-native fixture with Unicode, headings, hyphenation, and an empty page.
- [ ] Add multi-column fixture and document the expected reading-order limitation or behavior.
- [ ] Add scanned/image-only fixture and assert OCR is recommended but not invoked.
- [ ] Add encrypted fixture covering tolerant and strict behavior and permission errors.
- [ ] Add forms/annotations fixture and assert inspect counts.
- [ ] Add embedded-assets fixture for image, attachment, font, duplicate, and traversal cases.
- [ ] Add large synthetic text corpus for throughput, memory, no-op freshness, and warm search.
- [ ] Add malformed/adversarial PDFs for invalid references, unusual encodings, deep object graphs, decompression, and parser termination.
- [ ] Store golden inspect JSON, manifest, page JSONL, span JSONL, snippets, boxes, and CLI output with an intentional update workflow.

### P1.8 Test layers and release gates

- [ ] Unit-test normalization, offset mapping, typed models, query parsing, JSON, exit-code mapping, and safe path handling.
- [ ] Add parser-adapter tests for page count, rotation, dimensions, text spans, object inventory, and malformed input.
- [ ] Add integration tests for build/reopen, phrase search, filters, stale detection, schema mismatch, atomic failure, and crash recovery.
- [ ] Add CLI subprocess tests for stdout/stderr separation, JSON validity, paths, exit codes, signals, help, and zero-result success.
- [ ] Add property tests for normalization idempotence and monotonic/valid offset mappings.
- [ ] Add memory, throughput, cold-start, warm-search, first-result, and incremental no-op benchmarks with hardware/Julia/backend/fixture metadata.
- [ ] Add a CI check that prevents a source PDF from being modified by any command.

Acceptance: a passing unit suite is not sufficient; the fixture matrix, golden suite, integration suite, CLI suite, and benchmark report all pass or document deviations.

### P1.9 Threat model and resource controls

- [ ] Test path traversal through embedded names and ensure all unpack paths remain below the requested destination.
- [ ] Test decompression bombs and enforce byte/object/page/time budgets with typed limit errors.
- [ ] Isolate parser crashes/runaway loops where practical and preserve build state when a child process dies.
- [ ] Keep all processing local by default; ensure no network or telemetry path is introduced implicitly.
- [ ] Test stale/mixed indexes, accidental overwrite, symlinked outputs, and partial publication.
- [ ] Add diagnostic counters for skipped objects, truncated streams, warnings, and limit events.

Acceptance: the tool prefers an explicitly incomplete report over an unbounded operation and never mutates or leaks source data implicitly.

## P2 - post-MVP roadmap

### P2.1 Enriched document understanding

- [ ] Add an OCR provider plugin interface that returns text, confidence, and source-image references; keep OCR optional and out of the text-native core path.
- [ ] Add structured reading-order blocks for headings, paragraphs, lists, tables, captions, and columns while preserving page/span evidence.
- [ ] Add links, bookmarks, annotations, forms, attachments, JavaScript-action warnings, XMP, and named-destination extraction behind bounded options.
- [ ] Add optional language detection, token statistics, named-entity hints, and document-level summaries without making them part of the deterministic core artifact.
- [ ] Add optional evidence verification that reopens the original PDF only when explicitly requested.

### P2.2 Collections and discovery

- [ ] Add multi-document/corpus import with document/file-glob filters and one index namespace per compatible configuration.
- [ ] Add collection manifests, document aliases, duplicate detection, source relocation, and resumable imports.
- [ ] Add watch-mode hooks for changed/added/removed PDFs while leaving scheduling and UI notifications to the host application.
- [ ] Add cross-document search with stable document/page ordering, scoped filters, and per-document freshness state.

### P2.3 Search enrichment

- [ ] Add optional relevance ranking after source-order correctness is benchmarked and documented.
- [ ] Add opt-in fuzzy, stemming, synonym, language, and proximity search with explicit query-version negotiation.
- [ ] Add result facets for document, page, heading, date, language, confidence, and extracted object type.
- [ ] Add result streaming or bounded pagination for large corpora without changing the deterministic result model.
- [ ] Add export adapters for JSON, JSONL, CSV, Markdown citations, and evidence packages containing source references and boxes.

### P2.4 Scale and backend evolution

- [ ] Add measured safe parallelism for parser stages and batched storage writes; do not parallelize SQLite writes speculatively.
- [ ] Evaluate a custom memory-mapped postings index only if SQLite/FTS5 misses published targets; retain the narrow `IndexStore` interface.
- [ ] Add remote-free, content-addressed artifact caching and deduplicated page storage for repeated imports.
- [ ] Add resumable indexing, back-pressure, resource quotas, and host-controlled cancellation for long-running collections.

## P3 - maintenance and productization

- [ ] Publish benchmark history and regression thresholds per fixture.
- [ ] Add changelog/release notes tied to artifact, index, and query schema versions.
- [ ] Add shell completion and man-page/reference documentation after the command grammar stabilizes.
- [ ] Add reproducible packaging artifacts and signed release checksums.
- [ ] Add issue templates for parser coverage, fixture regressions, safety reports, and performance regressions.

## Suggested execution order

1. HL-1: freeze the embedded API and prove it from an external project.
2. HL-2: build the fixture, golden, CLI, and benchmark-smoke harness.
3. HL-3: isolate Poppler/SQLite execution and enforce resource limits.
4. HL-4: make extraction/indexing a durable cache with recovery and progress.
5. HL-5: lock down source-to-normalized evidence mapping and result provenance.
6. Close the matching P0/P1 items, then publish packaging, CI, and compatibility guarantees.
7. HL-6: add OCR, corpus, structured-document, and ranking providers only after the baseline contracts are stable.
