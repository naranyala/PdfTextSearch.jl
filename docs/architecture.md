# PdfTextSearch.jl architecture

The command path is intentionally staged:

```text
PDF bytes -> ToolRunner/PDFReader -> PageRecord/Span + offset map -> JSONL artifacts -> IndexBackend/SQLite-FTS5 -> Query -> evidence output
```

`PDFReader.jl` is the only layer that knows about Poppler. The text model carries page identity, normalized and original text, character offsets, and optional boxes. `IndexStore.jl` treats SQLite as an acceleration layer; JSONL remains the inspectable source of derived evidence. `Query.jl` runs candidate retrieval against FTS5 and maps only returned pages back to spans for bounded evidence rendering.

The current adapter boundary is intentionally pragmatic: PDF inspection and text extraction use Poppler command-line helpers through `ToolRunner`, while indexing uses the `SQLiteCLIBackend` through `IndexBackend`. Both boundaries are replaceable without changing query or evidence semantics; see [limitations.md](limitations.md) and [TODOS.md](../TODOS.md).

The manifest is the freshness authority. It records source SHA-256, a cache key, parser version, normalization rules, extraction options, and index schema version. Index publication happens through a temporary database followed by a rename, and the manifest is marked fresh only after row-count validation. Normalized offsets carry an explicit map back to the page's original text representation.

## Requirements mapped to this slice

- FR-001/002/003/006/007: input validation, source hashing, `pdfinfo` inspection, JSON output, immutable source handling.
- FR-004/009/011/012/013: page records, image-only health, normalized spans, manifest configuration.
- FR-016/017: explicit overwrite protection and recoverable failed build reports.
- FR-020-026/028-029: query parsing, FTS5, page filters, snippets, offsets, boxes, success on zero hits, explain metadata.
- FR-021/022/030-ish acceptance surface: stable ordered JSON result objects and documented offsets.

## Decision record

The Poppler adapter is a pragmatic M0/M1 choice for an empty repository: it makes the vertical slice executable immediately and keeps the parser seam explicit. A native Julia parser can replace it after fixture-driven comparison without changing artifacts, the CLI, or the index schema.

For command syntax, see [cli-reference.md](cli-reference.md). For the on-disk contract, see [artifact-schema.md](artifact-schema.md).
