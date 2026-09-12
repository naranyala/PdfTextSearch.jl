# Fast unit tests for core text, JSON, models, and public API surface.
# No Poppler/SQLite subprocesses here; see test/runtests.jl for the
# integration slice and test/unit_safety.jl for filesystem boundaries.

@testset "normalization edge cases" begin
    @test PdfTextSearch.normalize_text("") == ""
    @test PdfTextSearch.normalize_text("   \t\n  ") == ""
    @test PdfTextSearch.normalize_text("ﬁ") == "fi"  # NFKC ligature
    @test PdfTextSearch.normalize_text("Café") == PdfTextSearch.normalize_text("Café")
    @test PdfTextSearch.normalize_text("WELL-known"; casefold=false) == "WELL-known"
    @test PdfTextSearch.normalize_text("WELL-known") == "well-known"
    @test PdfTextSearch.normalize_text("well-known") == "well-known"  # intra-word hyphen kept
    @test PdfTextSearch.normalize_text("word-\n  next") == "wordnext"
    @test PdfTextSearch.normalize_text("a  \t\n b") == "a b"
    # Idempotence: normalizing twice is a fixed point.
    for raw in ("  Supply\u00a0chain  RESILIENCE ", "Cafe\u0301  line-\nbreak", "word-\n  next", "ﬁ")
        once = PdfTextSearch.normalize_text(raw)
        @test PdfTextSearch.normalize_text(once) == once
    end
end

@testset "normalization mapping" begin
    mapped = PdfTextSearch.normalize_with_map("a  b")
    @test mapped.text == "a b"
    @test length(mapped.mapping) == length(collect(mapped.text))
    # Mapping is monotonic in source space.
    firsts = [first(r) for r in mapped.mapping]
    @test issorted(firsts)
    empty_mapped = PdfTextSearch.normalize_with_map("   ")
    @test empty_mapped.text == "" && isempty(empty_mapped.mapping)
end

@testset "char utilities" begin
    @test PdfTextSearch.char_vector("héllo") == collect("héllo")
    @test PdfTextSearch.text_from_chars(collect("hello"), 1, 3) == "he"
    @test PdfTextSearch.text_from_chars(collect("hello"), 3, 3) == ""
    @test PdfTextSearch.text_from_chars(collect("hello"), 4, 2) == ""
    @test PdfTextSearch.find_char_occurrences("hello", "") == UnitRange{Int}[]
    @test PdfTextSearch.find_char_occurrences("hi", "hello") == UnitRange{Int}[]
    @test PdfTextSearch.find_char_occurrences("aaa", "aa") == [1:3, 2:4]  # overlapping
    @test PdfTextSearch.find_char_occurrences("héllo héllo", "héllo") == [1:6, 7:12]
end

@testset "deterministic JSON" begin
    @test PdfTextSearch.json_string(Dict("b" => 1, "a" => 2)) == "{\"a\":2,\"b\":1}"
    @test PdfTextSearch.json_string(:sym) == "\"sym\""
    @test PdfTextSearch.json_string(1:3) == "[1,2,3]"
    @test PdfTextSearch.json_string((1, "a")) == "[1,\"a\"]"
    @test PdfTextSearch.json_string(true) == "true"
    @test PdfTextSearch.json_string(nothing) == "null"
    @test PdfTextSearch.json_string(Inf) == "null"
    # Escape round-trip incl. control characters.
    raw = "quote \" back\\slash\nnewline\ttab\rret\bback\fform\u0001"
    @test PdfTextSearch.parse_json(PdfTextSearch.json_string(raw)) == raw
    nested = Dict("z" => [3, 2, Dict("b" => false, "a" => nothing)], "a" => 1.5)
    @test PdfTextSearch.parse_json(PdfTextSearch.json_string(nested)) == nested
    # Malformed input is rejected, never silently truncated.
    @test_throws ArgumentError PdfTextSearch.parse_json("{invalid}")
    @test_throws ArgumentError PdfTextSearch.parse_json("\"unterminated")
    @test_throws ArgumentError PdfTextSearch.parse_json("[1, 2] trailing")
    @test_throws ArgumentError PdfTextSearch.parse_json("\"bad \\q escape\"")
    # Unsupported values use the typed error taxonomy, not a MethodError.
    err = try
        PdfTextSearch.json_string(Set([1]))
        nothing
    catch e
        e
    end
    @test err isa PdfTextSearch.PdfTextSearchError && err.code == PdfTextSearch.EXIT_INTERNAL
end

@testset "JSON file round-trip" begin
    root = mktempdir()
    value = Dict("b" => [1, 2], "a" => Dict("x" => "y"))
    path = joinpath(root, "v.json")
    PdfTextSearch.write_json(path, value)
    @test PdfTextSearch.read_json(path) == value
    lines = [Dict("n" => 1), Dict("n" => 2)]
    jl_path = joinpath(root, "v.jsonl")
    PdfTextSearch.write_jsonl(jl_path, lines)
    @test PdfTextSearch.read_jsonl(jl_path) == lines
    @test PdfTextSearch.dict_get(Dict("a" => 1), "missing", 7) == 7
end

@testset "models and serialization" begin
    box = PdfTextSearch.BBox(1.0, 2.0, 3.0, 4.0)
    @test PdfTextSearch.bbox_dict(box) == Dict("x0" => 1.0, "y0" => 2.0, "x1" => 3.0, "y1" => 4.0)
    @test PdfTextSearch.bbox_dict(nothing) === nothing
    span = PdfTextSearch.Span(1, 2, 1, 6, 1, 6, "hello", "hello", box)
    sd = PdfTextSearch.span_dict(span)
    @test (sd["span_id"], sd["page_number"], sd["text"], sd["bbox"]["x1"]) == (1, 2, "hello", 3.0)
    page = PdfTextSearch.PageRecord("doc", 2, 10.0, 20.0, 0, "hello", "hello",
        "hash", [span], 0, 0, "ok", String[])
    full = PdfTextSearch.page_dict(page)
    bare = PdfTextSearch.page_dict(page; include_spans=false)
    @test haskey(full, "spans") && !haskey(bare, "spans")
    @test bare["page_number"] == 2 && bare["text"] == "hello"
    plan = PdfTextSearch.ExtractionPlan(output="out", pages=2:5)
    @test plan.pages == 2:5 && plan.include_boxes === true
    @test PdfTextSearch.ExtractionPlan(output="out").pages === nothing
end

@testset "errors and public API surface" begin
    @test PdfTextSearch.error_code_name(0) == "Success"
    @test PdfTextSearch.error_code_name(999) == "UnknownError"
    e = PdfTextSearch.PdfTextSearchError(3, "extract", "a.pdf", "nope", "retry")
    d = PdfTextSearch.error_dict(e)
    @test (d["exit_code"], d["code"], d["action"]) == (3, "InputError", "extract")
    @test occursin("extract", sprint(showerror, e))
    @test PdfTextSearch.serialize_result([1, 2]) == "[1,2]"
    caps = PdfTextSearch.capabilities()
    @test caps["index_backend"] == "sqlite-cli-fts5"
    @test haskey(caps, "tools") && haskey(caps, "providers")
    @test caps["providers"]["ocr"]["available"] === false
    @test PdfTextSearch.provider_capabilities()["enrichment"]["available"] === false
    @test_throws ArgumentError PdfTextSearch.ocr(PdfTextSearch.NO_OCR_PROVIDER, "x.pdf")
    @test PdfTextSearch.DEFAULT_INDEX_BACKEND isa PdfTextSearch.SQLiteCLIBackend
    @test_throws ArgumentError PdfTextSearch.ToolRunner(timeout=0.0)
    @test PdfTextSearch.tool_available("pdftextsearch-tool-that-does-not-exist") === false
    @test PdfTextSearch.sql_quote("o'clock") == "'o''clock'"
    @test PdfTextSearch.sql_nullable_number(nothing) == "NULL"
end
