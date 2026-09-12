# Artifact and index schema

An extraction directory is the durable, inspectable boundary between PDF processing and search. Files are deterministic for the same source, selected pages, parser configuration, and normalization policy, subject to the versions of the external tools on `PATH`.

## Directory layout

```text
derived/report/
├── manifest.json
├── inspect.json
├── pages.jsonl
├── spans.jsonl
├── text/
│   ├── page-0001.txt
│   └── ...
├── assets/
├── index.sqlite
└── build-report.json
```

`assets/` is reserved for unpacked material. The current unpacker writes extracted images there only when its output directory is selected separately.

## Manifest

`manifest.json` records provenance and freshness. The current fields are:

| Field | Meaning |
| --- | --- |
| `schema_version` | Artifact schema identifier; current value is `2`. |
| `cache_key` | Hash of source bytes, parser/normalization versions, schema, and extraction options. |
| `created_at` | UTC creation timestamp. |
| `document_id` | Stable ID derived from the source hash. |
| `source` | Source path, byte size, and SHA-256. |
| `parser` | Parser/helper information and options. |
| `normalization` | Text normalization policy and version. |
| `extraction` | Extraction options such as boxes, strict mode, and text-file output. |
| `page_count` | Number of selected extracted pages. |
| `selected_pages` | Inclusive selected page numbers. |
| `state` | Lifecycle state such as `extracted` or `fresh`. |
| `index` | Index metadata and counts when an index exists. |
| `warnings` | Non-fatal extraction or indexing warnings. |

The source hash and `cache_key` are the main freshness keys. `status` recomputes the source hash and compares it with the manifest and index metadata; `cache_status` also validates extraction options before reuse.

During extraction, an atomic directory lock is held at `derived/report.lock`
with an `owner.json` record. A concurrent builder fails before touching the
existing artifact; normal extraction removes the lock in a `finally` block.
Hosts can inspect this state through `cache_status` or use the public lock
helpers when coordinating additional work.

## Page records

`pages.jsonl` contains one JSON object per selected page. Current fields include:

| Field | Meaning |
| --- | --- |
| `document_id` | Owning document ID. |
| `page_number` | 1-based source page number. |
| `width`, `height` | Page dimensions as reported by the current PDF helper. |
| `rotation` | Page rotation value; detailed per-page rotation is not yet fully populated. |
| `text` | Normalized page text. |
| `original_text` | Text before normalization when available. |
| `text_hash` | Hash of the normalized page text. |
| `extraction_status` | Page-level success or failure status. |
| `annotation_count`, `image_count` | Current best-effort counts. |
| `warnings` | Page-level warnings. |

The `text/page-XXXX.txt` files contain the normalized text in the same order as the page records.

## Span records

`spans.jsonl` contains one record per extracted text span where the adapter can provide it. Current fields include `document_id`, `page_number`, `span_id`, `start`, `stop`, `text`, `original_text`, and optional `bbox` coordinates.

Offsets use 1-based character indexing with an exclusive `stop`. Thus a span covering characters 1 through 4 is represented as `start: 1, stop: 5`. `original_start` and `original_stop` use the same convention against the page's `original_text` representation. The current coordinate values are PDF point values emitted by the Poppler adapter; consumers should treat the coordinate convention as adapter-defined until the native parser contract is finalized.

## Inspection and build reports

- `inspect.json` stores the metadata, health checks, warnings, and optional page/object sections returned by `inspect`.
- `build-report.json` records the last extraction or indexing operation, counts, duration, state, and warnings.

These reports are useful for debugging and audit trails. A complete versioned public schema for them is planned work; see [TODOS.md](../TODOS.md).

## SQLite index

`index.sqlite` is an implementation artifact created by the `sqlite3` command-line client. The current schema creates tables for documents, pages, spans, assets, build events, and an FTS5 virtual table for page search.

Consumers should use the CLI or the documented Julia API rather than depending directly on table names. A portable Julia SQLite binding, migrations, prepared statements, and a versioned schema are tracked in [TODOS.md](../TODOS.md).

## Freshness states

| State | Meaning |
| --- | --- |
| `extracted` | Text artifacts exist, but a current search index is not confirmed. |
| `fresh` | Extraction and index metadata agree with the current source hash. |
| `stale` or `incomplete` | The source, manifest, index, or required artifact set does not agree. |

Do not treat a stale index as authoritative. Re-run `extract` and `index` when the source PDF or extraction configuration changes.
