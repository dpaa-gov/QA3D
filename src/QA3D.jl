module QA3D

using JSON3
using LinearAlgebra
using MultivariateStats
using NearestNeighbors
using Statistics

include("mesh_reader.jl")
include("surface_generator.jl")
include("registration.jl")
include("dimensional_analysis.jl")

using .MeshReader
using .SurfaceGenerator
using .Registration
using .DimensionalAnalysis

"""
    handle_command(cmd::Dict) -> Dict

Dispatch a JSON command to the appropriate handler function.
"""
function handle_command(cmd::Dict)
    command = get(cmd, "command", "")

    try
        if command == "fileinfo"
            filepath = get(cmd, "filepath", "")
            ext = lowercase(splitext(filepath)[2])
            if !isfile(filepath) || ext ∉ SUPPORTED_EXTENSIONS
                return Dict("error" => "Unsupported file format. Supported: $(join(SUPPORTED_EXTENSIONS, ", "))")
            end
            mesh = read_mesh(filepath)
            return Dict("points" => size(mesh.coords, 1), "hasFaces" => mesh.faces !== nothing)

        elseif command == "compare"
            filepath = get(cmd, "filepath", "")
            dim_x = Float64(get(cmd, "x", 0.0))
            dim_y = Float64(get(cmd, "y", 0.0))
            dim_z = Float64(get(cmd, "z", 0.0))
            density = Float64(get(cmd, "d", 1.0))
            tolerance = Float64(get(cmd, "tolerance", 0.05))
            trim_pct = Float64(get(cmd, "trim_pct", 10.0))

            ext = lowercase(splitext(filepath)[2])
            if !isfile(filepath) || ext ∉ SUPPORTED_EXTENSIONS
                return Dict("error" => "Unsupported file format. Supported: $(join(SUPPORTED_EXTENSIONS, ", "))")
            end
            if dim_x <= 0 || dim_y <= 0 || dim_z <= 0 || density <= 0
                return Dict("error" => "All dimensions and density must be positive")
            end

            mesh = read_mesh(filepath)
            surf_mesh = generate_surface(dim_x, dim_y, dim_z, density)
            result = register(mesh.coords, surf_mesh.coords;
                              ref_normals=surf_mesh.normals,
                              tolerance=tolerance)

            # ── Dimensional Analysis (face-pair metrics) ──────
            n_scan = size(mesh.coords, 1)
            n_surf = size(surf_mesh.coords, 1)
            scan_reg = Matrix(reshape(Float64.(result["scanCoords"]), 3, n_scan)')
            surf_reg = Matrix(reshape(Float64.(result["surfCoords"]), 3, n_surf)')
            dim_result = analyze_dimensions(scan_reg, surf_reg, dim_x, dim_y, dim_z; trim_pct=trim_pct)
            merge!(result, dim_result)

            result["success"] = true
            result["scanPoints"] = n_scan
            result["surfacePoints"] = n_surf

            # Include face indices if available (convert to 0-based for JS)
            if mesh.faces !== nothing
                result["scanFaces"] = vec(mesh.faces' .- 1)
            end
            if surf_mesh.faces !== nothing
                result["surfFaces"] = vec(surf_mesh.faces' .- 1)
            end
            result["hasFaces"] = mesh.faces !== nothing

            return result

        else
            return Dict("error" => "Unknown command: $command")
        end

    catch e
        return Dict("error" => string(e))
    end
end

"""
    sidecar_main()

Main loop for the sidecar process. Reads JSON commands from stdin,
dispatches to handlers, and writes JSON responses to stdout.
"""
function sidecar_main()
    while !eof(stdin)
        line = readline(stdin)
        isempty(strip(line)) && continue

        try
            cmd = JSON3.read(line, Dict{String,Any})
            result = handle_command(cmd)
            println(stdout, JSON3.write(result))
            flush(stdout)
        catch e
            error_response = Dict("error" => "Failed to parse command: $(string(e))")
            println(stdout, JSON3.write(error_response))
            flush(stdout)
        end
    end
end

# Entry point for compiled executable
function julia_main()::Cint
    try
        sidecar_main()
    catch e
        println(stderr, "QA3D fatal error: $(string(e))")
        return 1
    end
    return 0
end

end
