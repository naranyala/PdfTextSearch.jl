using Dates

"""Run a small repeatable command-path benchmark over an existing derived index."""
function benchmark_search(directory::AbstractString, queries::Vector{String})
    handle = open_index(directory)
    samples = Any[]
    for query in queries
        started = time_ns()
        hits = search(handle, query; limit=20)
        elapsed_ms = (time_ns() - started) / 1_000_000
        push!(samples, Dict{String,Any}("query" => query, "matches" => length(hits), "elapsed_ms" => elapsed_ms))
    end
    Dict{String,Any}("schema_version" => ARTIFACT_SCHEMA_VERSION, "generated_at" => string(Dates.now()),
                     "index" => handle.database, "samples" => samples)
end
