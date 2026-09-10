# PDFProbe

PDFProbe is a local-first Julia CLI for inspecting PDFs, producing stable page-aware artifacts, indexing them with SQLite/FTS5, and searching with evidence-backed results.

This repository is the first vertical slice from the software requirements blueprint:

1. `inspect` reports PDF metadata, text/image health, page details, and JSON.
2. `extract` writes a versioned manifest, `pages.jsonl`, `spans.jsonl`, page text files, and a build report without changing the source PDF.
3. `index` creates a reopenable SQLite/FTS5 index with freshness metadata.
4. `search` performs word, phrase, AND-term, literal, regex, and page-filtered searches with snippets, offsets, and optional bounding boxes.

The default reader is a deliberately isolated Poppler command-line adapter. This keeps the MVP runnable with the system tools already used for PDF diagnostics while leaving the reader boundary ready for a native Julia parser later.

## Requirements

- Julia 1.10 or newer
- Poppler utilities: `pdfinfo`, `pdftotext`, and `pdfimages`
- SQLite 3 with FTS5 support and the `sqlite3` command

Run `pdfprobe doctor` to verify the environment.

## Quick start

From the repository root:

```sh
julia --project=. bin/pdfprobe inspect annual-report.pdf
julia --project=. bin/pdfprobe inspect annual-report.pdf --json > annual-report.inspect.json
julia --project=. bin/pdfprobe extract annual-report.pdf --out derived/annual-report
julia --project=. bin/pdfprobe index derived/annual-report
julia --project=. bin/pdfprobe search derived/annual-report "supply chain resilience" --boxes
julia --project=. bin/pdfprobe status derived/annual-report
```

Progress and diagnostics are kept off JSON stdout. No command mutates the source PDF. Existing derived output is refused unless `--force` is supplied; a forced extraction moves the previous directory to a recoverable `.previous-*` sibling.

## Artifact contract

An extraction directory contains:

```text
manifest.json       source hash, parser and normalization versions, build state
inspect.json        structural and health report
pages.jsonl         one record per selected source page, including empty pages
spans.jsonl         normalized spans, offsets, original text, and optional boxes
text/page-*.txt     convenience page text views
assets/             reserved for unpacked resources
index.sqlite        SQLite/FTS5 retrieval layer after `index`
build-report.json   timings, counters, warnings, and failure state
```

Search JSON is a stable array of result objects. Offsets are 1-based character offsets with an exclusive `stop`; they refer to the normalized page text. Coordinates are in the PDF reader's point coordinate system when Poppler exposes them.

## Public API

```julia
using PDFProbe

report = inspect_pdf("annual-report.pdf")
plan = ExtractionPlan(output="derived/report", include_boxes=true)
extract_pdf("annual-report.pdf", plan)
index_directory("derived/report")
hits = search("derived/report", "supply chain resilience"; page=12, limit=20)
```

## Scope and next steps

The blueprint intentionally leaves OCR providers, deep low-level object inspection, attachment/font unpacking, custom indexes, and packaged startup benchmarks behind explicit extension points. The MVP optimizes for deterministic text-native inspection, extraction, indexing, and search first.

Stable exit codes are `0` success (including no hits), `2` usage/query error, `3` input/permission error, `4` parser/extraction failure, `5` stale/missing/corrupt index, and `10` unexpected internal error.
