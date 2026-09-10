function safe_unpack_target(path::AbstractString, force::Bool)
    target = abspath(String(path))
    if ispath(target)
        isdir(target) || probe_error(EXIT_INPUT, "unpack", target, "output path is not a directory", recovery="choose a directory path")
        !isempty(readdir(target)) && !force && probe_error(EXIT_INPUT, "unpack", target, "asset output already exists", recovery="choose a new directory or pass --force")
    else
        mkpath(target)
    end
    target
end

function unpack_pdf(source_path::AbstractString; what=["images"], output, force=false)
    source = ensure_pdf_path(source_path; action="unpack")
    target = safe_unpack_target(output, force)
    requested = Set(lowercase.(String.(what)))
    manifest = Dict{String,Any}(
        "schema_version" => ARTIFACT_SCHEMA_VERSION,
        "source" => Dict{String,Any}("path" => source, "sha256" => sha256_file(source)),
        "requested" => sort!(collect(requested)),
        "assets" => Any[],
        "warnings" => Any[],
    )
    if "images" in requested
        executable_available(PDFIMAGES_BIN) || push!(manifest["warnings"], "images_unavailable: pdfimages is not installed")
        if executable_available(PDFIMAGES_BIN)
            prefix = joinpath(target, "image")
            try
                run(`$(PDFIMAGES_BIN) -png -j $(source) $(prefix)`)
            catch err
                push!(manifest["warnings"], "images_failed: $(sprint(showerror, err))")
            end
            for path in sort!(filter(isfile, readdir(target; join=true)))
                basename(path) == "unpack-manifest.json" && continue
                extension = splitext(path)[2]
                extension in (".png", ".jpg", ".jpeg", ".ppm", ".pbm", ".pgm") || continue
                push!(manifest["assets"], Dict{String,Any}(
                    "asset_id" => basename(path), "kind" => "image", "path" => basename(path),
                    "sha256" => sha256_file(path), "size_bytes" => filesize(path)))
            end
        end
    end
    for unsupported in setdiff(requested, Set(["images"]))
        push!(manifest["warnings"], "$(unsupported)_unavailable: low-level export is not provided by the Poppler adapter")
    end
    write_json(joinpath(target, "unpack-manifest.json"), manifest)
    target
end

function doctor_report(; fixtures=nothing)
    checks = Any[]
    for (name, description) in (("julia", "Julia runtime"), (PDFINFO_BIN, "PDF metadata reader"),
                                (PDFTEXT_BIN, "PDF text reader"), (PDFIMAGES_BIN, "PDF image inspector"),
                                (SQLITE_BIN, "SQLite command-line database"))
        available = name == "julia" ? true : executable_available(name)
        push!(checks, Dict{String,Any}("name" => name, "description" => description, "ok" => available,
                                       "path" => available && name != "julia" ? String(Sys.which(name)) : "julia"))
    end
    sqlite_fts5 = false
    if executable_available(SQLITE_BIN)
        database = tempname()
        try
            sqlite_script(database, "CREATE VIRTUAL TABLE probe USING fts5(text); INSERT INTO probe VALUES ('phrase search');"; action="doctor", target="SQLite")
            sqlite_fts5 = !isempty(sqlite_json(database, "SELECT rowid FROM probe WHERE probe MATCH 'phrase'"; action="doctor", target="SQLite"))
        catch
            sqlite_fts5 = false
        end
        isfile(database) && rm(database; force=true)
    end
    push!(checks, Dict{String,Any}("name" => "sqlite-fts5", "description" => "FTS5 virtual table support", "ok" => sqlite_fts5))
    if fixtures !== nothing
        fixture_path = abspath(String(fixtures))
        push!(checks, Dict{String,Any}("name" => "fixtures", "description" => "fixture directory", "ok" => isdir(fixture_path), "path" => fixture_path))
    end
    Dict{String,Any}("schema_version" => ARTIFACT_SCHEMA_VERSION, "ok" => all(Bool(dict_get(check, "ok", false)) for check in checks), "checks" => checks)
end
