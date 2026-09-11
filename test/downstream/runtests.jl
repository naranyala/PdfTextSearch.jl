using Test
using Printf
using PdfTextSearch

# This project intentionally imports only PdfTextSearch's public package API;
# it models what the WebView application should compile against.
function write_fixture_pdf(path)
    content = "BT /F1 16 Tf 72 720 Td (downstream integration) Tj ET"
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
    write(path, take!(io))
end

@testset "downstream public API" begin
    # Serialize the real search result without reaching into private JSON or SQL
    # helpers; this guards the intended path-dependency integration contract.
    root = mktempdir()
    source = joinpath(root, "fixture.pdf")
    artifacts = joinpath(root, "artifacts")
    write_fixture_pdf(source)
    @test PdfTextSearch.inspect_pdf(source)["pdf"]["pages"] == 1
    directory = PdfTextSearch.extract_pdf(source, PdfTextSearch.ExtractionPlan(output=artifacts))
    PdfTextSearch.index_directory(directory)
    hits = PdfTextSearch.search(directory, "downstream")
    serialized = PdfTextSearch.serialize_result(hits)
    @test !isempty(hits)
    @test startswith(serialized, "[")
    @test occursin("downstream", serialized)
end
