# CLI reference

## Invocation

```bash
julia --project=. bin/pdftextsearch <command> [options]
```

The command writes diagnostics and human-readable summaries to stderr. Commands that support `--json` write machine-readable JSON to stdout.

## Commands

### `inspect`

Report PDF metadata and basic extraction health.

```bash
julia --project=. bin/pdftextsearch inspect <file.pdf> [--json] [--pages] [--objects]
```

- `--json` emits an inspection object.
- `--pages` includes page records in JSON output.
- `--objects` includes the current object-inspection section. Low-level object detail is still limited in the MVP.

The inspection is best effort: metadata comes from `pdfinfo`, while text health is checked through `pdftotext`.

### `extract`

Create deterministic page and span artifacts from a PDF.

```bash
julia --project=. bin/pdftextsearch extract <file.pdf> --out <directory> [--pages A:B] [--force] [--json]
```

- `--out <directory>` is required.
- `--pages A:B` selects an inclusive page range. A single page can be written as `N:N`.
- `--force` replaces a non-empty destination after preserving the previous directory as a timestamped sibling.
- `--json` emits the extraction manifest/result.

Without `--pages`, all pages are selected. Extraction creates `manifest.json`, `inspect.json`, `pages.jsonl`, `spans.jsonl`, page text files, and a `build-report.json`. The directory is marked `extracted` until indexing completes.

### `index`

Build or rebuild the local SQLite/FTS5 search index.

```bash
julia --project=. bin/pdftextsearch index <directory> [--force] [--json]
```

- The directory must contain extraction artifacts.
- `--force` permits rebuilding an existing index.
- `--json` emits the indexing result.

Successful indexing records the source hash and marks the manifest state `fresh`.

### `search`

Search indexed page text and return evidence locations.

```bash
julia --project=. bin/pdftextsearch search <directory> <query> [options]
```

Supported options:

- `--json` emits a JSON array instead of human-readable matches.
- `--page <N>` limits matches to one page.
- `--pages <A:B>` limits matches to an inclusive page range.
- `--context <N>` controls the snippet context size in characters.
- `--limit <N>` limits the number of returned page hits.
- `--boxes` includes match bounding boxes when available.
- `--explain` includes diagnostic search details.
- `--regex` treats the query as a Julia regular expression and scans extracted page text.
- `--literal` disables query tokenization and searches the supplied text literally.

Query behavior:

```bash
# Exact phrase; the shell preserves the inner quotes.
julia --project=. bin/pdftextsearch search derived/report '"supply chain resilience"'

# Unquoted words are AND terms. All terms must be present on the same page.
julia --project=. bin/pdftextsearch search derived/report 'supply chain resilience'

# Literal text, useful for punctuation or symbols.
julia --project=. bin/pdftextsearch search derived/report 'C++' --literal

# A regular expression over normalized page text.
julia --project=. bin/pdftextsearch search derived/report 'supply\\s+chain' --regex
```

The MVP returns one result per matching page. Each result identifies the document, source path, page, match count, matched ranges, a context snippet, and optional boxes. Search is local to one extraction directory; corpus-wide search is planned.

### `status`

Explain extraction and index freshness.

```bash
julia --project=. bin/pdftextsearch status <directory> [--json]
```

The status check compares the current source SHA-256 with the manifest and index metadata. A source change, missing index, or incomplete build makes the directory stale or incomplete.

### `unpack`

Export selected PDF assets.

```bash
julia --project=. bin/pdftextsearch unpack <file.pdf> --out <directory> [--what images,...]
```

The current implementation supports `images` through Poppler's `pdfimages`. Attachment, font, and other object-class extraction are reserved for future work. Unsupported selections produce a diagnostic rather than silently claiming success.

### `doctor`

Diagnose local setup and optional fixture availability.

```bash
julia --project=. bin/pdftextsearch doctor [--fixtures <directory>] [--json]
```

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | Success |
| `2` | Usage or argument error |
| `3` | Missing input or output path |
| `4` | External dependency or helper failure |
| `5` | Invalid or stale derived artifacts |
| `10` | Unexpected internal error |

## Accepted but incomplete options

The CLI parser accepts some global options for forward compatibility, including `--config`, `--jobs`, `--quiet`, and `--verbose`. Their behavior is not complete in the MVP; see [TODOS.md](../TODOS.md) before relying on them in automation.
