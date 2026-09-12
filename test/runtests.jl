using Test
using Printf

include(joinpath(@__DIR__, "..", "src", "PdfTextSearch.jl"))
using .PdfTextSearch

# Fast, dependency-free unit layers run before the slower tool-boundary and
# vertical-slice sets below.
include(joinpath(@__DIR__, "unit_core.jl"))
include(joinpath(@__DIR__, "unit_query_cli.jl"))
include(joinpath(@__DIR__, "unit_safety.jl"))
include(joinpath(@__DIR__, "unit_structure.jl"))

@testset "normalization and JSON" begin
    @test PdfTextSearch.normalize_text("  Supply\u00a0chain  RESILIENCE ") == "supply chain resilience"
    @test PdfTextSearch.normalize_text("hyphen-\nbreak") == "hyphenbreak"
    value = Dict("text" => "quote \" and \\ slash", "ok" => true, "nothing" => nothing)
    @test PdfTextSearch.parse_json(PdfTextSearch.json_string(value)) == value
end

@testset "query semantics" begin
    @test PdfTextSearch.find_char_occurrences("a phrase phrase", "phrase") == [3:9, 10:16]
    spec = PdfTextSearch.parse_query("\"Supply Chain\"")
    @test spec.phrases == ["supply chain"]
    @test PdfTextSearch.query_occurrences("Supply chain resilience", spec) == [1:13]
end

@testset "public API, provenance, and tool boundary" begin
    # Keep these checks close to the public surface so API drift is caught even
    # when lower-level parser tests happen to pass.
    capabilities = PdfTextSearch.capabilities()
    @test capabilities["name"] == "PdfTextSearch"
    @test capabilities["version"] == string(PdfTextSearch.package_version())
    @test capabilities["artifact_schema_version"] == 2

    mapped = PdfTextSearch.normalize_with_map("Cafe\u0301  line-\nbreak")
    @test mapped.text == "café linebreak"
    @test first(mapped.mapping[1]) == 1
    @test first(mapped.mapping[4]) == 4

    julia = Sys.which("julia")
    if julia !== nothing
        runner = PdfTextSearch.ToolRunner(timeout=5.0)
        ok_result = PdfTextSearch.run_tool(runner, String(julia), ["--startup-file=no", "-e", "print(\"ok\")"])
        @test success(ok_result)
        @test ok_result.stdout == "ok"

        failed_result = PdfTextSearch.run_tool(runner, String(julia), ["--startup-file=no", "-e", "exit(7)"])
        @test failed_result.exit_code == 7
        @test !success(failed_result)

        timeout_result = PdfTextSearch.run_tool(PdfTextSearch.ToolRunner(timeout=0.1), String(julia),
                                                ["--startup-file=no", "-e", "sleep(2)"])
        @test timeout_result.timed_out
        @test !success(timeout_result)

        missing_tool = PdfTextSearch.run_tool(runner, "pdftextsearch-tool-that-does-not-exist", String[])
        @test missing_tool.exit_code == -1
        @test !success(missing_tool)

        # Cancellation is cooperative from the host's perspective, but the
        # runner must still terminate the child and return a structured result.
        cancelled = Ref(false)
        cancel_task = @async begin
            sleep(0.1)
            cancelled[] = true
        end
        cancelled_result = PdfTextSearch.run_tool(PdfTextSearch.ToolRunner(timeout=5.0), String(julia),
                                                  ["--startup-file=no", "-e", "sleep(2)"]; cancel=cancelled)
        wait(cancel_task)
        @test cancelled_result.cancelled
        @test !success(cancelled_result)

        cli = joinpath(@__DIR__, "..", "bin", "pdftextsearch")
        cli_runner = PdfTextSearch.ToolRunner(timeout=30.0)
        cli_help = PdfTextSearch.run_tool(cli_runner, String(julia), ["--startup-file=no", "--compile=min", cli, "--help"])
        @test success(cli_help)
        @test occursin("Usage: pdftextsearch", cli_help.stdout)

        cli_version = PdfTextSearch.run_tool(cli_runner, String(julia), ["--startup-file=no", "--compile=min", cli, "--version"])
        @test success(cli_version)
        @test strip(cli_version.stdout) == string(PdfTextSearch.package_version())

        cli_unknown = PdfTextSearch.run_tool(cli_runner, String(julia), ["--startup-file=no", "--compile=min", cli, "unknown-command"])
        @test cli_unknown.exit_code == 2
        @test occursin("pdftextsearch:", cli_unknown.stderr)
    end
end

@testset "PDF reader and inspect" begin
    @test PdfTextSearch.executable_available("pdfinfo")
    @test PdfTextSearch.executable_available("pdftotext")
end

 # The fixture is generated rather than committed as binary data, keeping the
 # test portable and making its text payload obvious to future maintainers.
function write_fixture_pdf(path)
    content = "BT /F1 16 Tf 72 720 Td (supply chain resilience) Tj ET"
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Length $(ncodeunits(content)) >>\nstream\n$(content)\nendstream",
    ]
    io = IOBuffer()
    write(io, "%PDF-1.4\n")
    offsets = Int[]
    for (number, object) in enumerate(objects)
        push!(offsets, position(io))
        write(io, "$(number) 0 obj\n$(object)\nendobj\n")
    end
    xref = position(io)
    write(io, "xref\n0 $(length(objects) + 1)\n0000000000 65535 f \n")
    for offset in offsets
        write(io, @sprintf("%010d 00000 n \n", offset))
    end
    write(io, "trailer\n<< /Size $(length(objects) + 1) /Root 1 0 R >>\nstartxref\n$(xref)\n%%EOF\n")
    open(path, "w") do output
        write(output, take!(io))
    end
end

@testset "vertical slice" begin
    # This is the contract-level workflow an embedding application is expected
    # to exercise: source PDF -> artifacts -> index -> evidence-backed search.
    root = mktempdir()
    pdf = joinpath(root, "fixture.pdf")
    derived = joinpath(root, "derived")
    write_fixture_pdf(pdf)
    report = PdfTextSearch.inspect_pdf(pdf)
    @test report["pdf"]["pages"] == 1
    PdfTextSearch.extract_pdf(pdf, PdfTextSearch.ExtractionPlan(output=derived))
    @test isfile(joinpath(derived, "manifest.json"))
    @test isfile(joinpath(derived, "pages.jsonl"))
    @test PdfTextSearch.cache_status(derived, pdf)["fresh"] === true
    lock = PdfTextSearch.acquire_cache_lock(derived)
    @test PdfTextSearch.cache_status(derived, pdf)["locked"] === true
    @test_throws PdfTextSearch.PdfTextSearchError PdfTextSearch.extract_pdf(
        pdf, PdfTextSearch.ExtractionPlan(output=derived, force=true))
    PdfTextSearch.release_cache_lock(lock)
    @test PdfTextSearch.cache_status(derived, pdf)["locked"] === false
    @test PdfTextSearch.extract_pdf(pdf, PdfTextSearch.ExtractionPlan(output=derived, reuse=true)) == derived
    PdfTextSearch.index_directory(derived)
    hits = PdfTextSearch.search(derived, "\"supply chain resilience\""; boxes=true)
    @test length(hits) == 1
    @test hits[1]["page"] == 1
    @test hits[1]["match"]["text"] == "supply chain resilience"
    @test hits[1]["match"]["original_start"] == 1
    @test hits[1]["match"]["original_stop"] == 24
    @test hits[1]["match"]["original_text"] == "supply chain resilience"
    @test length(hits[1]["boxes"]) >= 1
    @test PdfTextSearch.status(derived)["fresh"] === true
    open(pdf, "a") do io
        write(io, "\n")
    end
    @test PdfTextSearch.status(derived)["fresh"] === false
end
