module SurfaceGenerator

export generate_surface

using LinearAlgebra
using ..MeshReader: MeshData

"""
    generate_surface(x, y, z, d) -> MeshData

Generate surface points and triangulated faces of a rectangular prism
with dimensions x × y × z at point density d.

Port of QA3D R function `nsurface(a, b, c, d)`, extended with face generation.
"""
function generate_surface(x::Float64, y::Float64, z::Float64, d::Float64)
    ax = collect(0.0:d:x)
    ay = collect(0.0:d:y)
    az = collect(0.0:d:z)

    # Use a dict to deduplicate vertices while tracking indices
    vertex_map = Dict{Tuple{Float64, Float64, Float64}, Int}()
    coords = Vector{Vector{Float64}}()
    faces = Vector{Vector{Int}}()

    function get_or_add_vertex(px, py, pz)
        key = (px, py, pz)
        idx = get(vertex_map, key, 0)
        if idx == 0
            push!(coords, [px, py, pz])
            idx = length(coords)
            vertex_map[key] = idx
        end
        return idx
    end

    # Helper: triangulate a regular grid of vertices on one face of the prism
    function add_face_grid(grid_u, grid_v, make_point)
        nu = length(grid_u)
        nv = length(grid_v)

        # Build index grid
        idx_grid = Matrix{Int}(undef, nu, nv)
        for iu in 1:nu, iv in 1:nv
            idx_grid[iu, iv] = get_or_add_vertex(make_point(grid_u[iu], grid_v[iv])...)
        end

        # Triangulate: two triangles per quad
        for iu in 1:(nu - 1), iv in 1:(nv - 1)
            a = idx_grid[iu, iv]
            b = idx_grid[iu + 1, iv]
            c = idx_grid[iu + 1, iv + 1]
            dd = idx_grid[iu, iv + 1]
            push!(faces, [a, b, c])
            push!(faces, [a, c, dd])
        end
    end

    # XY faces (z = 0 and z = max)
    add_face_grid(ax, ay, (u, v) -> (u, v, az[1]))
    add_face_grid(ax, ay, (u, v) -> (u, v, az[end]))

    # XZ faces (y = 0 and y = max)
    add_face_grid(ax, az, (u, v) -> (u, ay[1], v))
    add_face_grid(ax, az, (u, v) -> (u, ay[end], v))

    # YZ faces (x = 0 and x = max)
    add_face_grid(ay, az, (u, v) -> (ax[1], u, v))
    add_face_grid(ay, az, (u, v) -> (ax[end], u, v))

    # Convert to matrix
    n = length(coords)
    mat = Matrix{Float64}(undef, n, 3)
    for i in 1:n
        mat[i, :] = coords[i]
    end

    nf = length(faces)
    face_mat = Matrix{Int}(undef, nf, 3)
    for i in 1:nf
        face_mat[i, :] = faces[i]
    end

    # Compute per-vertex normals (face-area-weighted)
    normals = zeros(Float64, n, 3)
    for i in 1:nf
        i1, i2, i3 = face_mat[i, 1], face_mat[i, 2], face_mat[i, 3]
        v1 = mat[i1, :]
        v2 = mat[i2, :]
        v3 = mat[i3, :]
        edge1 = v2 .- v1
        edge2 = v3 .- v1
        fn = cross(edge1, edge2)  # area-weighted (magnitude = 2× triangle area)
        normals[i1, :] .+= fn
        normals[i2, :] .+= fn
        normals[i3, :] .+= fn
    end

    # Normalize and orient outward from prism centroid
    centroid = [x / 2.0, y / 2.0, z / 2.0]
    for i in 1:n
        nrm = norm(normals[i, :])
        if nrm > 0
            normals[i, :] ./= nrm
        end
        # Flip if pointing toward centroid (inward)
        outward = mat[i, :] .- centroid
        if dot(normals[i, :], outward) < 0
            normals[i, :] .*= -1
        end
    end

    return MeshData(mat, face_mat, normals)
end

end # module
