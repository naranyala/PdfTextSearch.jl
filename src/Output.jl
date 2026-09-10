"""Small deterministic JSON writer/parser kept dependency-free for the CLI contract."""

function json_escape(value::AbstractString)
    io = IOBuffer()
    for c in String(value)
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c == '\b'
            print(io, "\\b")
        elseif c == '\f'
            print(io, "\\f")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        elseif c == '\t'
            print(io, "\\t")
        elseif Int(c) < 0x20
            print(io, "\\u", lpad(string(Int(c), base=16), 4, '0'))
        else
            print(io, c)
        end
    end
    String(take!(io))
end

function json_value(value)
    value === nothing && return "null"
    value === true && return "true"
    value === false && return "false"
    value isa AbstractString && return "\"$(json_escape(value))\""
    value isa Symbol && return json_value(String(value))
    value isa Integer && return string(value)
    value isa AbstractFloat && return isfinite(value) ? string(value) : "null"
    value isa AbstractRange && return json_value(collect(value))
    value isa AbstractVector && return "[" * join(json_value.(value), ",") * "]"
    if value isa AbstractDict
        keys_sorted = sort!(String[string(k) for k in keys(value)])
        pairs = String[]
        for key in keys_sorted
            original = haskey(value, key) ? key : findfirst(k -> String(k) == key, keys(value))
            item = original isa Int ? value[collect(keys(value))[original]] : value[original]
            push!(pairs, json_value(key) * ":" * json_value(item))
        end
        return "{" * join(pairs, ",") * "}"
    end
    value isa Tuple && return json_value(collect(value))
    probe_error(EXIT_INTERNAL, "serialize", "", "unsupported JSON value $(typeof(value))")
end

json_string(value) = json_value(value)

function write_json(path::AbstractString, value)
    open(path, "w") do io
        write(io, json_string(value))
        write(io, '\n')
    end
    path
end

function write_jsonl(path::AbstractString, values)
    open(path, "w") do io
        for value in values
            write(io, json_string(value))
            write(io, '\n')
        end
    end
    path
end

mutable struct JSONParser
    chars::Vector{Char}
    position::Int
end

JSONParser(text::AbstractString) = JSONParser(collect(String(text)), 1)

function json_skip_space!(parser::JSONParser)
    while parser.position <= length(parser.chars) && parser.chars[parser.position] in (' ', '\n', '\r', '\t')
        parser.position += 1
    end
end

function json_expect!(parser::JSONParser, expected::Char)
    json_skip_space!(parser)
    parser.position <= length(parser.chars) && parser.chars[parser.position] == expected ||
        throw(ArgumentError("expected '$expected' in JSON"))
    parser.position += 1
end

function json_string_value!(parser::JSONParser)
    json_expect!(parser, '"')
    io = IOBuffer()
    while parser.position <= length(parser.chars)
        c = parser.chars[parser.position]
        parser.position += 1
        c == '"' && return String(take!(io))
        if c != '\\'
            write(io, c)
            continue
        end
        parser.position > length(parser.chars) && throw(ArgumentError("unterminated JSON escape"))
        escaped = parser.chars[parser.position]
        parser.position += 1
        if escaped == '"' || escaped == '\\' || escaped == '/'
            write(io, escaped)
        elseif escaped == 'b'
            write(io, '\b')
        elseif escaped == 'f'
            write(io, '\f')
        elseif escaped == 'n'
            write(io, '\n')
        elseif escaped == 'r'
            write(io, '\r')
        elseif escaped == 't'
            write(io, '\t')
        elseif escaped == 'u'
            parser.position + 3 <= length(parser.chars) || throw(ArgumentError("short unicode escape"))
            digits = String(parser.chars[parser.position:parser.position + 3])
            all(c -> c in ['0':'9'; 'a':'f'; 'A':'F'], digits) || throw(ArgumentError("invalid unicode escape"))
            write(io, Char(parse(Int, digits; base=16)))
            parser.position += 4
        else
            throw(ArgumentError("invalid JSON escape"))
        end
    end
    throw(ArgumentError("unterminated JSON string"))
end

function json_number!(parser::JSONParser)
    start = parser.position
    while parser.position <= length(parser.chars) &&
          (parser.chars[parser.position] in ('-', '+', '.', 'e', 'E') || isdigit(parser.chars[parser.position]))
        parser.position += 1
    end
    raw = String(parser.chars[start:parser.position - 1])
    occursin(r"[.eE]", raw) ? parse(Float64, raw) : parse(Int, raw)
end

function json_value!(parser::JSONParser)
    json_skip_space!(parser)
    parser.position <= length(parser.chars) || throw(ArgumentError("unexpected end of JSON"))
    c = parser.chars[parser.position]
    c == '"' && return json_string_value!(parser)
    if c == '{'
        parser.position += 1
        result = Dict{String,Any}()
        json_skip_space!(parser)
        if parser.position <= length(parser.chars) && parser.chars[parser.position] == '}'
            parser.position += 1
            return result
        end
        while true
            key = json_string_value!(parser)
            json_expect!(parser, ':')
            result[key] = json_value!(parser)
            json_skip_space!(parser)
            parser.position <= length(parser.chars) || throw(ArgumentError("unterminated JSON object"))
            separator = parser.chars[parser.position]
            parser.position += 1
            separator == '}' && return result
            separator == ',' || throw(ArgumentError("expected ',' in JSON object"))
        end
    elseif c == '['
        parser.position += 1
        result = Any[]
        json_skip_space!(parser)
        if parser.position <= length(parser.chars) && parser.chars[parser.position] == ']'
            parser.position += 1
            return result
        end
        while true
            push!(result, json_value!(parser))
            json_skip_space!(parser)
            parser.position <= length(parser.chars) || throw(ArgumentError("unterminated JSON array"))
            separator = parser.chars[parser.position]
            parser.position += 1
            separator == ']' && return result
            separator == ',' || throw(ArgumentError("expected ',' in JSON array"))
        end
    elseif startswith(String(parser.chars[parser.position:end]), "true")
        parser.position += 4
        return true
    elseif startswith(String(parser.chars[parser.position:end]), "false")
        parser.position += 5
        return false
    elseif startswith(String(parser.chars[parser.position:end]), "null")
        parser.position += 4
        return nothing
    else
        return json_number!(parser)
    end
end

function parse_json(text::AbstractString)
    parser = JSONParser(text)
    result = json_value!(parser)
    json_skip_space!(parser)
    parser.position <= length(parser.chars) && throw(ArgumentError("trailing data after JSON value"))
    result
end

read_json(path::AbstractString) = parse_json(read(path, String))

function read_jsonl(path::AbstractString)
    result = Any[]
    for line in eachline(path)
        isempty(strip(line)) || push!(result, parse_json(line))
    end
    result
end

dict_get(dict::AbstractDict, key::AbstractString, default=nothing) = haskey(dict, key) ? dict[key] : default
