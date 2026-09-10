using Unicode

const NORMALIZATION_DESCRIPTION = Dict{String,Any}(
    "unicode" => "NFKC",
    "casefold" => true,
    "collapse_whitespace" => true,
    "join_hyphenated_linebreaks" => true,
)

"""Normalize one searchable text value using the manifest's canonical rules."""
function normalize_text(value::AbstractString; casefold=true, join_hyphenated_linebreaks=true)
    text = Unicode.normalize(String(value), :NFKC)
    casefold && (text = Unicode.normalize(text; compat=true, casefold=true))
    if join_hyphenated_linebreaks
        text = replace(text, r"(?m)(\p{L}+)-[ \t]*\n[ \t]*(\p{L}+)" => s"\1\2")
    end
    text = replace(text, r"\s+" => " ")
    strip(text)
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
