# PDFProbe

PDFProbe is a local-first Julia CLI for inspecting PDFs, extracting deterministic text artifacts, indexing them with SQLite/FTS5, and returning evidence-backed search matches.

This repository contains the first vertical slice from the software requirements blueprint. It favors an explicit artifact contract and replaceable boundaries so native parsing, richer inspection, OCR, and a custom index can be added without changing the core workflow.

## Quick start

Prerequisites are Julia 1.10+, Poppler (`pdfinfo`, `pdftotext`, `pdfimages`), and `sqlite3` with FTS5 support. Verify them with:

```bash
julia --project=. bin/pdfprobe doctor
```

Then inspect, extract, index, and search:

```bash
julia --project=. bin/pdfprobe inspect annual-report.pdf --json > annual-report.inspect.json
julia --project=. bin/pdfprobe extract annual-report.pdf --out derived/annual-report
julia --project=. bin/pdfprobe index derived/annual-report
julia --project=. bin/pdfprobe search derived/annual-report '"supply chain resilience"' --boxes
julia --project=. bin/pdfprobe status derived/annual-report --json
```

The inner double quotes in the search example request exact phrase semantics; the outer single quotes protect them from the shell. Use `extract --force` only when replacement is intentional. PDFProbe refuses to overwrite a non-empty derived directory by default and preserves a forced replacement as a timestamped `.previous-*` sibling.

## Documentation

The documentation set lives in [`docs/index.md`](docs/index.md):

- [Installation and prerequisites](docs/installation.md)
- [CLI reference](docs/cli-reference.md)
- [Artifact and index schema](docs/artifact-schema.md)
- [Architecture](docs/architecture.md)
- [Development workflow](docs/development.md)
- [Limitations and safety notes](docs/limitations.md)
- [Requirements mapping](docs/requirements.md)
- [Open implementation gaps](TODOS.md)

## Artifact contract

An extraction directory contains `manifest.json`, `inspect.json`, `pages.jsonl`, `spans.jsonl`, normalized `text/page-XXXX.txt` files, `assets/`, `index.sqlite`, and `build-report.json`. The [artifact schema](docs/artifact-schema.md) documents current fields, freshness states, offsets, and coordinate conventions.

Search results are stable JSON arrays when `--json` is supplied. Match offsets use 1-based character indexing with an exclusive `stop`; optional boxes use PDF point values from the current adapter.

## Public API

```julia
using PDFProbe

report = inspect_pdf("annual-report.pdf")
plan = ExtractionPlan(output="derived/report", include_boxes=true)
extract_pdf("annual-report.pdf", plan)
index_directory("derived/report")
hits = search("derived/report", "supply chain resilience"; page=12, limit=20)
```

## Development

Run the repository test suite with:

```bash
julia --project=. test/runtests.jl
```

The current slice intentionally leaves OCR, low-level object inspection, attachment/font unpacking, corpus search, richer query filters, packaged installation, and a custom mmap index incomplete. See [`TODOS.md`](TODOS.md) for the prioritized backlog and [`docs/limitations.md`](docs/limitations.md) for operational caveats.

## Exit codes

`0` success · `2` usage/argument error · `3` missing input/output · `4` external helper failure · `5` invalid/stale artifacts · `10` unexpected internal error.
