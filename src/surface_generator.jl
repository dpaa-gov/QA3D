module SurfaceGenerator

export generate_surface

"""
    generate_surface(x, y, z, d) -> Matrix{Float64}

Generate surface points of a rectangular prism with dimensions x × y × z
at point density d. Returns unique Nx3 coordinate matrix.

Port of QA3D R function `nsurface(a, b, c, d)`.
"""
function generate_surface(x::Float64, y::Float64, z::Float64, d::Float64)
    ax = collect(0.0:d:x)
    ay = collect(0.0:d:y)
    az = collect(0.0:d:z)
    
    points = Set{Tuple{Float64, Float64, Float64}}()
    
    # XY faces (z = min and z = max)
    for xi in ax, yi in ay
        push!(points, (xi, yi, az[1]))
        push!(points, (xi, yi, az[end]))
    end
    
    # XZ faces (y = min and y = max)
    for xi in ax, zi in az
        push!(points, (xi, ay[1], zi))
        push!(points, (xi, ay[end], zi))
    end
    
    # YZ faces (x = min and x = max)
    for yi in ay, zi in az
        push!(points, (ax[1], yi, zi))
        push!(points, (ax[end], yi, zi))
    end
    
    # Convert to matrix
    n = length(points)
    mat = Matrix{Float64}(undef, n, 3)
    for (i, p) in enumerate(points)
        mat[i, 1] = p[1]
        mat[i, 2] = p[2]
        mat[i, 3] = p[3]
    end
    
    return mat
end

end # module
