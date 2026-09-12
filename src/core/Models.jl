const ARTIFACT_SCHEMA_VERSION = 2
const INDEX_SCHEMA_VERSION = 2
const PARSER_NAME = "poppler"
const PARSER_VERSION = "0.1"
const NORMALIZATION_VERSION = "1"

# Version constants are written into manifests and indexes so a caller can
# reject artifacts produced under incompatible parsing rules.
struct BBox
    x0::Float64
    y0::Float64
    x1::Float64
    y1::Float64
end

struct Span
    span_id::Int
    page_number::Int
    start::Int
    stop::Int
    original_start::Int
    original_stop::Int
    text::String
    original_text::String
    bbox::Union{Nothing,BBox}
end

# `stop` is exclusive and all offsets are 1-based character positions. The
# original pair lets search results point back through normalization changes.
struct PageRecord
    document_id::String
    page_number::Int
    width::Float64
    height::Float64
    rotation::Int
    text::String
    original_text::String
    text_hash::String
    spans::Vector{Span}
    image_count::Int
    annotation_count::Int
    extraction_status::String
    warnings::Vector{String}
end

# ExtractionPlan contains policy, not runtime state; it is safe to construct in
# the host application before dispatching work to its own job manager.
struct ExtractionPlan
    output::String
    include_boxes::Bool
    pages::Union{Nothing,UnitRange{Int}}
    strict::Bool
    force::Bool
    include_text_files::Bool
    reuse::Bool
end

function ExtractionPlan(; output, include_boxes=true, pages=nothing, strict=false,
                        force=false, include_text_files=true, reuse=false)
    selected = pages === nothing ? nothing : UnitRange{Int}(first(pages), last(pages))
    ExtractionPlan(String(output), Bool(include_boxes), selected, Bool(strict),
                   Bool(force), Bool(include_text_files), Bool(reuse))
end

# IndexHandle carries the selected backend so query code never needs to know
# whether storage is SQLite CLI, a native binding, or another implementation.
struct IndexHandle
    directory::String
    database::String
    manifest::Dict{String,Any}
    backend::IndexBackend
end

IndexHandle(directory::String, database::String, manifest::Dict{String,Any}) =
    IndexHandle(directory, database, manifest, DEFAULT_INDEX_BACKEND)

function bbox_dict(box::Union{Nothing,BBox})
    box === nothing && return nothing
    Dict{String,Any}("x0" => box.x0, "y0" => box.y0, "x1" => box.x1, "y1" => box.y1)
end

function span_dict(span::Span)
    Dict{String,Any}(
        "span_id" => span.span_id,
        "page_number" => span.page_number,
        "start" => span.start,
        "stop" => span.stop,
        "original_start" => span.original_start,
        "original_stop" => span.original_stop,
        "text" => span.text,
        "original_text" => span.original_text,
        "bbox" => bbox_dict(span.bbox),
    )
end

function page_dict(page::PageRecord; include_spans=true)
    result = Dict{String,Any}(
        "document_id" => page.document_id,
        "page_number" => page.page_number,
        "width" => page.width,
        "height" => page.height,
        "rotation" => page.rotation,
        "text" => page.text,
        "original_text" => page.original_text,
        "text_hash" => page.text_hash,
        "image_count" => page.image_count,
        "annotation_count" => page.annotation_count,
        "extraction_status" => page.extraction_status,
        "warnings" => page.warnings,
    )
    include_spans && (result["spans"] = [span_dict(s) for s in page.spans])
    result
end
