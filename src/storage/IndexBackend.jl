"""Backend seam for searchable index storage."""
abstract type IndexBackend end

"""SQLite command-line backend retained as the default compatibility adapter."""
struct SQLiteCLIBackend <: IndexBackend
    runner::ToolRunner
end

# The default remains intentionally conservative for the current release. A
# native SQLite backend can be added later without changing Query.jl callers.
SQLiteCLIBackend(; runner=ToolRunner()) = SQLiteCLIBackend(runner)

const DEFAULT_INDEX_BACKEND = SQLiteCLIBackend()
