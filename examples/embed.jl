#!/usr/bin/env julia

using PdfTextSearch

if length(ARGS) < 3
    println(stderr, "usage: julia --project=. examples/embed.jl FILE.pdf ARTIFACT_DIR QUERY")
    exit(2)
end

source, artifact_directory, query = ARGS[1:3]
# This is the host-owned workflow: inspect for UI metadata, then reuse the
# durable artifact/index for repeated search requests.
println("capabilities: ", PdfTextSearch.capabilities())
println("inspection: ", PdfTextSearch.inspect_pdf(source))

plan = PdfTextSearch.ExtractionPlan(
    output=artifact_directory,
    include_boxes=true,
    reuse=true,
)
directory = PdfTextSearch.extract_pdf(source, plan)
PdfTextSearch.index_directory(directory)
println("status: ", PdfTextSearch.status(directory))
println("hits: ", PdfTextSearch.search(directory, query; boxes=true, explain=true))
