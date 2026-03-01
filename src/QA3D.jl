module QA3D

using JSON3
using LinearAlgebra
using MultivariateStats
using NearestNeighbors
using Statistics

include("xyzrgb_reader.jl")
include("surface_generator.jl")
include("registration.jl")

using .XYZRGBReader
using .SurfaceGenerator
using .Registration

"""
    handle_command(cmd::Dict) -> Dict

Dispatch a JSON command to the appropriate handler function.
"""
function handle_command(cmd::Dict)
    command = get(cmd, "command", "")

    try
        if command == "fileinfo"
            filepath = get(cmd, "filepath", "")
            if !isfile(filepath) || lowercase(splitext(filepath)[2]) != ".xyzrgb"
                return Dict("error" => "Invalid file")
            end
            coords = read_xyzrgb(filepath)
            return Dict("points" => size(coords, 1))

        elseif command == "compare"
            filepath = get(cmd, "filepath", "")
            dim_x = Float64(get(cmd, "x", 0.0))
            dim_y = Float64(get(cmd, "y", 0.0))
            dim_z = Float64(get(cmd, "z", 0.0))
            density = Float64(get(cmd, "d", 1.0))

            if !isfile(filepath) || lowercase(splitext(filepath)[2]) != ".xyzrgb"
                return Dict("error" => "Invalid .xyzrgb file")
            end
            if dim_x <= 0 || dim_y <= 0 || dim_z <= 0 || density <= 0
                return Dict("error" => "All dimensions and density must be positive")
            end

            scan_coords = read_xyzrgb(filepath)
            surface = generate_surface(dim_x, dim_y, dim_z, density)
            result = register(scan_coords, surface)

            result["success"] = true
            result["scanPoints"] = size(scan_coords, 1)
            result["surfacePoints"] = size(surface, 1)

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
