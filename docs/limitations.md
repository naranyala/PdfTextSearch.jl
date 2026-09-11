# Limitations and safety notes

PdfTextSearch.jl is an MVP extraction and search pipeline, not yet a hardened general-purpose PDF forensics engine. The following limitations are intentional and tracked in [TODOS.md](../TODOS.md).

## Capability limits

- Parsing currently delegates to Poppler executables rather than a native Julia PDF parser.
- Metadata and health inspection are useful summaries, but low-level objects, annotations, forms, fonts, attachments, JavaScript, named destinations, and XMP are incomplete.
- Per-page dimensions, rotation, and object counts are best effort in the current adapter.
- `unpack` currently exports images; attachments and fonts are not implemented.
- Search covers one extracted directory at a time. Corpus search, richer filters, ranking controls, and a custom mmap index are future work.
- OCR for scanned/image-only PDFs is not implemented.
- Source-to-normalized text maps and full reading-order metadata are not yet persisted.
- CLI configuration, parallel jobs, quiet/verbose logging, command-specific help, and complete SIGINT handling are not finished.

## Safety model today

- The source PDF is read-only from PdfTextSearch.jl's perspective.
- Extraction refuses to overwrite an existing non-empty directory unless `--force` is explicit.
- Forced extraction preserves the prior directory under a timestamped sibling before replacement.
- External helper failures are surfaced as typed PdfTextSearch.jl errors or non-zero exit codes.
- `status` checks source hashes so consumers can detect an index that no longer describes the current PDF.

These safeguards do not make arbitrary PDFs safe to process without operational controls. The helper subprocesses do not yet have complete timeouts, cancellation, memory limits, page-count budgets, output quotas, or sandboxing. Process untrusted files in an isolated environment and set host-level resource limits where appropriate.

## Compatibility limits

The generated artifacts depend on the versions and behavior of Poppler and SQLite available on `PATH`. Until parser and index schemas are versioned and migration support is added, do not assume that an `index.sqlite` created by a different toolchain is interchangeable.

## Reporting a gap

When documenting a missing capability, include the PDF type, operating system, helper versions, command, and a minimized reproduction if possible. Add or update the matching priority item in [TODOS.md](../TODOS.md), and add a fixture when the behavior should remain stable.
