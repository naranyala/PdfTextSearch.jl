"""Local-first PDF extraction, indexing, and evidence-backed search."""
module PdfTextSearch

# Includes are ordered from shared contracts to higher-level workflows. Keeping
# the CLI last makes every library operation available without invoking it.
include("Errors.jl")
include("ToolRunner.jl")
include("IndexBackend.jl")
include("Model.jl")
include("Normalize.jl")
include("Output.jl")
include("PDFReader.jl")
include("Providers.jl")
include("API.jl")
include("Extract.jl")
include("IndexStore.jl")
include("Query.jl")
include("Unpack.jl")
include("Benchmarks.jl")
include("CLI.jl")

export PdfTextSearchError, ExtractionPlan, IndexHandle, Span, BBox, PageRecord
export ToolResult, ToolRunner, run_tool, IndexBackend, SQLiteCLIBackend
export OCRPage, OCRResult, AbstractOCRProvider, AbstractEnrichmentProvider
export package_version, capabilities, provider_capabilities, artifact_cache_key, cache_status, serialize_result
export cache_lock_path, acquire_cache_lock, release_cache_lock
export error_code_name, error_dict
export inspect_pdf, extract_pdf, index_directory, open_index, search, status
export unpack_pdf, doctor_report, main

end
