"""Local-first PDF extraction, indexing, and evidence-backed search."""
module PdfTextSearch

# Includes are ordered by dependency rather than directory. Keeping the CLI
# last makes every library operation available without invoking it.
include("core/Errors.jl")
include("adapters/ToolRunner.jl")
include("storage/IndexBackend.jl")
include("core/Models.jl")
include("core/Normalize.jl")
include("core/JSON.jl")
include("adapters/PDFReader.jl")
include("adapters/Providers.jl")
include("workflows/API.jl")
include("workflows/Extract.jl")
include("storage/IndexStore.jl")
include("workflows/Query.jl")
include("workflows/Unpack.jl")
include("benchmarks/Benchmarks.jl")
include("cli/CLI.jl")

export PdfTextSearchError, ExtractionPlan, IndexHandle, Span, BBox, PageRecord
export ToolResult, ToolRunner, run_tool, IndexBackend, SQLiteCLIBackend
export OCRPage, OCRResult, AbstractOCRProvider, AbstractEnrichmentProvider
export package_version, capabilities, provider_capabilities, artifact_cache_key, cache_status, serialize_result
export cache_lock_path, acquire_cache_lock, release_cache_lock
export error_code_name, error_dict
export inspect_pdf, extract_pdf, index_directory, open_index, search, status
export unpack_pdf, doctor_report, main

end
