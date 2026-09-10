using SHA

const PDFINFO_BIN = "pdfinfo"
const PDFTEXT_BIN = "pdftotext"
const PDFIMAGES_BIN = "pdfimages"

function executable_available(name::AbstractString)
    Sys.which(name) !== nothing
end

function ensure_pdf_path(path::AbstractString; action="inspect")
    source = abspath(String(path))
    isfile(source) || probe_error(EXIT_INPUT, action, source, "file does not exist", recovery="check the path and permissions")
    readable = try
        open(source, "r") do io
            read(io, min(5, filesize(source)))
        end
        true
    catch
        false
    end
    readable || probe_error(EXIT_INPUT, action, source, "file is not readable", recovery="check the path and permissions")
    header = open(source, "r") do io
        read(io, min(5, filesize(source)))
    end
    length(header) >= 5 && String(header) == "%PDF-" ||
        probe_error(EXIT_INPUT, action, source, "input is not a PDF file", recovery="provide a file beginning with the %PDF- signature")
    source
end

function sha256_file(path::AbstractString)
    bytes2hex(SHA.sha256(read(path)))
end

function run_pdf_command(binary::AbstractString, args::Vector{String}, action::AbstractString, target::AbstractString)
    executable_available(binary) || probe_error(EXIT_INTERNAL, action, target,
        "required helper '$binary' is not installed", recovery="install Poppler utilities and retry")
    try
        read(Cmd([binary; args]), String)
    catch err
        message = err isa ProcessFailedException ? "PDF helper '$binary' could not process the file" : sprint(showerror, err)
        probe_error(EXIT_PARSE, action, target, message, recovery="retry in tolerant mode or inspect the PDF with another reader")
    end
end

function pdfinfo(source::AbstractString)
    output = run_pdf_command(PDFINFO_BIN, [source], "inspect", source)
    values = Dict{String,String}()
    for line in split(output, '\n')
        pieces = split(line, ':'; limit=2)
        length(pieces) == 2 || continue
        values[strip(pieces[1])] = strip(pieces[2])
    end
    values
end

parse_int_or(value, fallback=0) = try parse(Int, strip(string(value))) catch; fallback end
parse_float_or(value, fallback=0.0) = try parse(Float64, strip(string(value))) catch; fallback end

function parse_bool(value)
    lowercase(strip(string(value))) in ("yes", "true", "1")
end

function page_size(info::Dict{String,String})
    raw = get(info, "Page size", "595.276 x 841.89 pts (A4)")
    match_result = match(r"([0-9.]+)\s+x\s+([0-9.]+)", raw)
    match_result === nothing && return (595.276, 841.89)
    parse_float_or(match_result.captures[1], 595.276), parse_float_or(match_result.captures[2], 841.89)
end

function pdf_page_texts(source::AbstractString, page_count::Int)
    output = run_pdf_command(PDFTEXT_BIN, ["-layout", source, "-"], "extract", source)
    chunks = split(output, '\f'; keepempty=true)
    # pdftotext conventionally leaves a trailing form-feed after the last page.
    length(chunks) > page_count && (chunks = chunks[1:page_count])
    while length(chunks) < page_count
        push!(chunks, "")
    end
    [replace(chunk, r"[ \t]+\n" => "\n") for chunk in chunks[1:page_count]]
end

function image_counts(source::AbstractString, page_count::Int)
    counts = zeros(Int, page_count)
    warnings = String[]
    if !executable_available(PDFIMAGES_BIN)
        push!(warnings, "image_count_unavailable: pdfimages is not installed")
        return counts, warnings
    end
    output = try
        read(`$(PDFIMAGES_BIN) -list $(source)`, String)
    catch
        push!(warnings, "image_count_unavailable: pdfimages could not inspect the file")
        return counts, warnings
    end
    data_started = false
    for line in split(output, '\n')
        stripped = strip(line)
        startswith(stripped, "page") && (data_started = true; continue)
        data_started || continue
        fields = split(stripped)
        isempty(fields) && continue
        page = try parse(Int, fields[1]) catch; 0 end
        1 <= page <= page_count && (counts[page] += 1)
    end
    counts, warnings
end

function html_unescape(value::AbstractString)
    result = replace(String(value), "&lt;" => "<", "&gt;" => ">", "&amp;" => "&", "&quot;" => "\"", "&apos;" => "'")
    for match_result in collect(eachmatch(r"&#x([0-9A-Fa-f]+);", result))
        replacement = try string(Char(parse(Int, match_result.captures[1]; base=16))) catch; match_result.match end
        result = replace(result, match_result.match => replacement)
    end
    for match_result in collect(eachmatch(r"&#([0-9]+);", result))
        replacement = try string(Char(parse(Int, match_result.captures[1]))) catch; match_result.match end
        result = replace(result, match_result.match => replacement)
    end
    result
end

function xml_attribute(tag::AbstractString, name::AbstractString, fallback=nothing)
    match_result = match(Regex("\\b" * name * "=\\\"([^\\\"]*)\\\""), tag)
    match_result === nothing ? fallback : match_result.captures[1]
end

function bbox_from_attributes(tag::AbstractString)
    values = [xml_attribute(tag, name, "") for name in ("xMin", "yMin", "xMax", "yMax")]
    any(isempty, values) && return nothing
    BBox(parse_float_or(values[1]), parse_float_or(values[2]), parse_float_or(values[3]), parse_float_or(values[4]))
end

function bbox_pages(source::AbstractString, page_count::Int)
    output = run_pdf_command(PDFTEXT_BIN, ["-bbox-layout", source, "-"], "extract", source)
    parsed = NamedTuple[]
    page_matches = eachmatch(r"<page\b[^>]*>.*?</page>"s, output)
    for page_match in page_matches
        block = page_match.match
        page_tag_match = match(r"<page\b[^>]*>", block)
        page_tag_match === nothing && continue
        page_tag = page_tag_match.match
        width = parse_float_or(xml_attribute(page_tag, "width", "595.276"), 595.276)
        height = parse_float_or(xml_attribute(page_tag, "height", "841.89"), 841.89)
        words = NamedTuple[]
        line_no = 0
        for line_match in eachmatch(r"<line\b[^>]*>(.*?)</line>"s, block)
            line_no += 1
            line_content = line_match.captures[1]
            for word_match in eachmatch(r"<word\b([^>]*)>(.*?)</word>"s, line_content)
                attributes, encoded = word_match.captures
                text = html_unescape(encoded)
                isempty(text) && continue
                push!(words, (text=text, bbox=bbox_from_attributes(attributes), line=line_no))
            end
        end
        push!(parsed, (width=width, height=height, rotation=0, words=words))
    end
    while length(parsed) < page_count
        push!(parsed, (width=595.276, height=841.89, rotation=0, words=NamedTuple[]))
    end
    length(parsed) > page_count && (parsed = parsed[1:page_count])
    parsed
end

function build_page_text(words, page_number::Int; include_boxes=true)
    chars = Char[]
    original_chars = Char[]
    spans = Span[]
    previous_word = nothing
    previous_span_index = 0
    for word in words
        normalized = normalize_word(word.text)
        isempty(normalized) && continue
        joined = false
        if !isempty(chars) && previous_word !== nothing
            previous_normalized = normalize_word(previous_word.text)
            joined = endswith(previous_normalized, "-") && word.line > previous_word.line &&
                     isletter(first(normalized))
            if joined
                pop!(chars)
                pop!(original_chars)
                if previous_span_index > 0
                    prior = spans[previous_span_index]
                    prior_chars = char_vector(prior.text)
                    shortened = length(prior_chars) > 1 ? String(prior_chars[1:end-1]) : ""
                    spans[previous_span_index] = Span(prior.span_id, prior.page_number, prior.start,
                        prior.stop - 1, shortened, prior.original_text, prior.bbox)
                end
            else
                push!(chars, ' ')
                push!(original_chars, ' ')
            end
        end
        start = length(chars) + 1
        append!(chars, char_vector(normalized))
        append!(original_chars, char_vector(word.text))
        stop = length(chars) + 1
        box = include_boxes ? word.bbox : nothing
        push!(spans, Span(length(spans) + 1, page_number, start, stop, normalized, word.text, box))
        previous_span_index = length(spans)
        previous_word = word
    end
    String(chars), String(original_chars), spans
end

function fallback_page(page_text::AbstractString, page_number::Int, width::Float64, height::Float64,
                       document_id::String, image_count::Int; include_boxes=true)
    normalized = normalize_text(page_text)
    spans = isempty(normalized) ? Span[] : [Span(1, page_number, 1, length(char_vector(normalized)) + 1,
                                                  normalized, String(page_text), nothing)]
    PageRecord(document_id, page_number, width, height, 0, normalized, String(page_text),
               sha256_hex(normalized), spans, image_count, 0, "fallback", String[])
end

function sha256_hex(value::AbstractString)
    bytes2hex(SHA.sha256(codeunits(String(value))))
end

function extract_pages(source::AbstractString; pages=nothing, include_boxes=true, strict=false)
    source = ensure_pdf_path(source; action="extract")
    info = pdfinfo(source)
    page_count = parse_int_or(get(info, "Pages", "0"), 0)
    page_count > 0 || probe_error(EXIT_PARSE, "extract", source, "PDF reports no pages", recovery="use a valid PDF or tolerant parser")
    selected = pages === nothing ? collect(1:page_count) : collect(pages)
    all(number -> 1 <= number <= page_count, selected) || probe_error(EXIT_USAGE, "extract", source, "page selection is outside the document", recovery="choose pages between 1 and $page_count")
    widths, heights = page_size(info)
    counts, image_warnings = image_counts(source, page_count)
    document_id = "sha256:" * sha256_file(source)
    warnings = String[]
    append!(warnings, image_warnings)
    parsed = try
        bbox_pages(source, page_count)
    catch err
        strict && rethrow(err)
        push!(warnings, "geometry_unavailable: falling back to page text extraction")
        nothing
    end
    texts = parsed === nothing ? pdf_page_texts(source, page_count) : nothing
    result = PageRecord[]
    for number in selected
        if parsed === nothing || isempty(parsed[number].words)
            text = texts === nothing ? "" : texts[number]
            page = fallback_page(text, number, widths, heights, document_id, counts[number]; include_boxes=include_boxes)
        else
            parsed_page = parsed[number]
            normalized, original, spans = build_page_text(parsed_page.words, number; include_boxes=include_boxes)
            page = PageRecord(document_id, number, parsed_page.width, parsed_page.height, parsed_page.rotation,
                              normalized, original, sha256_hex(normalized), spans, counts[number], 0,
                              "ok", String[])
        end
        !isempty(warnings) && (page = PageRecord(page.document_id, page.page_number, page.width, page.height,
            page.rotation, page.text, page.original_text, page.text_hash, page.spans, page.image_count,
            page.annotation_count, page.extraction_status, copy(warnings)))
        push!(result, page)
    end
    result, info, warnings, page_count
end

function inspect_pdf(path::AbstractString; include_pages=false, include_objects=false,
                     include_fonts=false, include_images=false, strict=false)
    source = ensure_pdf_path(path; action="inspect")
    info = pdfinfo(source)
    page_count = parse_int_or(get(info, "Pages", "0"), 0)
    width, height = page_size(info)
    warnings = String[]
    page_text = try
        pdf_page_texts(source, page_count)
    catch err
        strict && rethrow(err)
        push!(warnings, "text_health_unavailable: $(sprint(showerror, err))")
        fill("", page_count)
    end
    counts, image_warnings = image_counts(source, page_count)
    append!(warnings, image_warnings)
    text_native = count(text -> !isempty(text), [normalize_text(text) for text in page_text])
    page_details = Any[]
    if include_pages
        for number in 1:page_count
            push!(page_details, Dict{String,Any}(
                "page_number" => number,
                "width" => width,
                "height" => height,
                "rotation" => 0,
                "text_present" => !isempty(normalize_text(page_text[number])),
                "image_count" => counts[number],
                "annotation_count" => 0,
                "extraction_status" => isempty(normalize_text(page_text[number])) ? "empty_or_image_only" : "text_present",
            ))
        end
    end
    report = Dict{String,Any}(
        "schema_version" => ARTIFACT_SCHEMA_VERSION,
        "source" => Dict{String,Any}("path" => source, "sha256" => sha256_file(source), "size_bytes" => filesize(source)),
        "pdf" => Dict{String,Any}(
            "version" => get(info, "PDF version", "unknown"),
            "pages" => page_count,
            "encrypted" => parse_bool(get(info, "Encrypted", "no")),
            "linearized" => parse_bool(get(info, "Linearized", "no")),
        ),
        "metadata" => Dict{String,Any}(key => value for (key, value) in info if key in ("Title", "Author", "Subject", "Keywords", "Creator", "Producer", "CreationDate", "ModDate")),
        "health" => Dict{String,Any}("text_native_pages" => text_native, "image_only_pages" => page_count - text_native),
        "warnings" => warnings,
    )
    include_pages && (report["pages"] = page_details)
    if include_objects || include_fonts || include_images
        report["objects"] = Dict{String,Any}(
            "images" => sum(counts),
            "fonts" => "unavailable_without_low_level_reader",
            "annotations" => "unavailable_without_low_level_reader",
            "attachments" => "unavailable_without_low_level_reader",
        )
    end
    report
end
