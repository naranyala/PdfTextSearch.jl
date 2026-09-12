using Dates
using Printf

function atomic_json_write(path::AbstractString, value)
    # Write beside the destination and rename only after serialization succeeds
    # so readers never observe a half-written manifest.
    temporary = path * ".tmp"
    write_json(temporary, value)
    mv(temporary, path; force=true)
    path
end

function selected_page_dict(pages)
    pages === nothing && return nothing
    isempty(pages) ? "" : "$(first(pages)):$(last(pages))"
end

function extraction_manifest(source::AbstractString, info::Dict{String,String}, pages, selected;
                             include_boxes=true, strict=false, include_text_files=true)
    cache_key = artifact_cache_key(source; include_boxes=include_boxes, pages=selected,
                                   strict=strict, include_text_files=include_text_files)
    Dict{String,Any}(
        "schema_version" => ARTIFACT_SCHEMA_VERSION,
        "cache_key" => cache_key,
        "document_id" => "sha256:" * sha256_file(source),
        "source" => Dict{String,Any}(
            "path" => source,
            "sha256" => sha256_file(source),
            "size_bytes" => filesize(source),
        ),
        "parser" => Dict{String,Any}("name" => PARSER_NAME, "version" => PARSER_VERSION,
                                     "backend" => "Poppler command-line adapter"),
        "normalization" => normalization_dict(),
        "extraction" => Dict{String,Any}(
            "include_boxes" => Bool(include_boxes),
            "strict" => Bool(strict),
            "include_text_files" => Bool(include_text_files),
        ),
        "index" => Dict{String,Any}("backend" => "sqlite-fts5", "schema_version" => INDEX_SCHEMA_VERSION,
                                    "state" => "missing"),
        "page_count" => pages,
        "selected_pages" => selected_page_dict(selected),
        "state" => "building",
        "created_at" => string(Dates.now()),
        "warnings" => Any[],
    )
end

function ensure_output_target(path::AbstractString, force::Bool)
    if ispath(path)
        isdir(path) || probe_error(EXIT_INPUT, "extract", path, "output path is not a directory", recovery="choose a directory path")
        if !force && !isempty(readdir(path))
            probe_error(EXIT_INPUT, "extract", path, "derived output already exists", recovery="choose a new directory or pass --force")
        end
    else
        mkpath(path)
    end
end

cache_lock_path(directory::AbstractString) = abspath(String(directory)) * ".lock"

function acquire_cache_lock(directory::AbstractString)
    # `mkdir` is atomic for a directory: competing builders either own the lock
    # or receive a typed conflict before touching the existing artifact.
    lock_path = cache_lock_path(directory)
    mkpath(dirname(lock_path))
    try
        mkdir(lock_path)
    catch err
        ispath(lock_path) && probe_error(EXIT_INPUT, "extract", directory,
            "another extraction is already building this artifact",
            recovery="wait for the existing build or remove the lock after confirming its owner is gone")
        rethrow(err)
    end
    try
        write_json(joinpath(lock_path, "owner.json"), Dict{String,Any}(
            "pid" => getpid(),
            "started_at" => string(Dates.now()),
            "directory" => abspath(String(directory)),
        ))
    catch err
        rm(lock_path; recursive=true, force=true)
        rethrow(err)
    end
    lock_path
end

function release_cache_lock(lock_path::AbstractString)
    isempty(String(lock_path)) || rm(String(lock_path); recursive=true, force=true)
    nothing
end

function write_page_artifacts(directory::AbstractString, page_records::Vector{PageRecord}; include_text_files=true)
    write_jsonl(joinpath(directory, "pages.jsonl"), (page_dict(page; include_spans=false) for page in page_records))
    span_records = Any[]
    for page in page_records
        for span in page.spans
            record = span_dict(span)
            record["document_id"] = page.document_id
            push!(span_records, record)
        end
    end
    write_jsonl(joinpath(directory, "spans.jsonl"), span_records)
    if include_text_files
        text_dir = joinpath(directory, "text")
        mkpath(text_dir)
        for page in page_records
            filename = joinpath(text_dir, @sprintf("page-%06d.txt", page.page_number))
            open(filename, "w") do io
                write(io, page.text)
                write(io, '\n')
            end
        end
    end
end

function extract_pdf(source_path::AbstractString, plan::ExtractionPlan)
    source = ensure_pdf_path(source_path; action="extract")
    output = abspath(plan.output)
    if plan.reuse && isdir(output)
        cached = cache_status(output, source; include_boxes=plan.include_boxes, pages=plan.pages,
                              strict=plan.strict, include_text_files=plan.include_text_files)
        cached["fresh"] === true && return output
    end
    # Check before locking for the common no-op case, then recheck after locking
    # because another process may have completed while this caller raced it.
    lock_path = acquire_cache_lock(output)
    temporary = ""
    started = time()
    manifest = nothing
    try
        if plan.reuse && isdir(output)
            cached = cache_status(output, source; include_boxes=plan.include_boxes, pages=plan.pages,
                                  strict=plan.strict, include_text_files=plan.include_text_files)
            cached["fresh"] === true && return output
        end
        ensure_output_target(output, plan.force)
        parent = dirname(output)
        temporary = mktempdir(parent)
        pages, info, extraction_warnings, page_count = extract_pages(source; pages=plan.pages,
            include_boxes=plan.include_boxes, strict=plan.strict)
        manifest = extraction_manifest(source, info, page_count, plan.pages;
                                      include_boxes=plan.include_boxes, strict=plan.strict,
                                      include_text_files=plan.include_text_files)
        manifest["warnings"] = extraction_warnings
        atomic_json_write(joinpath(temporary, "manifest.json"), manifest)
        inspect_report = inspect_pdf(source; include_pages=true, include_objects=false, strict=plan.strict)
        write_json(joinpath(temporary, "inspect.json"), inspect_report)
        write_page_artifacts(temporary, pages; include_text_files=plan.include_text_files)
        mkpath(joinpath(temporary, "assets"))
        build_report = Dict{String,Any}(
            "schema_version" => ARTIFACT_SCHEMA_VERSION,
            "state" => "extracted",
            "started_at" => string(Dates.now()),
            "duration_ms" => round((time() - started) * 1000; digits=3),
            "pages_seen" => page_count,
            "pages_written" => length(pages),
            "spans_written" => sum(length(page.spans) for page in pages),
            "warnings" => extraction_warnings,
        )
        write_json(joinpath(temporary, "build-report.json"), build_report)
        manifest["state"] = "extracted"
        atomic_json_write(joinpath(temporary, "manifest.json"), manifest)
        # Publish only after all files and validation have completed. A forced
        # replacement keeps the old directory as a recoverable sibling.
        if ispath(output)
            if !plan.force && !isempty(readdir(output))
                probe_error(EXIT_INPUT, "extract", output, "derived output already exists", recovery="choose a new directory or pass --force")
            end
            if plan.force && !isempty(readdir(output))
                backup = output * ".previous-" * string(round(Int, time()))
                mv(output, backup; force=false)
            else
                rm(output; recursive=true, force=true)
            end
        end
        mv(temporary, output)
        temporary = ""
        output
    catch err
        if !isempty(temporary) && isdir(temporary)
            rm(temporary; recursive=true, force=true)
        end
        if !ispath(output) || (isdir(output) && isempty(readdir(output)))
            mkpath(output)
            failed_report = Dict{String,Any}(
                "schema_version" => ARTIFACT_SCHEMA_VERSION,
                "state" => "failed",
                "duration_ms" => round((time() - started) * 1000; digits=3),
                "error" => sprint(showerror, err),
                "recovery" => "rerun extract after addressing the error; this directory is not fresh",
            )
            write_json(joinpath(output, "build-report.json"), failed_report)
        end
        rethrow()
    finally
        release_cache_lock(lock_path)
    end
end
