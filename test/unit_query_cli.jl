# Fast unit tests for query semantics and CLI parsing.
# Heavy CLI subprocess and index-search paths stay in test/runtests.jl.

@testset "query parsing" begin
    @test_throws PdfTextSearch.PdfTextSearchError PdfTextSearch.parse_query("")
    @test_throws PdfTextSearch.PdfTextSearchError PdfTextSearch.parse_query("   ")
    quoted_empty = try
        PdfTextSearch.parse_query("\"   \"")
        nothing
    catch e
        e
    end
    @test quoted_empty isa PdfTextSearch.PdfTextSearchError && quoted_empty.code == PdfTextSearch.EXIT_USAGE

    spec = PdfTextSearch.parse_query("supply chain")
    @test spec.terms == ["supply", "chain"] && isempty(spec.phrases)
    phrase = PdfTextSearch.parse_query("\"Supply Chain\" resilience")
    @test phrase.phrases == ["supply chain"] && phrase.terms == ["resilience"]
    flags = PdfTextSearch.parse_query("Hi"; literal=true, case_sensitive=true, regex=false)
    @test flags.literal === true && flags.case_sensitive === true
end

@testset "query matching modes" begin
    @test PdfTextSearch.query_occurrences("C++ rocks", PdfTextSearch.parse_query("C++"; literal=true)) == [1:4]
    @test PdfTextSearch.query_occurrences("aaa", PdfTextSearch.parse_query("aa"; literal=true)) == [1:3, 2:4]
    cs = PdfTextSearch.parse_query("Hello"; case_sensitive=true)
    @test PdfTextSearch.query_occurrences("hello Hello", cs) == [7:12]
    @test isempty(PdfTextSearch.query_occurrences("hello world", cs))
    rx = PdfTextSearch.parse_query("h.llo"; regex=true)
    @test PdfTextSearch.query_occurrences("say hillo ok", rx) == [5:10]
    bad_rx = try
        PdfTextSearch.regex_occurrences("hello", "([")
        nothing
    catch e
        e
    end
    @test bad_rx isa PdfTextSearch.PdfTextSearchError && bad_rx.code == PdfTextSearch.EXIT_USAGE
    # Case-insensitive evidence maps back onto the original text.
    @test PdfTextSearch.original_match_range("Café", 1:5, false) == 1:5
    @test PdfTextSearch.original_match_range("Café", 1:5, false) == 1:6  # decomposed é
    @test PdfTextSearch.original_match_range("hello", 1:3, true) == 1:3
end

@testset "FTS and SQL fragments" begin
    @test PdfTextSearch.fts_quote("a\"b") == "\"a\"\"b\""
    spec = PdfTextSearch.parse_query("\"supply chain\" resilience")
    @test PdfTextSearch.fts_expression(spec) == "\"supply chain\" AND \"resilience\""
    empty_spec = PdfTextSearch.QuerySpec("x", String[], String[], false, false, true)
    @test PdfTextSearch.fts_expression(empty_spec) == ""
    @test PdfTextSearch.page_where(nothing, nothing) == ""
    @test PdfTextSearch.page_where(2, nothing) == " AND p.page_number = 2"
    @test PdfTextSearch.page_where(nothing, 2:5) == " AND p.page_number BETWEEN 2 AND 5"
end

@testset "snippets and char positions" begin
    @test PdfTextSearch.snippet("", 1:1, 5) == ""
    @test PdfTextSearch.snippet("hello world", 1:6, 0) == "hello..."
    @test PdfTextSearch.snippet("hello world", 7:12, 2) == "...o world"
    @test PdfTextSearch.snippet("hello", 1:6, 80) == "hello"
    @test PdfTextSearch.byte_to_char_position("hello", 1) == 1
    @test PdfTextSearch.byte_to_char_position("hello", 3) == 3
    @test PdfTextSearch.byte_to_char_position("h\xc3\xa9llo", 4) == 3  # byte vs char offset
end

@testset "CLI option parsing" begin
    pos, opt = PdfTextSearch.cli_options(["inspect", "a.pdf", "--json"])
    @test pos == ["inspect", "a.pdf"] && opt[:json] === true
    _, opt_eq = PdfTextSearch.cli_options(["--out=dir"])
    @test opt_eq[:out] == "dir"
    _, opt_sp = PdfTextSearch.cli_options(["--out", "dir"])
    @test opt_sp[:out] == "dir"
    pos_sep, _ = PdfTextSearch.cli_options(["--", "--json"])
    @test pos_sep == ["--json"]
    @test_throws PdfTextSearch.PdfTextSearchError PdfTextSearch.cli_options(["--nope"])
    @test_throws PdfTextSearch.PdfTextSearchError PdfTextSearch.cli_options(["--out"])
    @test PdfTextSearch.cli_integer(Dict(:limit => "5"), :limit, 20) == 5
    @test PdfTextSearch.cli_integer(Dict{Symbol,Any}(), :limit, 20) == 20
    @test_throws PdfTextSearch.PdfTextSearchError PdfTextSearch.cli_integer(Dict(:limit => "x"), :limit, 20)
    @test PdfTextSearch.cli_page_range(Dict{Symbol,Any}()) === nothing
    @test PdfTextSearch.cli_page_range(Dict(:pages => "2:5")) == 2:5
    @test PdfTextSearch.cli_page_range(Dict(:pages => "3")) == 3:3
    @test_throws PdfTextSearch.PdfTextSearchError PdfTextSearch.cli_page_range(Dict(:pages => "5:2"))
    @test_throws PdfTextSearch.PdfTextSearchError PdfTextSearch.cli_page_range(Dict(:pages => "x"))
end

@testset "CLI entry-point exit codes" begin
    redirect_stdout(devnull) do
        @test PdfTextSearch.main(String[]) == PdfTextSearch.EXIT_USAGE
        @test PdfTextSearch.main(["--help"]) == PdfTextSearch.EXIT_SUCCESS
        @test PdfTextSearch.main(["--version"]) == PdfTextSearch.EXIT_SUCCESS
        @test PdfTextSearch.main(["unknown-command"]) == PdfTextSearch.EXIT_USAGE
        @test PdfTextSearch.main(["search", "only-one-positional"]) == PdfTextSearch.EXIT_USAGE
    end
end
