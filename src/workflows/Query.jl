struct QuerySpec
    raw::String
    phrases::Vector{String}
    terms::Vector{String}
    literal::Bool
    case_sensitive::Bool
    regex::Bool
end

# Retrieval is intentionally two-stage: FTS narrows candidate pages, then Julia
# performs exact semantics and evidence offsets on the stored page text.
function parse_query(raw::AbstractString; literal=false, case_sensitive=false, regex=false)
    value = strip(String(raw))
    isempty(value) && probe_error(EXIT_USAGE, "search", "", "query is empty", recovery="provide a word or phrase")
    # Keep quoted phrases separate from terms so phrases preserve adjacency and
    # unquoted terms can retain AND semantics during candidate retrieval.
    phrases = String[]
    remaining = value
    for match_result in eachmatch(r"\"([^\"]+)\"", value)
        phrase = normalize_text(match_result.captures[1]; casefold=!case_sensitive)
        isempty(phrase) || push!(phrases, phrase)
        remaining = replace(remaining, match_result.match => " "; count=1)
    end
    terms = String[]
    for token in split(remaining)
        normalized = normalize_text(token; casefold=!case_sensitive)
        isempty(normalized) || push!(terms, normalized)
    end
    isempty(phrases) && isempty(terms) && !regex &&
        probe_error(EXIT_USAGE, "search", value, "query contains no searchable text", recovery="provide a word or phrase")
    QuerySpec(value, phrases, terms, Bool(literal), Bool(case_sensitive), Bool(regex))
end

function fts_quote(term::AbstractString)
    "\"" * replace(String(term), "\"" => "\"\"") * "\""
end

function fts_expression(spec::QuerySpec)
    pieces = String[]
    append!(pieces, fts_quote.(spec.phrases))
    append!(pieces, fts_quote.(spec.terms))
    isempty(pieces) ? "" : join(pieces, " AND ")
end

function page_where(page=nothing, page_range=nothing)
    clauses = String[]
    if page !== nothing
        push!(clauses, "p.page_number = $(parse(Int, string(page)))")
    elseif page_range !== nothing
        first_page, last_page = first(page_range), last(page_range)
        push!(clauses, "p.page_number BETWEEN $(parse(Int, string(first_page))) AND $(parse(Int, string(last_page)))")
    end
    isempty(clauses) ? "" : " AND " * join(clauses, " AND ")
end

function byte_to_char_position(text::AbstractString, byte_position::Int)
    byte_position <= 1 && return 1
    length(collect(SubString(String(text), 1, prevind(String(text), byte_position)))) + 1
end

function regex_occurrences(text::AbstractString, pattern::AbstractString)
    # Regex is a post-filter over extracted page text, never a raw SQL expression,
    # so user patterns cannot alter the index query. Resource limits remain a
    # separate hardening task.
    result = UnitRange{Int}[]
    expression = try Regex(String(pattern)) catch err
        probe_error(EXIT_USAGE, "search", pattern, "invalid regular expression: $(sprint(showerror, err))")
    end
    for match_result in eachmatch(expression, String(text))
        start = byte_to_char_position(text, match_result.offset)
        stop = start + length(char_vector(match_result.match))
        push!(result, start:stop)
    end
    result
end

function query_occurrences(text::AbstractString, spec::QuerySpec)
    target = spec.case_sensitive ? String(text) : normalize_text(text)
    if spec.regex
        return regex_occurrences(target, spec.raw)
    elseif spec.literal
        query = spec.case_sensitive ? spec.raw : normalize_text(spec.raw)
        return find_char_occurrences(target, query)
    elseif !isempty(spec.phrases)
        ranges = UnitRange{Int}[]
        for phrase in spec.phrases
            append!(ranges, find_char_occurrences(target, phrase))
        end
        return sort!(ranges; by=first)
    elseif length(spec.terms) == 1
        return find_char_occurrences(target, spec.terms[1])
    else
        ranges = UnitRange{Int}[]
        for term in spec.terms
            append!(ranges, find_char_occurrences(target, term))
        end
        sort!(ranges; by=first)
    end
end

function snippet(text::AbstractString, range::UnitRange{Int}, context::Int)
    chars = char_vector(text)
    isempty(chars) && return ""
    context = max(context, 0)
    start = max(1, first(range) - context)
    stop = min(length(chars), last(range) - 1 + context)
    prefix = start > 1 ? "..." : ""
    suffix = stop < length(chars) ? "..." : ""
    prefix * String(chars[start:stop]) * suffix
end

function original_match_range(original_text::AbstractString, range::UnitRange{Int}, case_sensitive::Bool)
    case_sensitive && return range
    mapping = normalize_with_map(original_text).mapping
    last(range) - 1 <= length(mapping) || return nothing
    first_source = first(mapping[first(range)])
    last_source = last(mapping[last(range) - 1])
    first_source:(last_source + 1)
end

function result_boxes(handle::IndexHandle, document_id::AbstractString, page_number::Int, range::UnitRange{Int})
    rows = sqlite_json(handle.database, "SELECT start,stop,x0,y0,x1,y1 FROM spans WHERE document_id=$(sql_quote(document_id)) AND page_number=$(page_number) ORDER BY span_id"; action="search", target=handle.directory, backend=handle.backend)
    result = Any[]
    for row in rows
        start = parse_int_or(row["start"], 0)
        stop = parse_int_or(row["stop"], 0)
        start < last(range) && stop > first(range) || continue
        nothing in (row["x0"], row["y0"], row["x1"], row["y1"]) && continue
        push!(result, Dict{String,Any}("x0" => Float64(row["x0"]), "y0" => Float64(row["y0"]),
                                      "x1" => Float64(row["x1"]), "y1" => Float64(row["y1"])))
    end
    result
end

function candidate_pages(handle::IndexHandle, spec::QuerySpec, page, page_range, limit::Int)
    where_clause = page_where(page, page_range)
    # Literal/regex modes bypass FTS because their semantics are character-based.
    if spec.literal || spec.regex
        return sqlite_json(handle.database, "SELECT p.document_id,p.page_number,p.text,p.original_text FROM pages p WHERE 1=1$(where_clause) ORDER BY p.page_number LIMIT $(limit)"; action="search", target=handle.directory, backend=handle.backend)
    end
    expression = fts_expression(spec)
    isempty(expression) && return Any[]
    query = "SELECT p.document_id,p.page_number,p.text,p.original_text FROM fts_pages f JOIN pages p ON p.document_id=f.document_id AND p.page_number=f.page_number WHERE fts_pages MATCH $(sql_quote(expression))$(where_clause) ORDER BY p.page_number LIMIT $(limit)"
    rows = sqlite_json(handle.database, query; action="search", target=handle.directory, backend=handle.backend)
    if isempty(rows)
        # Punctuation and ligatures may be intentionally excluded by unicode61. A bounded
        # substring fallback preserves correctness without reparsing PDFs.
        fallback = normalize_text(spec.raw; casefold=!spec.case_sensitive)
        rows = sqlite_json(handle.database, "SELECT p.document_id,p.page_number,p.text,p.original_text FROM pages p WHERE instr(p.text,$(sql_quote(fallback))) > 0$(where_clause) ORDER BY p.page_number LIMIT $(limit)"; action="search", target=handle.directory, backend=handle.backend)
    end
    rows
end

function search(handle::IndexHandle, query_text::AbstractString; page=nothing, page_range=nothing,
                limit=20, context=80, literal=false, case_sensitive=false, regex=false,
                boxes=false, explain=false)
    spec = parse_query(query_text; literal=literal, case_sensitive=case_sensitive, regex=regex)
    limit = max(1, Int(limit))
    context = max(0, Int(context))
    if page !== nothing
        page = Int(page)
        page_range = nothing
    end
    # Search never reopens the source PDF: all evidence comes from the validated
    # derived index and its stored original text.
    rows = candidate_pages(handle, spec, page, page_range, limit)
    source = manifest_source(handle.manifest)
    document_id = String(dict_get(handle.manifest, "document_id", ""))
    document_path = String(dict_get(source, "path", ""))
    result = Any[]
    for row in rows
        row_document = String(row["document_id"])
        row_document == document_id || continue
        page_number = Int(row["page_number"])
        original_text = String(row["original_text"])
        text = spec.case_sensitive ? original_text : String(row["text"])
        ranges = query_occurrences(text, spec)
        isempty(ranges) && continue
        # A multi-term query has AND semantics at the candidate-page stage; every
        # occurrence remains separately auditable in the result stream.
        for range in ranges
            match_text = text_from_chars(char_vector(text), first(range), last(range))
            source_range = original_match_range(original_text, range, spec.case_sensitive)
            item = Dict{String,Any}(
                "document" => basename(document_path),
                "source_path" => document_path,
                "page" => page_number,
                "match_count" => length(ranges),
                "match" => Dict{String,Any}("start" => first(range), "stop" => last(range), "text" => match_text),
                "snippet" => snippet(text, range, context),
            )
            if source_range !== nothing
                item["match"]["original_start"] = first(source_range)
                item["match"]["original_stop"] = last(source_range)
                item["match"]["original_text"] = text_from_chars(char_vector(original_text), first(source_range), last(source_range))
            end
            boxes && (item["boxes"] = result_boxes(handle, row_document, page_number, range))
            explain && (item["explain"] = Dict{String,Any}(
                "index" => handle.database,
                "normalization" => dict_get(handle.manifest, "normalization", Dict{String,Any}()),
                "filters" => Dict{String,Any}("page" => page, "page_range" => page_range, "limit" => limit),
            ))
            push!(result, item)
        end
    end
    sort!(result; by=item -> (Int(item["page"]), Int(item["match"]["start"])))
    length(result) > limit && (result = result[1:limit])
    result
end

function search(path::AbstractString, query_text::AbstractString; backend::IndexBackend=DEFAULT_INDEX_BACKEND, kwargs...)
    search(open_index(path; backend=backend), query_text; kwargs...)
end
