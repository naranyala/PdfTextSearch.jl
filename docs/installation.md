# Installation and prerequisites

## Requirements

PdfTextSearch.jl currently runs directly from this repository and requires:

- Julia 1.10 or newer.
- Poppler command-line utilities: `pdfinfo`, `pdftotext`, and `pdfimages`.
- The `sqlite3` command-line client built with FTS5 support.

The Julia project currently uses only standard-library modules, so a `Manifest.toml` is not required for the MVP checkout workflow.

## Verify a machine

From the repository root, run:

```bash
julia --project=. bin/pdftextsearch doctor
```

The diagnostic checks the Julia runtime, the required Poppler commands, SQLite availability, and SQLite FTS5 support. It exits non-zero when a required dependency is missing.

You can also inspect the exact versions visible to the shell:

```bash
julia --version
pdfinfo -v
pdftotext -v
pdfimages -v
sqlite3 --version
```

Install Poppler and SQLite using the package manager appropriate for the host operating system. Package names vary by distribution; the important part is that the commands above are on `PATH`.

## Run from the checkout

The supported development invocation is:

```bash
julia --project=. bin/pdftextsearch --help
```

The current repository entry point is not yet a registered Julia package executable. Packaged installation, dependency pinning, and release artifacts are tracked in [TODOS.md](../TODOS.md).

## First extraction

```bash
julia --project=. bin/pdftextsearch inspect annual-report.pdf --json
julia --project=. bin/pdftextsearch extract annual-report.pdf --out derived/annual-report
julia --project=. bin/pdftextsearch index derived/annual-report
julia --project=. bin/pdftextsearch search derived/annual-report '"supply chain resilience"' --boxes
```

Use shell single quotes around a query containing double quotes. The inner double quotes tell PdfTextSearch.jl to search the adjacent words as an exact phrase.

## Operational notes

- PdfTextSearch.jl does not modify the source PDF.
- Output paths are created as needed, but an existing non-empty extraction directory is refused unless `extract --force` is used.
- `extract --force` preserves the previous directory under a timestamped `.previous-*` sibling before writing the replacement.
- The current subprocess boundary does not yet provide complete timeouts, cancellation, or resource budgets for hostile or unusually large PDFs. Review [limitations and safety notes](limitations.md) before processing untrusted input at scale.
