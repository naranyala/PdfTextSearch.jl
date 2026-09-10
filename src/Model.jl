const ARTIFACT_SCHEMA_VERSION = 1
const INDEX_SCHEMA_VERSION = 1
const PARSER_NAME = "poppler"
const PARSER_VERSION = "0.1"
const NORMALIZATION_VERSION = "1"

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
    text::String
    original_text::String
    bbox::Union{Nothing,BBox}
end

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

struct ExtractionPlan
    output::String
    include_boxes::Bool
    pages::Union{Nothing,UnitRange{Int}}
    strict::Bool
    force::Bool
    include_text_files::Bool
end

function ExtractionPlan(; output, include_boxes=true, pages=nothing, strict=false,
                        force=false, include_text_files=true)
    selected = pages === nothing ? nothing : UnitRange{Int}(first(pages), last(pages))
    ExtractionPlan(String(output), Bool(include_boxes), selected, Bool(strict),
                   Bool(force), Bool(include_text_files))
end

struct IndexHandle
    directory::String
    database::String
    manifest::Dict{String,Any}
end

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
