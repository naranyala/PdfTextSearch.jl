# Fast safety tests: input validation, cache keys, and locks.
# Uses minimal %PDF- fixtures so Poppler/SQLite are not required.

function write_minimal_pdf(path::AbstractString, payload::AbstractString="%PDF-1.4\nhello\n")
    open(path, "w") do io
        write(io, payload)
    end
    path
end

@testset "input validation" begin
    root = mktempdir()
    good = write_minimal_pdf(joinpath(root, "good.pdf"))
    @test PdfTextSearch.ensure_pdf_path(good; action="test") == abspath(good)
    @test length(PdfTextSearch.sha256_file(good)) == 64

    missing = try
        PdfTextSearch.ensure_pdf_path(joinpath(root, "nope.pdf"))
        nothing
    catch e
        e
    end
    @test missing isa PdfTextSearch.PdfTextSearchError && missing.code == PdfTextSearch.EXIT_INPUT

    not_pdf = joinpath(root, "plain.txt")
    open(not_pdf, "w") do io
        write(io, "just text")
    end
    bad = try
        PdfTextSearch.ensure_pdf_path(not_pdf)
        nothing
    catch e
        e
    end
    @test bad isa PdfTextSearch.PdfTextSearchError && bad.code == PdfTextSearch.EXIT_INPUT
end

@testset "cache keys and status" begin
    root = mktempdir()
    source = write_minimal_pdf(joinpath(root, "doc.pdf"))
    key_default = PdfTextSearch.artifact_cache_key(source)
    @test length(key_default) == 64
    @test PdfTextSearch.artifact_cache_key(source) == key_default  # deterministic
    @test PdfTextSearch.artifact_cache_key(source; include_boxes=false) != key_default
    @test PdfTextSearch.artifact_cache_key(source; strict=true) != key_default
    @test PdfTextSearch.artifact_cache_key(source; pages=1:2) != key_default

    missing_dir = PdfTextSearch.cache_status(joinpath(root, "absent"), source)
    @test missing_dir["fresh"] === false
    @test occursin("manifest", missing_dir["reason"])

    empty_dir = joinpath(root, "empty")
    mkpath(empty_dir)
    PdfTextSearch.write_json(joinpath(empty_dir, "manifest.json"), Dict("cache_key" => "x", "state" => "extracted"))
    incomplete = PdfTextSearch.cache_status(empty_dir, source)
    @test incomplete["fresh"] === false
    @test occursin("required artifacts", incomplete["reason"])
end

@testset "cache locks" begin
    root = mktempdir()
    directory = joinpath(root, "artifacts")
    lock_path = PdfTextSearch.acquire_cache_lock(directory)
    @test isdir(lock_path)
    @test PdfTextSearch.cache_lock_path(directory) == lock_path
    # Second acquisition while locked is a typed conflict, not a crash.
    conflict = try
        PdfTextSearch.acquire_cache_lock(directory)
        nothing
    catch e
        e
    end
    @test conflict isa PdfTextSearch.PdfTextSearchError && conflict.code == PdfTextSearch.EXIT_INPUT
    PdfTextSearch.release_cache_lock(lock_path)
    @test !ispath(lock_path)
    # Releasing twice is safe; releasing empty is a no-op.
    PdfTextSearch.release_cache_lock(lock_path)
    PdfTextSearch.release_cache_lock("")
end

@testset "doctor structure" begin
    report = PdfTextSearch.doctor_report()
    @test haskey(report, "ok") && haskey(report, "checks")
    @test report["checks"] isa AbstractVector && !isempty(report["checks"])
    for check in report["checks"]
        @test haskey(check, "name") && haskey(check, "ok")
    end
    names = Set(String(c["name"]) for c in report["checks"])
    @test all(n in names for n in ("pdfinfo", "pdftotext", "sqlite-fts5"))
end
