# PdfTextSearch.jl API contract

This is the embedded-library contract for downstream Julia applications. The
CLI is a presentation layer over the same functions; applications should call
the Julia API directly and keep their own UI, job, cache, and persistence
policies.

## Version and capabilities

```julia
using PdfTextSearch

PdfTextSearch.package_version()
PdfTextSearch.capabilities()
PdfTextSearch.serialize_result(value)
```

`API_VERSION` changes when exported names or their semantics change.
`artifact_schema_version` and `index_schema_version` identify on-disk formats.
Applications should record all three values with their document registry.

The stable integration surface is `ExtractionPlan`, `IndexHandle`, `Span`,
`BBox`, `PageRecord`, `ToolRunner`, `IndexBackend`, `inspect_pdf`,
`extract_pdf`, `index_directory`, `open_index`, `search`, `status`,
`artifact_cache_key`, `cache_status`, `capabilities`, `package_version`,
`serialize_result`, `error_code_name`, and `error_dict`. SQL strings, parser
helpers, and artifact file-writing helpers are implementation details.

## Processing sequence

```julia
report = PdfTextSearch.inspect_pdf(source)

plan = PdfTextSearch.ExtractionPlan(
    output=artifact_directory,
    include_boxes=true,
    reuse=true,
)
directory = PdfTextSearch.extract_pdf(source, plan)
PdfTextSearch.index_directory(directory)

state = PdfTextSearch.status(directory)
hits = PdfTextSearch.search(directory, query; boxes=true, explain=true)
```

Extraction never modifies the source PDF. It publishes a complete artifact
directory containing the manifest, inspection report, page/span JSONL, and
normalized page text. Indexing publishes `index.sqlite` only after validation.
`reuse=true` returns an existing directory only when its source/configuration
cache key is still valid.

`cache_status(directory, source)` reports the cache key, freshness reason, and
whether an atomic extraction lock is held. `acquire_cache_lock` and
`release_cache_lock` are available to hosts that coordinate additional work;
normal extraction manages this lock automatically.

## Stable result concepts

- Inspection results are dictionaries containing `schema_version`, `source`,
  `pdf`, `metadata`, `health`, and optional `pages`/`objects` sections.
- Search results are arrays of match dictionaries containing `document`,
  `source_path`, `page`, `match_count`, `match`, and `snippet`, plus optional
  `boxes` and `explain` sections.
- Normalized match offsets are 1-based character positions with an exclusive
  `stop`. When available, `original_start`, `original_stop`, and
  `original_text` locate the match in the page's `original_text` representation.
- `Span` records carry both normalized and original offsets. Geometry is
  optional and must be treated as unavailable when `bbox` is `nothing`.
- `status(directory)["fresh"]` is the authority for whether an index may be
  searched. A stale or incompatible index must be rebuilt.

## Errors

Library failures throw `PdfTextSearchError`. Its `code` is the stable process
exit code; `error_code_name(error.code)` returns the semantic name and
`error_dict(error)` returns a JSON-ready envelope:

```julia
try
    PdfTextSearch.open_index(directory)
catch error
    error isa PdfTextSearch.PdfTextSearchError || rethrow()
    payload = PdfTextSearch.error_dict(error)
end
```

The current names are `UsageError` (2), `InputError` (3), `ParseError` (4),
`IndexError` (5), and `InternalError` (10). Hosts may map these to their own
protocol but should preserve the action, message, recovery, and original exit
code in diagnostics.

## Optional providers and tools

`ToolRunner` and `IndexBackend` isolate external command execution and storage
selection. The default backend uses Poppler and the `sqlite3` CLI with FTS5.
`provider_capabilities()` reports that OCR/enrichment are unavailable until a
host supplies an optional provider. Provider output must preserve page identity,
confidence, warnings, and source provenance; it must not silently replace the
deterministic native-text path.
