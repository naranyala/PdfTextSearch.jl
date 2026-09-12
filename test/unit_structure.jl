# Structural guard: keep every src/ module small enough to review in one pass.
# The longest module today is ~344 lines, so the 400-line ceiling leaves
# headroom without permitting a slide toward 1000-line files.

@testset "module size guard" begin
    root = joinpath(@__DIR__, "..", "src")
    limit = 400
    sizes = Tuple{String,Int}[]
    for (dir, _, files) in walkdir(root)
        for file in files
            endswith(file, ".jl") || continue
            path = joinpath(dir, file)
            push!(sizes, (relpath(path, root), countlines(path)))
        end
    end
    @test !isempty(sizes)
    over = filter(((name, n),) -> n > limit, sizes)
    @test isempty(over) ||
        error("modules over $(limit) lines (split by responsibility): " *
              join(["$(name): $(n)" for (name, n) in over], ", "))
    # Sanity: the historic ceiling from the reorganization review.
    @test all(((_, n),) -> n <= 1000, sizes)
end
