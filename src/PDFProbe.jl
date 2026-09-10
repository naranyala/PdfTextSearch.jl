module PDFProbe

include("Errors.jl")
include("Model.jl")
include("Normalize.jl")
include("Output.jl")
include("PDFReader.jl")
include("Extract.jl")
include("IndexStore.jl")
include("Query.jl")
include("Unpack.jl")
include("Benchmarks.jl")
include("CLI.jl")

export PDFProbeError, ExtractionPlan, IndexHandle, Span, BBox, PageRecord
export inspect_pdf, extract_pdf, index_directory, open_index, search, status
export unpack_pdf, doctor_report, main

end
