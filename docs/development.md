# Development workflow

## Repository layout

```text
bin/pdfprobe          Checkout entry point
src/                  Julia implementation modules
test/runtests.jl      MVP integration and contract tests
docs/                 User and developer documentation
TODOS.md              Prioritized implementation backlog
Project.toml          Julia project metadata
```

The runtime is split by responsibility: PDF helper invocation, typed models and errors, normalization, artifact output, indexing, querying, unpacking, benchmarks, and CLI dispatch. See [architecture.md](architecture.md) for the data flow.

## Run tests

From the repository root:

```bash
julia --project=. test/runtests.jl
```

The tests generate a minimal PDF in a temporary directory and exercise the inspect → extract → index → search → status workflow. They require the same Poppler and SQLite tools as the CLI.

If the default Julia depot is not writable in a constrained environment, use a task-local depot:

```bash
JULIA_DEPOT_PATH=/tmp/pdfprobe-julia julia --project=. test/runtests.jl
```

The current suite is intentionally small. It does not yet cover a committed corpus fixture matrix, malformed PDFs, OCR, cancellation, concurrency, or cross-platform helper differences.

## Manual smoke test

```bash
julia --project=. bin/pdfprobe doctor
julia --project=. bin/pdfprobe inspect sample.pdf --json
julia --project=. bin/pdfprobe extract sample.pdf --out /tmp/pdfprobe-sample
julia --project=. bin/pdfprobe index /tmp/pdfprobe-sample
julia --project=. bin/pdfprobe search /tmp/pdfprobe-sample '"example phrase"' --json
julia --project=. bin/pdfprobe status /tmp/pdfprobe-sample --json
```

## Documentation checks

Before committing documentation changes:

```bash
git diff --check
git status --short
```

Keep command examples aligned with `bin/pdfprobe` and keep the artifact descriptions aligned with `src/Model.jl`, `src/Output.jl`, `src/IndexStore.jl`, and `src/Query.jl`.

## Design constraints

- Preserve source PDFs and make derived output explicit.
- Keep stdout suitable for pipelines and send diagnostics to stderr.
- Keep page identity, offsets, and evidence boxes traceable to source pages.
- Prefer deterministic artifacts so freshness and reproducibility can be checked.
- Keep external-tool boundaries replaceable so a native parser and Julia SQLite binding can be introduced incrementally.

## Before submitting a change

1. Update the relevant documentation and [TODOS.md](../TODOS.md) when behavior or scope changes.
2. Run the Julia test suite.
3. Run `git diff --check`.
4. Review generated artifact behavior on a representative PDF.
5. State any dependency, platform, or schema compatibility impact in the commit message or change description.
