@testset "examples" begin

function find_sources(path::String, sources=String[])
    if isdir(path)
        for entry in readdir(path)
            find_sources(joinpath(path, entry), sources)
        end
    elseif endswith(path, ".jl")
        push!(sources, path)
    end
    sources
end

examples_dir = joinpath(@__DIR__, "..", "examples")
examples = find_sources(examples_dir)
filter!(file -> readline(file) != "# EXCLUDE FROM TESTING", examples)
filter!(file -> !occursin("Kaleidoscope", file), examples)

cd(examples_dir) do
    examples = relpath.(examples, Ref(examples_dir))
    @testset for example in examples
        cmd = `$(Base.julia_cmd()) --project=$(Base.active_project())`
        @test success(pipeline(`$cmd $example`, stderr=stderr))
    end
end

end
