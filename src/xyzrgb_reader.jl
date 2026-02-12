module XYZRGBReader

export read_xyzrgb

"""
    read_xyzrgb(filepath::String) -> Matrix{Float64}

Read a .xyzrgb file and return an Nx3 coordinate matrix (discarding RGB columns).
Format: space-delimited, 6 columns per line (x y z r g b).
"""
function read_xyzrgb(filepath::String)
    lines = readlines(filepath)
    coords = Vector{Vector{Float64}}()
    
    for line in lines
        stripped = strip(line)
        isempty(stripped) && continue
        startswith(stripped, '#') && continue  # skip comments
        
        parts = split(stripped)
        length(parts) >= 3 || continue
        
        x = parse(Float64, parts[1])
        y = parse(Float64, parts[2])
        z = parse(Float64, parts[3])
        push!(coords, [x, y, z])
    end
    
    n = length(coords)
    n == 0 && error("No valid coordinates found in $filepath")
    
    # Convert to Nx3 matrix
    mat = Matrix{Float64}(undef, n, 3)
    for i in 1:n
        mat[i, :] = coords[i]
    end
    
    return mat
end

end # module
