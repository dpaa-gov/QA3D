# Build QA3D sysimage for faster startup
using PackageCompiler

create_sysimage(
    [:Genie, :HTTP, :JSON3, :LinearAlgebra, :MultivariateStats, :NearestNeighbors, :Statistics];
    sysimage_path = joinpath(@__DIR__, "..", "dist", "qa3d_sysimage.so"),
    precompile_execution_file = joinpath(@__DIR__, "precompile_script.jl"),
    project = joinpath(@__DIR__, "..")
)
