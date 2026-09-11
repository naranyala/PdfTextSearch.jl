const API_VERSION = v"1.0.0"
const PACKAGE_NAME = "PdfTextSearch"
const FALLBACK_PACKAGE_VERSION = v"0.1.0"

# Prefer package metadata when loaded normally, but retain a source-checkout
# fallback because the CLI and tests also include the module directly.
function package_version()
    loaded_version = try Base.pkgversion(@__MODULE__) catch; nothing end
    loaded_version !== nothing && return loaded_version
    project = joinpath(dirname(@__DIR__), "Project.toml")
    if isfile(project)
        match_result = match(r"(?m)^version\s*=\s*\"([^\"]+)\"", read(project, String))
        match_result !== nothing && return VersionNumber(match_result.captures[1])
    end
    FALLBACK_PACKAGE_VERSION
end

const PACKAGE_VERSION = package_version()

"""Serialize a public result or error envelope as deterministic JSON."""
serialize_result(value) = json_string(value)

const ERROR_CODE_NAMES = Dict(
    0 => "Success",
    EXIT_USAGE => "UsageError",
    EXIT_INPUT => "InputError",
    EXIT_PARSE => "ParseError",
    EXIT_INDEX => "IndexError",
    EXIT_INTERNAL => "InternalError",
)

error_code_name(code::Integer) = get(ERROR_CODE_NAMES, Int(code), "UnknownError")

function error_dict(error::PdfTextSearchError)
    Dict{String,Any}(
        "schema_version" => 1,
        "code" => error_code_name(error.code),
        "exit_code" => error.code,
        "action" => error.action,
        "target" => error.target,
        "message" => error.message,
        "recovery" => error.recovery,
    )
end

function capabilities()
    Dict{String,Any}(
        "name" => PACKAGE_NAME,
        "version" => string(PACKAGE_VERSION),
        "api_version" => string(API_VERSION),
        "artifact_schema_version" => ARTIFACT_SCHEMA_VERSION,
        "index_schema_version" => INDEX_SCHEMA_VERSION,
        "parser" => Dict{String,Any}("name" => PARSER_NAME, "version" => PARSER_VERSION),
        "index_backend" => "sqlite-cli-fts5",
        "tools" => Dict{String,Any}(name => Dict{String,Any}(
            "available" => tool_available(name),
            "path" => something(tool_path(name), ""),
        ) for name in (PDFINFO_BIN, PDFTEXT_BIN, PDFIMAGES_BIN, SQLITE_BIN)),
        "providers" => provider_capabilities(),
    )
end

function artifact_cache_key(source::AbstractString; include_boxes=true, pages=nothing,
                            strict=false, include_text_files=true)
    # The key covers every option that changes derived bytes. Source paths are
    # intentionally excluded so moving a PDF does not force reparsing.
    source = ensure_pdf_path(source; action="cache-key")
    selection = pages === nothing ? nothing : "$(first(pages)):$(last(pages))"
    configuration = Dict{String,Any}(
        "source_sha256" => sha256_file(source),
        "parser" => Dict{String,Any}("name" => PARSER_NAME, "version" => PARSER_VERSION),
        "normalization" => normalization_dict(),
        "artifact_schema_version" => ARTIFACT_SCHEMA_VERSION,
        "include_boxes" => Bool(include_boxes),
        "pages" => selection,
        "strict" => Bool(strict),
        "include_text_files" => Bool(include_text_files),
    )
    bytes2hex(SHA.sha256(codeunits(json_string(configuration))))
end

function cache_status(directory::AbstractString, source::AbstractString; include_boxes=true, pages=nothing,
                      strict=false, include_text_files=true)
    directory = abspath(String(directory))
    lock_path = directory * ".lock"
    expected_key = artifact_cache_key(source; include_boxes=include_boxes, pages=pages,
                                      strict=strict, include_text_files=include_text_files)
    manifest_path = joinpath(directory, "manifest.json")
    if !isfile(manifest_path)
        return Dict{String,Any}("fresh" => false, "reason" => "manifest.json is missing",
                                "directory" => directory, "cache_key" => expected_key,
                                "locked" => ispath(lock_path), "lock_path" => lock_path)
    end
    manifest = try read_json(manifest_path) catch
        return Dict{String,Any}("fresh" => false, "reason" => "manifest.json is invalid",
                                "directory" => directory, "cache_key" => expected_key,
                                "locked" => ispath(lock_path), "lock_path" => lock_path)
    end
    actual_key = String(dict_get(manifest, "cache_key", ""))
    required = all(isfile(joinpath(directory, filename)) for filename in ("pages.jsonl", "spans.jsonl", "build-report.json"))
    state = String(dict_get(manifest, "state", "unknown"))
    # A manifest can exist while a build is incomplete; required artifacts,
    # matching configuration, and an allowed lifecycle state are all needed.
    fresh = required && actual_key == expected_key && state in ("extracted", "fresh")
    reason = fresh ? "source and extraction configuration match" : !required ? "required artifacts are missing" : actual_key != expected_key ? "source or extraction configuration changed" : "build state is $state"
    Dict{String,Any}("fresh" => fresh, "reason" => reason, "directory" => directory,
                     "cache_key" => expected_key, "actual_cache_key" => actual_key,
                     "state" => state, "locked" => ispath(lock_path), "lock_path" => lock_path)
end
