using Test
using Printf

include(joinpath(@__DIR__, "..", "src", "PDFProbe.jl"))
using .PDFProbe

@testset "normalization and JSON" begin
    @test PDFProbe.normalize_text("  Supply\u00a0chain  RESILIENCE ") == "supply chain resilience"
    @test PDFProbe.normalize_text("hyphen-\nbreak") == "hyphenbreak"
    value = Dict("text" => "quote \" and \\ slash", "ok" => true, "nothing" => nothing)
    @test PDFProbe.parse_json(PDFProbe.json_string(value)) == value
end

@testset "query semantics" begin
    @test PDFProbe.find_char_occurrences("a phrase phrase", "phrase") == [3:9, 10:16]
    spec = PDFProbe.parse_query("\"Supply Chain\"")
    @test spec.phrases == ["supply chain"]
    @test PDFProbe.query_occurrences("Supply chain resilience", spec) == [1:13]
end

@testset "PDF reader and inspect" begin
    @test PDFProbe.executable_available("pdfinfo")
    @test PDFProbe.executable_available("pdftotext")
end

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
    root = mktempdir()
    pdf = joinpath(root, "fixture.pdf")
    derived = joinpath(root, "derived")
    write_fixture_pdf(pdf)
    report = PDFProbe.inspect_pdf(pdf)
    @test report["pdf"]["pages"] == 1
    PDFProbe.extract_pdf(pdf, PDFProbe.ExtractionPlan(output=derived))
    @test isfile(joinpath(derived, "manifest.json"))
    @test isfile(joinpath(derived, "pages.jsonl"))
    PDFProbe.index_directory(derived)
    hits = PDFProbe.search(derived, "\"supply chain resilience\""; boxes=true)
    @test length(hits) == 1
    @test hits[1]["page"] == 1
    @test hits[1]["match"]["text"] == "supply chain resilience"
    @test length(hits[1]["boxes"]) >= 1
    @test PDFProbe.status(derived)["fresh"] === true
    open(pdf, "a") do io
        write(io, "\n")
    end
    @test PDFProbe.status(derived)["fresh"] === false
end
