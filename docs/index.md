# PDFProbe documentation

PDFProbe is a local-first Julia command-line tool for inspecting PDF metadata, extracting deterministic text artifacts, building a searchable local index, and returning evidence-backed matches.

This documentation describes the current MVP in this repository. The implementation is intentionally explicit about the external tools it uses and the capabilities that remain on the roadmap.

## Start here

- [Installation and prerequisites](installation.md)
- [CLI reference](cli-reference.md)
- [Artifact and index schema](artifact-schema.md)
- [Architecture](architecture.md)
- [Development workflow](development.md)
- [Limitations and safety notes](limitations.md)
- [Requirements mapping](requirements.md)
- [Open implementation gaps](../TODOS.md)

## Typical workflow

```text
PDF
  -> inspect
  -> extract
  -> index
  -> search / status
  -> unpack selected images when needed
```

The extraction directory is the durable boundary between PDF processing and search. It contains the normalized page text, page and span records, source metadata, and—after indexing—the SQLite/FTS5 database.

## Current contract

- Commands are run from the checkout with `julia --project=. bin/pdfprobe ...`.
- Human-readable diagnostics go to stderr; machine-readable results go to stdout where a command supports `--json`.
- Existing non-empty extraction directories are not overwritten unless `--force` is supplied.
- Search offsets are 1-based character positions with an exclusive `stop` value.
- Coordinates are optional evidence boxes in the adapter's PDF point coordinate system.

For planned work, see [TODOS.md](../TODOS.md). It distinguishes the implemented first vertical slice from the missing production-hardening, parser, indexing, OCR, and packaging work.
