const VALUE_OPTIONS = Set(["out", "name", "page", "pages", "context", "limit", "what", "fixtures", "config", "jobs"])
const BOOLEAN_OPTIONS = Set(["json", "pages", "objects", "fonts", "images", "strict", "force", "no-boxes", "version",
                            "literal", "case-sensitive", "regex", "boxes", "explain", "quiet", "verbose", "help"])

function cli_options(arguments::Vector{String})
    # Keep option parsing dependency-free and deterministic; command handlers
    # perform type/range validation once the option context is known.
    positionals = String[]
    options = Dict{Symbol,Any}()
    index = 1
    while index <= length(arguments)
        argument = arguments[index]
        if !startswith(argument, "--")
            push!(positionals, argument)
            index += 1
            continue
        end
        raw = argument[3:end]
        if raw == ""
            append!(positionals, arguments[index + 1:end])
            break
        end
        key, value = if occursin('=', raw)
            pieces = split(raw, '='; limit=2)
            pieces[1], pieces[2]
        else
            raw, nothing
        end
        key in VALUE_OPTIONS || key in BOOLEAN_OPTIONS ||
            probe_error(EXIT_USAGE, "cli", key, "unknown option", recovery="run pdftextsearch --help")
        symbol = Symbol(replace(key, '-' => '_'))
        if value === nothing && key == "pages" &&
           (index == length(arguments) || startswith(arguments[index + 1], "--"))
            value = true
        elseif value === nothing && key in VALUE_OPTIONS
            index < length(arguments) || probe_error(EXIT_USAGE, "cli", key, "option needs a value")
            index += 1
            value = arguments[index]
        elseif value === nothing
            value = true
        end
        options[symbol] = value
        index += 1
    end
    positionals, options
end

function cli_integer(options::AbstractDict, key::Symbol, default)
    value = get(options, key, default)
    value === default && return default
    try parse(Int, String(value)) catch
        probe_error(EXIT_USAGE, "cli", String(key), "expected an integer, got $(repr(value))")
    end
end

function cli_page_range(options::AbstractDict)
    value = get(options, :pages, nothing)
    value === nothing && return nothing
    text = String(value)
    if occursin(':', text)
        pieces = split(text, ':'; limit=2)
        length(pieces) == 2 || probe_error(EXIT_USAGE, "cli", "--pages", "expected START:END")
        first_page = try parse(Int, pieces[1]) catch; probe_error(EXIT_USAGE, "cli", "--pages", "invalid page range") end
        last_page = try parse(Int, pieces[2]) catch; probe_error(EXIT_USAGE, "cli", "--pages", "invalid page range") end
        first_page <= last_page || probe_error(EXIT_USAGE, "cli", "--pages", "range start is after range end")
        return first_page:last_page
    end
    number = try parse(Int, text) catch; probe_error(EXIT_USAGE, "cli", "--pages", "expected START:END") end
    number:number
end

function print_help(io::IO=stdout)
    println(io, "pdftextsearch $(package_version()) - inspect, dismantle, and search PDF files")
    println(io)
    println(io, "Usage: pdftextsearch <command> [options]")
    println(io)
    println(io, "Commands:")
    println(io, "  inspect <file.pdf> [--json] [--pages] [--objects]   Report metadata and health")
    println(io, "  extract <file.pdf> --out <dir> [--pages A:B]       Write deterministic page artifacts")
    println(io, "  index <dir> [--force]                              Build a SQLite/FTS5 index")
    println(io, "  search <dir> <query> [--json] [--page N]            Find evidence-backed matches")
    println(io, "  status <dir> [--json]                               Explain freshness and index health")
    println(io, "  unpack <file.pdf> --out <dir> [--what images,...]   Export selected assets")
    println(io, "  doctor [--fixtures <dir>]                           Diagnose the local setup")
    println(io)
    println(io, "Examples:")
    println(io, "  pdftextsearch inspect annual-report.pdf --json")
    println(io, "  pdftextsearch extract annual-report.pdf --out derived/report")
    println(io, "  pdftextsearch index derived/report")
    println(io, "  pdftextsearch search derived/report \"supply chain resilience\" --context 80")
    println(io)
    println(io, "Machine-readable output is written to stdout; diagnostics belong on stderr.")
end

function human_inspect(report::AbstractDict)
    source = dict_get(report, "source", Dict{String,Any}())
    pdf = dict_get(report, "pdf", Dict{String,Any}())
    health = dict_get(report, "health", Dict{String,Any}())
    println("$(basename(String(dict_get(source, "path", ""))))")
    println("  size: $(dict_get(source, "size_bytes", 0)) bytes")
    println("  sha256: $(dict_get(source, "sha256", ""))")
    println("  PDF $(dict_get(pdf, "version", "unknown")), $(dict_get(pdf, "pages", 0)) pages, encrypted=$(dict_get(pdf, "encrypted", false))")
    println("  text-native pages: $(dict_get(health, "text_native_pages", 0)); image-only pages: $(dict_get(health, "image_only_pages", 0))")
    warnings = dict_get(report, "warnings", Any[])
    isempty(warnings) || println("  warnings: ", join(String.(warnings), "; "))
end

function human_search(hits, elapsed_ms, directory)
    pages = Set{Int}()
    for item in hits
        page = Int(item["page"])
        push!(pages, page)
        println("$(item["document"]):$page")
        println("  ", item["snippet"])
        println()
    end
    println("$(length(hits)) matches in $(length(pages)) pages | $(round(elapsed_ms; digits=2)) ms | index: $(joinpath(directory, "index.sqlite"))")
end

function dispatch_cli(command::String, positional::Vector{String}, options::Dict{Symbol,Any})
    # Dispatch is deliberately thin: business logic remains callable from Julia
    # and the CLI only translates arguments, output formats, and exit codes.
    if command == "inspect"
        length(positional) == 1 || probe_error(EXIT_USAGE, "inspect", "", "expected exactly one PDF path", recovery="run pdftextsearch inspect --help")
        report = inspect_pdf(positional[1]; include_pages=get(options, :pages, false), include_objects=get(options, :objects, false),
                             include_fonts=get(options, :fonts, false), include_images=get(options, :images, false), strict=get(options, :strict, false))
        get(options, :json, false) ? println(json_string(report)) : human_inspect(report)
        return EXIT_SUCCESS
    elseif command == "extract"
        length(positional) == 1 || probe_error(EXIT_USAGE, "extract", "", "expected one PDF path")
        haskey(options, :out) || probe_error(EXIT_USAGE, "extract", "", "--out is required", recovery="choose a derived output directory")
        selected = cli_page_range(options)
        plan = ExtractionPlan(output=String(options[:out]), include_boxes=!get(options, :no_boxes, false),
                              pages=selected, strict=get(options, :strict, false), force=get(options, :force, false))
        directory = extract_pdf(positional[1], plan)
        if get(options, :json, false)
            println(json_string(read_json(joinpath(directory, "manifest.json"))))
        else
            println("extracted $(directory)")
            println("  next: pdftextsearch index $(directory)")
        end
        return EXIT_SUCCESS
    elseif command == "index"
        length(positional) == 1 || probe_error(EXIT_USAGE, "index", "", "expected one derived directory")
        database = index_directory(positional[1]; name=String(get(options, :name, "")), force=get(options, :force, false))
        get(options, :json, false) ? println(json_string(index_status(positional[1]))) : println("index ready: $(database)")
        return EXIT_SUCCESS
    elseif command == "search"
        length(positional) == 2 || probe_error(EXIT_USAGE, "search", "", "expected a derived directory and query")
        page = haskey(options, :page) ? cli_integer(options, :page, 0) : nothing
        page_range = page === nothing ? cli_page_range(options) : nothing
        haskey(options, :page) && page < 1 && probe_error(EXIT_USAGE, "search", "--page", "page must be positive")
        started = time()
        hits = search(positional[1], positional[2]; page=page, page_range=page_range,
                      limit=cli_integer(options, :limit, 20), context=cli_integer(options, :context, 80),
                      literal=get(options, :literal, false), case_sensitive=get(options, :case_sensitive, false),
                      regex=get(options, :regex, false), boxes=get(options, :boxes, false), explain=get(options, :explain, false))
        elapsed_ms = (time() - started) * 1000
        get(options, :json, false) ? println(json_string(hits)) : human_search(hits, elapsed_ms, abspath(positional[1]))
        return EXIT_SUCCESS
    elseif command == "status"
        length(positional) == 1 || probe_error(EXIT_USAGE, "status", "", "expected one derived directory")
        report = status(positional[1])
        get(options, :json, false) ? println(json_string(report)) : begin
            println("$(report["directory"])")
            println("  state: $(report["state"])")
            println("  fresh: $(report["fresh"]) ($(report["reason"]))")
            println("  index: $(report["database"])")
        end
        return EXIT_SUCCESS
    elseif command == "unpack"
        length(positional) == 1 || probe_error(EXIT_USAGE, "unpack", "", "expected one PDF path")
        haskey(options, :out) || probe_error(EXIT_USAGE, "unpack", "", "--out is required")
        what = split(String(get(options, :what, "images")), ',')
        target = unpack_pdf(positional[1]; what=what, output=String(options[:out]), force=get(options, :force, false))
        println("assets written: $(target)")
        return EXIT_SUCCESS
    elseif command == "doctor"
        report = doctor_report(; fixtures=get(options, :fixtures, nothing))
        get(options, :json, false) ? println(json_string(report)) : for check in report["checks"]
            println(Bool(check["ok"]) ? "ok   " : "FAIL ", check["name"], " - ", check["description"])
        end
        return Bool(report["ok"]) ? EXIT_SUCCESS : EXIT_INPUT
    end
    probe_error(EXIT_USAGE, "cli", command, "unknown command", recovery="run pdftextsearch --help")
end

function main(arguments=ARGS)
    # Every expected library error becomes a stable exit code; unexpected errors
    # remain visible on stderr without contaminating machine-readable stdout.
    try
        raw = String.(arguments)
        if isempty(raw) || "--help" in raw || "-h" in raw
            print_help()
            return isempty(raw) ? EXIT_USAGE : EXIT_SUCCESS
        end
        if raw == ["--version"]
            println(package_version())
            return EXIT_SUCCESS
        end
        command = raw[1]
        positional, options = cli_options(raw[2:end])
        dispatch_cli(command, positional, options)
    catch err
        if err isa PdfTextSearchError
            println(stderr, "pdftextsearch: ", sprint(showerror, err))
            return err.code
        end
        println(stderr, "pdftextsearch: unexpected internal error: ", sprint(showerror, err))
        return EXIT_INTERNAL
    end
end
