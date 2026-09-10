const SQLITE_BIN = "sqlite3"

function sql_quote(value)
    "'" * replace(string(value), "'" => "''") * "'"
end

sql_nullable_number(value) = value === nothing ? "NULL" : string(parse_float_or(value, 0.0))

function ensure_sqlite(target::AbstractString)
    executable_available(SQLITE_BIN) || probe_error(EXIT_INTERNAL, "index", target,
        "required helper 'sqlite3' is not installed", recovery="install SQLite with FTS5 support and retry")
end

function sqlite_script(database::AbstractString, script::AbstractString; action="index", target=database)
    ensure_sqlite(target)
    process = try
        open(`$(SQLITE_BIN) -batch $(database)`, "w")
    catch err
        probe_error(EXIT_INDEX, action, target, "could not open SQLite database: $(sprint(showerror, err))")
    end
    try
        write(process, script)
        close(process)
        wait(process)
    catch err
        try close(process) catch end
        probe_error(EXIT_INDEX, action, target, "SQLite build failed: $(sprint(showerror, err))",
                    recovery="check SQLite/FTS5 support and remove only the partial index")
    end
    nothing
end

function sqlite_json(database::AbstractString, query::AbstractString; action="search", target=database)
    ensure_sqlite(target)
    output = try
        read(`$(SQLITE_BIN) -json $(database) $(query)`, String)
    catch err
        probe_error(EXIT_INDEX, action, target, "SQLite query failed: $(sprint(showerror, err))",
                    recovery="rebuild the derived index with pdfprobe index --force")
    end
    isempty(strip(output)) ? Any[] : parse_json(output)
end

const INDEX_SCHEMA_SQL = """
PRAGMA journal_mode = DELETE;
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS documents (
    document_id TEXT PRIMARY KEY,
    source_path TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    parser_version TEXT NOT NULL,
    config_hash TEXT NOT NULL,
    page_count INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS pages (
    document_id TEXT NOT NULL,
    page_number INTEGER NOT NULL,
    width REAL NOT NULL,
    height REAL NOT NULL,
    rotation INTEGER NOT NULL,
    text TEXT NOT NULL,
    original_text TEXT NOT NULL,
    text_hash TEXT NOT NULL,
    image_count INTEGER NOT NULL DEFAULT 0,
    annotation_count INTEGER NOT NULL DEFAULT 0,
    extraction_status TEXT NOT NULL,
    PRIMARY KEY (document_id, page_number),
    FOREIGN KEY (document_id) REFERENCES documents(document_id)
);
CREATE VIRTUAL TABLE IF NOT EXISTS fts_pages USING fts5(
    document_id UNINDEXED,
    page_number UNINDEXED,
    text,
    tokenize = 'unicode61 remove_diacritics 2'
);
CREATE TABLE IF NOT EXISTS spans (
    document_id TEXT NOT NULL,
    page_number INTEGER NOT NULL,
    span_id INTEGER NOT NULL,
    start INTEGER NOT NULL,
    stop INTEGER NOT NULL,
    text TEXT NOT NULL,
    original_text TEXT NOT NULL,
    x0 REAL,
    y0 REAL,
    x1 REAL,
    y1 REAL,
    PRIMARY KEY (document_id, page_number, span_id),
    FOREIGN KEY (document_id, page_number) REFERENCES pages(document_id, page_number)
);
CREATE TABLE IF NOT EXISTS assets (
    document_id TEXT NOT NULL,
    asset_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    path TEXT NOT NULL,
    object_ref TEXT,
    sha256 TEXT,
    PRIMARY KEY (document_id, asset_id)
);
CREATE TABLE IF NOT EXISTS build_events (
    document_id TEXT NOT NULL,
    phase TEXT NOT NULL,
    started_at TEXT,
    duration_ms REAL,
    counters_json TEXT,
    warnings_json TEXT
);
"""

function manifest_source(manifest::AbstractDict)
    source = dict_get(manifest, "source", Dict{String,Any}())
    source isa AbstractDict ? source : Dict{String,Any}()
end

function index_directory(directory::AbstractString; name="", force=false)
    directory = abspath(String(directory))
    isdir(directory) || probe_error(EXIT_INPUT, "index", directory, "derived directory does not exist", recovery="run extract first")
    manifest_path = joinpath(directory, "manifest.json")
    isfile(manifest_path) || probe_error(EXIT_INDEX, "index", directory, "manifest.json is missing", recovery="run extract first")
    manifest = try read_json(manifest_path) catch err
        probe_error(EXIT_INDEX, "index", directory, "manifest.json is invalid: $(sprint(showerror, err))", recovery="rerun extract")
    end
    pages_path = joinpath(directory, "pages.jsonl")
    isfile(pages_path) || probe_error(EXIT_INDEX, "index", directory, "pages.jsonl is missing", recovery="rerun extract")
    database = joinpath(directory, "index.sqlite")
    current_status = isfile(database) ? index_status(directory) : Dict{String,Any}("fresh" => false)
    current_status["fresh"] === true && !force && return database
    isfile(database) && !force && probe_error(EXIT_INDEX, "index", directory, "existing index is stale or failed", recovery="pass --force to rebuild it")

    pages = read_jsonl(pages_path)
    spans_path = joinpath(directory, "spans.jsonl")
    spans = isfile(spans_path) ? read_jsonl(spans_path) : Any[]
    source = manifest_source(manifest)
    source_hash = String(dict_get(source, "sha256", ""))
    document_id = String(dict_get(manifest, "document_id", "sha256:" * source_hash))
    source_path = String(dict_get(source, "path", ""))
    config_hash = sha256_hex(json_string(dict_get(manifest, "normalization", Dict{String,Any}())))
    temporary = joinpath(directory, "index.sqlite.partial")
    isfile(temporary) && rm(temporary; force=true)
    started = time()
    try
        script = IOBuffer()
        write(script, INDEX_SCHEMA_SQL)
        write(script, "BEGIN IMMEDIATE;\n")
        write(script, "INSERT OR REPLACE INTO meta(key,value) VALUES ('schema_version',$(sql_quote(INDEX_SCHEMA_VERSION)));\n")
        write(script, "INSERT OR REPLACE INTO meta(key,value) VALUES ('source_sha256',$(sql_quote(source_hash)));\n")
        write(script, "INSERT OR REPLACE INTO meta(key,value) VALUES ('document_id',$(sql_quote(document_id)));\n")
        write(script, "INSERT OR REPLACE INTO meta(key,value) VALUES ('parser_version',$(sql_quote(PARSER_VERSION)));\n")
        write(script, "INSERT OR REPLACE INTO meta(key,value) VALUES ('normalization_version',$(sql_quote(NORMALIZATION_VERSION)));\n")
        write(script, "INSERT OR REPLACE INTO meta(key,value) VALUES ('name',$(sql_quote(name)));\n")
        write(script, "INSERT OR REPLACE INTO documents(document_id,source_path,sha256,parser_version,config_hash,page_count) VALUES ($(sql_quote(document_id)),$(sql_quote(source_path)),$(sql_quote(source_hash)),$(sql_quote(PARSER_VERSION)),$(sql_quote(config_hash)),$(length(pages)));\n")
        for page in pages
            page_document = String(dict_get(page, "document_id", document_id))
            page_number = parse_int_or(dict_get(page, "page_number", 0), 0)
            write(script, "INSERT OR REPLACE INTO pages(document_id,page_number,width,height,rotation,text,original_text,text_hash,image_count,annotation_count,extraction_status) VALUES ($(sql_quote(page_document)),$page_number,$(parse_float_or(dict_get(page,"width",0.0),0.0)),$(parse_float_or(dict_get(page,"height",0.0),0.0)),$(parse_int_or(dict_get(page,"rotation",0),0)),$(sql_quote(dict_get(page,"text",""))),$(sql_quote(dict_get(page,"original_text",""))),$(sql_quote(dict_get(page,"text_hash",""))),$(parse_int_or(dict_get(page,"image_count",0),0)),$(parse_int_or(dict_get(page,"annotation_count",0),0)),$(sql_quote(dict_get(page,"extraction_status","unknown"))));\n")
            write(script, "INSERT INTO fts_pages(document_id,page_number,text) VALUES ($(sql_quote(page_document)),$page_number,$(sql_quote(dict_get(page,"text",""))));\n")
        end
        for span in spans
            box = dict_get(span, "bbox", nothing)
            x0 = box isa AbstractDict ? dict_get(box, "x0", nothing) : nothing
            y0 = box isa AbstractDict ? dict_get(box, "y0", nothing) : nothing
            x1 = box isa AbstractDict ? dict_get(box, "x1", nothing) : nothing
            y1 = box isa AbstractDict ? dict_get(box, "y1", nothing) : nothing
            span_document = sql_quote(dict_get(span, "document_id", document_id))
            span_page = parse_int_or(dict_get(span, "page_number", 0), 0)
            span_id = parse_int_or(dict_get(span, "span_id", 0), 0)
            span_start = parse_int_or(dict_get(span, "start", 0), 0)
            span_stop = parse_int_or(dict_get(span, "stop", 0), 0)
            span_text = sql_quote(dict_get(span, "text", ""))
            span_original = sql_quote(dict_get(span, "original_text", ""))
            write(script, "INSERT OR REPLACE INTO spans(document_id,page_number,span_id,start,stop,text,original_text,x0,y0,x1,y1) VALUES ($span_document,$span_page,$span_id,$span_start,$span_stop,$span_text,$span_original,$(sql_nullable_number(x0)),$(sql_nullable_number(y0)),$(sql_nullable_number(x1)),$(sql_nullable_number(y1)));\n")
        end
        write(script, "INSERT INTO build_events(document_id,phase,started_at,duration_ms,counters_json,warnings_json) VALUES ($(sql_quote(document_id)),'index',$(sql_quote(string(Dates.now()))),$(round((time()-started)*1000; digits=3)),$(sql_quote(json_string(Dict("pages"=>length(pages),"spans"=>length(spans))))),'[]');\n")
        write(script, "COMMIT;\n")
        sqlite_script(temporary, String(take!(script)); action="index", target=directory)
        counts = sqlite_json(temporary, "SELECT (SELECT COUNT(*) FROM pages) AS pages, (SELECT COUNT(*) FROM fts_pages) AS indexed_pages, (SELECT COUNT(*) FROM spans) AS spans"; action="index", target=directory)
        isempty(counts) && probe_error(EXIT_INDEX, "index", directory, "SQLite validation returned no counters")
        count_row = counts[1]
        Int(count_row["pages"]) == length(pages) || probe_error(EXIT_INDEX, "index", directory, "SQLite page count validation failed")
        mv(temporary, database; force=true)
        manifest["state"] = "fresh"
        index_meta = dict_get(manifest, "index", Dict{String,Any}())
        index_meta isa AbstractDict || (index_meta = Dict{String,Any}())
        index_meta["backend"] = "sqlite-fts5"
        index_meta["schema_version"] = INDEX_SCHEMA_VERSION
        index_meta["state"] = "fresh"
        index_meta["database"] = "index.sqlite"
        manifest["index"] = index_meta
        manifest["indexed_at"] = string(Dates.now())
        atomic_json_write(manifest_path, manifest)
        build_report = Dict{String,Any}(
            "schema_version" => ARTIFACT_SCHEMA_VERSION,
            "state" => "fresh",
            "phase" => "index",
            "duration_ms" => round((time() - started) * 1000; digits=3),
            "pages_written" => length(pages),
            "spans_written" => length(spans),
            "warnings" => Any[],
        )
        write_json(joinpath(directory, "build-report.json"), build_report)
        database
    catch err
        isfile(temporary) && rm(temporary; force=true)
        manifest["state"] = "failed"
        index_meta = dict_get(manifest, "index", Dict{String,Any}())
        index_meta isa AbstractDict || (index_meta = Dict{String,Any}())
        index_meta["state"] = "failed"
        manifest["index"] = index_meta
        try atomic_json_write(manifest_path, manifest) catch end
        write_json(joinpath(directory, "build-report.json"), Dict{String,Any}(
            "schema_version" => ARTIFACT_SCHEMA_VERSION, "state" => "failed", "phase" => "index",
            "duration_ms" => round((time() - started) * 1000; digits=3), "error" => sprint(showerror, err),
            "recovery" => "rerun index with --force after addressing the error"))
        rethrow()
    end
end

function index_status(directory::AbstractString)
    directory = abspath(String(directory))
    manifest_path = joinpath(directory, "manifest.json")
    isfile(manifest_path) || probe_error(EXIT_INDEX, "status", directory, "manifest.json is missing", recovery="run extract first")
    manifest = read_json(manifest_path)
    database = joinpath(directory, "index.sqlite")
    source = manifest_source(manifest)
    expected_hash = String(dict_get(source, "sha256", ""))
    actual_hash = isfile(String(dict_get(source, "path", ""))) ? sha256_file(String(dict_get(source, "path", ""))) : ""
    meta = Any[]
    database_exists = isfile(database)
    database_exists && (meta = sqlite_json(database, "SELECT key,value FROM meta"; action="status", target=directory))
    meta_map = Dict{String,String}()
    for row in meta
        meta_map[String(row["key"])] = String(row["value"])
    end
    state = String(dict_get(manifest, "state", "unknown"))
    fresh = database_exists && state == "fresh" && expected_hash == actual_hash && get(meta_map, "source_sha256", "") == expected_hash
    reason = fresh ? "source and derived versions match" : !database_exists ? "index.sqlite is missing" : state != "fresh" ? "build state is $state" : expected_hash != actual_hash ? "source bytes changed" : "index metadata does not match manifest"
    Dict{String,Any}(
        "schema_version" => ARTIFACT_SCHEMA_VERSION,
        "directory" => directory,
        "source" => source,
        "state" => state,
        "fresh" => fresh,
        "reason" => reason,
        "database" => database,
        "database_exists" => database_exists,
        "parser" => dict_get(manifest, "parser", Dict{String,Any}()),
        "normalization" => dict_get(manifest, "normalization", Dict{String,Any}()),
        "index" => dict_get(manifest, "index", Dict{String,Any}()),
        "meta" => meta_map,
    )
end

status(directory::AbstractString) = index_status(directory)

function open_index(path::AbstractString)
    candidate = abspath(String(path))
    directory = isdir(candidate) ? candidate : dirname(candidate)
    database = isdir(candidate) ? joinpath(candidate, "index.sqlite") : candidate
    state = index_status(directory)
    state["fresh"] === true || probe_error(EXIT_INDEX, "search", directory, "index is not fresh ($(state["reason"]))", recovery="run pdfprobe index --force")
    IndexHandle(directory, database, read_json(joinpath(directory, "manifest.json")))
end
