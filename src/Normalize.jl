using Unicode

const NORMALIZATION_DESCRIPTION = Dict{String,Any}(
    "unicode" => "NFKC",
    "casefold" => true,
    "collapse_whitespace" => true,
    "join_hyphenated_linebreaks" => true,
)

# A normalized character may represent several source characters (for example,
# a composed accent or collapsed whitespace), so mappings store source ranges.
function _mapped_range(left::UnitRange{Int}, right::UnitRange{Int})
    min(first(left), first(right)):max(last(left), last(right))
end

function _normalized_pairs(value::AbstractString, casefold::Bool)
    result = Tuple{Char,UnitRange{Int}}[]
    source_index = 1
    for cluster in Unicode.graphemes(String(value))
        cluster_length = length(char_vector(cluster))
        source_range = source_index:(source_index + cluster_length - 1)
        normalized = Unicode.normalize(String(cluster), :NFKC)
        casefold && (normalized = Unicode.normalize(normalized; compat=true, casefold=true))
        for normalized_character in char_vector(normalized)
            push!(result, (normalized_character, source_range))
        end
        source_index += cluster_length
    end
    result
end

"""Normalize text and retain a monotonic map from normalized chars to source chars."""
function normalize_with_map(value::AbstractString; casefold=true, join_hyphenated_linebreaks=true)
    pairs = _normalized_pairs(value, Bool(casefold))
    if join_hyphenated_linebreaks
        # Remove only a word-ending hyphen followed by a line break and another
        # letter; ordinary hyphens such as "well-known" remain searchable.
        index = 2
        while index <= length(pairs)
            if pairs[index][1] == '-' && isletter(pairs[index - 1][1])
                next_index = index + 1
                while next_index <= length(pairs) && pairs[next_index][1] in (' ', '\t')
                    next_index += 1
                end
                if next_index <= length(pairs) && pairs[next_index][1] == '\n'
                    next_index += 1
                    while next_index <= length(pairs) && pairs[next_index][1] in (' ', '\t')
                        next_index += 1
                    end
                    if next_index <= length(pairs) && isletter(pairs[next_index][1])
                        deleteat!(pairs, index:next_index - 1)
                        continue
                    end
                end
            end
            index += 1
        end
    end

    collapsed = Tuple{Char,UnitRange{Int}}[]
    index = 1
    while index <= length(pairs)
        if isspace(pairs[index][1])
            # Collapse a whitespace run to one searchable space while retaining
            # the full source range covered by that run.
            last_index = index
            while last_index < length(pairs) && isspace(pairs[last_index + 1][1])
                last_index += 1
            end
            source_range = pairs[index][2]
            for source_index in index + 1:last_index
                source_range = _mapped_range(source_range, pairs[source_index][2])
            end
            push!(collapsed, (' ', source_range))
            index = last_index + 1
        else
            push!(collapsed, pairs[index])
            index += 1
        end
    end

    first_index = findfirst(pair -> !isspace(pair[1]), collapsed)
    first_index === nothing && return (text="", mapping=UnitRange{Int}[])
    last_index = findlast(pair -> !isspace(pair[1]), collapsed)
    trimmed = collapsed[first_index:last_index]
    (text=String([pair[1] for pair in trimmed]), mapping=UnitRange{Int}[pair[2] for pair in trimmed])
end

"""Normalize one searchable text value using the manifest's canonical rules."""
function normalize_text(value::AbstractString; casefold=true, join_hyphenated_linebreaks=true)
    normalize_with_map(value; casefold=casefold, join_hyphenated_linebreaks=join_hyphenated_linebreaks).text
end

normalize_word(value::AbstractString) = normalize_text(value; join_hyphenated_linebreaks=false)

function normalization_dict()
    copy(NORMALIZATION_DESCRIPTION)
end

function char_vector(text::AbstractString)
    collect(String(text))
end

function text_from_chars(chars::AbstractVector{Char}, start::Int, stop::Int)
    start >= stop && return ""
    String(chars[start:stop-1])
end

function find_char_occurrences(haystack::AbstractString, needle::AbstractString)
    h = char_vector(haystack)
    n = char_vector(needle)
    isempty(n) && return UnitRange{Int}[]
    length(n) > length(h) && return UnitRange{Int}[]
    result = UnitRange{Int}[]
    for i in 1:(length(h) - length(n) + 1)
        h[i:i + length(n) - 1] == n && push!(result, i:(i + length(n)))
    end
    result
end
