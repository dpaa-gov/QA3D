module MeshReader

export read_mesh, SUPPORTED_EXTENSIONS

using Statistics

const SUPPORTED_EXTENSIONS = Set([".xyzrgb", ".obj", ".ply", ".stl"])

"""
    MeshData

Container for mesh vertices and optional face indices.
- `coords`:  Nx3 Float64 matrix of vertex positions
- `faces`:   Mx3 Int matrix of triangle indices (1-based), or `nothing` for point clouds
- `normals`: Nx3 Float64 matrix of per-vertex normals, or `nothing`
"""
struct MeshData
    coords::Matrix{Float64}
    faces::Union{Matrix{Int}, Nothing}
    normals::Union{Matrix{Float64}, Nothing}
end

"""
    read_mesh(filepath::String) -> MeshData

Read a 3D mesh/point cloud file and return a MeshData with coordinates and optional faces.
Dispatches to format-specific readers based on file extension.
Supported: .xyzrgb, .obj, .ply, .stl
"""
function read_mesh(filepath::String)
    ext = lowercase(splitext(filepath)[2])
    if ext == ".xyzrgb"
        return read_xyzrgb(filepath)
    elseif ext == ".obj"
        return read_obj(filepath)
    elseif ext == ".ply"
        return read_ply(filepath)
    elseif ext == ".stl"
        return read_stl(filepath)
    else
        error("Unsupported file format: $ext. Supported: $(join(SUPPORTED_EXTENSIONS, ", "))")
    end
end

# ── XYZRGB ───────────────────────────────────────────────────

"""
Read a .xyzrgb file — space-delimited, ≥3 columns per line (x y z [r g b]).
No face data (point cloud only).
"""
function read_xyzrgb(filepath::String)
    lines = readlines(filepath)
    coords = Vector{Vector{Float64}}()

    for line in lines
        stripped = strip(line)
        isempty(stripped) && continue
        startswith(stripped, '#') && continue

        parts = split(stripped)
        length(parts) >= 3 || continue

        x = parse(Float64, parts[1])
        y = parse(Float64, parts[2])
        z = parse(Float64, parts[3])
        push!(coords, [x, y, z])
    end

    return MeshData(_to_matrix(coords, filepath), nothing, nothing)
end

# ── OBJ ──────────────────────────────────────────────────────

"""
Read an .obj file — extract vertex positions and face indices.
Handles f v, f v/vt, f v/vt/vn, and f v//vn notations.
"""
function read_obj(filepath::String)
    lines = readlines(filepath)
    coords = Vector{Vector{Float64}}()
    faces = Vector{Vector{Int}}()

    for line in lines
        stripped = strip(line)
        isempty(stripped) && continue
        startswith(stripped, '#') && continue

        # Vertex lines: "v x y z [w]"
        if startswith(stripped, "v ") || startswith(stripped, "v\t")
            parts = split(stripped)
            length(parts) >= 4 || continue  # "v" + x + y + z
            x = parse(Float64, parts[2])
            y = parse(Float64, parts[3])
            z = parse(Float64, parts[4])
            push!(coords, [x, y, z])

        # Face lines: "f v1 v2 v3 ..." or "f v1/vt1/vn1 ..."
        elseif startswith(stripped, "f ") || startswith(stripped, "f\t")
            parts = split(stripped)
            length(parts) >= 4 || continue  # "f" + at least 3 vertices

            # Extract vertex indices (first component before any /)
            vidxs = Int[]
            for i in 2:length(parts)
                vstr = split(parts[i], '/')[1]
                push!(vidxs, parse(Int, vstr))
            end

            # Triangulate: fan triangulation for polygons with > 3 vertices
            for i in 2:(length(vidxs) - 1)
                push!(faces, [vidxs[1], vidxs[i], vidxs[i + 1]])
            end
        end
    end

    mat = _to_matrix(coords, filepath)
    face_mat = length(faces) > 0 ? _faces_to_matrix(faces) : nothing
    return MeshData(mat, face_mat, nothing)
end

# ── PLY ──────────────────────────────────────────────────────

"""
Read a .ply file — supports ASCII, binary_little_endian, and binary_big_endian.
Extracts x, y, z from the vertex element block and face indices.
"""
function read_ply(filepath::String)
    # Parse header to determine format and vertex layout
    io = open(filepath, "r")
    header_lines = String[]
    while !eof(io)
        line = readline(io)
        push!(header_lines, line)
        strip(line) == "end_header" && break
    end
    header_byte_offset = position(io)
    close(io)

    # Determine format
    format = "ascii"
    for line in header_lines
        if startswith(strip(line), "format ")
            parts = split(strip(line))
            format = parts[2]
            break
        end
    end

    # Find vertex count, face count, and property layouts
    n_vertices = 0
    n_faces = 0
    vertex_props = String[]
    vertex_prop_types = String[]
    in_vertex_element = false
    in_face_element = false
    face_index_type = "int"
    face_count_type = "uchar"

    for line in header_lines
        stripped = strip(line)

        if startswith(stripped, "element vertex")
            n_vertices = parse(Int, split(stripped)[3])
            in_vertex_element = true
            in_face_element = false
        elseif startswith(stripped, "element face")
            n_faces = parse(Int, split(stripped)[3])
            in_face_element = true
            in_vertex_element = false
        elseif startswith(stripped, "element ") && !startswith(stripped, "element vertex") && !startswith(stripped, "element face")
            in_vertex_element = false
            in_face_element = false
        elseif in_vertex_element && startswith(stripped, "property ")
            parts = split(stripped)
            if length(parts) >= 3 && parts[1] == "property" && parts[2] != "list"
                push!(vertex_prop_types, parts[2])
                push!(vertex_props, parts[3])
            end
        elseif in_face_element && startswith(stripped, "property list")
            # "property list uchar int vertex_indices"
            parts = split(stripped)
            if length(parts) >= 5
                face_count_type = parts[3]
                face_index_type = parts[4]
            end
        end
    end

    n_vertices == 0 && error("No vertices found in PLY file: $filepath")

    # Find indices of x, y, z in the property list
    xi = findfirst(==("x"), vertex_props)
    yi = findfirst(==("y"), vertex_props)
    zi = findfirst(==("z"), vertex_props)
    (xi === nothing || yi === nothing || zi === nothing) &&
        error("PLY file missing x/y/z vertex properties: $filepath")

    if format == "ascii"
        return _read_ply_ascii(filepath, header_lines, n_vertices, n_faces, xi, yi, zi)
    else
        is_little = format == "binary_little_endian"
        return _read_ply_binary(filepath, header_byte_offset, n_vertices, n_faces,
                                vertex_props, vertex_prop_types, xi, yi, zi, is_little,
                                face_count_type, face_index_type)
    end
end

function _read_ply_ascii(filepath, header_lines, n_vertices, n_faces, xi, yi, zi)
    lines = readlines(filepath)

    # Find where data starts (after end_header)
    data_start = 0
    for (i, line) in enumerate(lines)
        if strip(line) == "end_header"
            data_start = i + 1
            break
        end
    end

    # Read vertices
    coords = Vector{Vector{Float64}}()
    for i in data_start:min(data_start + n_vertices - 1, length(lines))
        parts = split(strip(lines[i]))
        length(parts) >= max(xi, yi, zi) || continue
        x = parse(Float64, parts[xi])
        y = parse(Float64, parts[yi])
        z = parse(Float64, parts[zi])
        push!(coords, [x, y, z])
    end

    # Read faces (immediately after vertices)
    faces = Vector{Vector{Int}}()
    face_start = data_start + n_vertices
    for i in face_start:min(face_start + n_faces - 1, length(lines))
        parts = split(strip(lines[i]))
        length(parts) >= 4 || continue  # count + at least 3 indices
        nv = parse(Int, parts[1])
        nv >= 3 || continue

        # Read vertex indices (PLY uses 0-based, convert to 1-based)
        vidxs = [parse(Int, parts[j + 1]) + 1 for j in 1:nv]

        # Fan triangulation for polygons
        for j in 2:(nv - 1)
            push!(faces, [vidxs[1], vidxs[j], vidxs[j + 1]])
        end
    end

    mat = _to_matrix(coords, filepath)
    face_mat = length(faces) > 0 ? _faces_to_matrix(faces) : nothing
    return MeshData(mat, face_mat, nothing)
end

const PLY_TYPE_SIZES = Dict(
    "char" => 1, "int8" => 1, "uchar" => 1, "uint8" => 1,
    "short" => 2, "int16" => 2, "ushort" => 2, "uint16" => 2,
    "int" => 4, "int32" => 4, "uint" => 4, "uint32" => 4,
    "float" => 4, "float32" => 4,
    "double" => 8, "float64" => 8,
)

const PLY_TYPE_MAP = Dict(
    "char" => Int8, "int8" => Int8,
    "uchar" => UInt8, "uint8" => UInt8,
    "short" => Int16, "int16" => Int16,
    "ushort" => UInt16, "uint16" => UInt16,
    "int" => Int32, "int32" => Int32,
    "uint" => UInt32, "uint32" => UInt32,
    "float" => Float32, "float32" => Float32,
    "double" => Float64, "float64" => Float64,
)

function _read_ply_binary(filepath, header_byte_offset, n_vertices, n_faces,
                          vertex_props, vertex_prop_types, xi, yi, zi, is_little,
                          face_count_type, face_index_type)
    # Compute byte offsets for each property
    prop_offsets = Int[]
    offset = 0
    for dtype in vertex_prop_types
        push!(prop_offsets, offset)
        offset += get(PLY_TYPE_SIZES, dtype, 4)
    end
    vertex_stride = offset

    mat = Matrix{Float64}(undef, n_vertices, 3)

    faces = Vector{Vector{Int}}()

    open(filepath, "r") do io
        seek(io, header_byte_offset)

        # Read all vertex data
        vertex_buf = read(io, vertex_stride * n_vertices)

        for i in 1:n_vertices
            base = (i - 1) * vertex_stride
            for (col, pi) in enumerate([xi, yi, zi])
                dtype = vertex_prop_types[pi]
                jtype = PLY_TYPE_MAP[dtype]
                nbytes = PLY_TYPE_SIZES[dtype]
                start = base + prop_offsets[pi] + 1
                raw = vertex_buf[start:start+nbytes-1]
                if !is_little
                    reverse!(raw)
                end
                val = reinterpret(jtype, raw)[1]
                mat[i, col] = Float64(val)
            end
        end

        # Read face data
        count_jtype = get(PLY_TYPE_MAP, face_count_type, UInt8)
        count_size = get(PLY_TYPE_SIZES, face_count_type, 1)
        index_jtype = get(PLY_TYPE_MAP, face_index_type, Int32)
        index_size = get(PLY_TYPE_SIZES, face_index_type, 4)

        for _ in 1:n_faces
            # Read vertex count for this face
            raw_count = read(io, count_size)
            if !is_little
                reverse!(raw_count)
            end
            nv = Int(reinterpret(count_jtype, raw_count)[1])

            # Read vertex indices (0-based in PLY, convert to 1-based)
            vidxs = Vector{Int}(undef, nv)
            for j in 1:nv
                raw_idx = read(io, index_size)
                if !is_little
                    reverse!(raw_idx)
                end
                vidxs[j] = Int(reinterpret(index_jtype, raw_idx)[1]) + 1
            end

            # Fan triangulation
            for j in 2:(nv - 1)
                push!(faces, [vidxs[1], vidxs[j], vidxs[j + 1]])
            end
        end
    end

    face_mat = length(faces) > 0 ? _faces_to_matrix(faces) : nothing
    return MeshData(mat, face_mat, nothing)
end

# ── STL ──────────────────────────────────────────────────────

"""
Read an .stl file — supports ASCII and binary. Deduplicates vertices and builds faces.
"""
function read_stl(filepath::String)
    bytes = open(filepath, "r") do io
        read(io, min(256, filesize(filepath)))
    end

    text_start = String(bytes[1:min(80, length(bytes))])
    is_ascii = startswith(strip(text_start), "solid") && _stl_has_facet(filepath)

    if is_ascii
        return _read_stl_ascii(filepath)
    else
        return _read_stl_binary(filepath)
    end
end

"""Check if file contains 'facet' keyword (distinguishes ASCII from binary with 'solid' header)."""
function _stl_has_facet(filepath::String)
    bytes = open(filepath, "r") do io
        read(io, min(1024, filesize(filepath)))
    end
    return occursin("facet", String(bytes))
end

function _read_stl_ascii(filepath::String)
    lines = readlines(filepath)
    raw_coords = Vector{Vector{Float64}}()

    for line in lines
        stripped = strip(line)
        if startswith(stripped, "vertex ")
            parts = split(stripped)
            length(parts) >= 4 || continue
            x = parse(Float64, parts[2])
            y = parse(Float64, parts[3])
            z = parse(Float64, parts[4])
            push!(raw_coords, [x, y, z])
        end
    end

    return _stl_dedup_with_faces(raw_coords, filepath)
end

function _read_stl_binary(filepath::String)
    raw_coords = Vector{Vector{Float64}}()

    open(filepath, "r") do io
        read(io, 80)  # skip header
        n_triangles = ltoh(read(io, UInt32))
        sizehint!(raw_coords, n_triangles * 3)

        for _ in 1:n_triangles
            read(io, 12)  # skip normal
            for _ in 1:3
                x = Float64(ltoh(read(io, Float32)))
                y = Float64(ltoh(read(io, Float32)))
                z = Float64(ltoh(read(io, Float32)))
                push!(raw_coords, [x, y, z])
            end
            read(io, 2)  # skip attribute
        end
    end

    return _stl_dedup_with_faces(raw_coords, filepath)
end

"""
Deduplicate STL vertices and build face indices.
Every 3 raw vertices form one triangle. After deduplication, face indices
reference the unique vertex list.
"""
function _stl_dedup_with_faces(raw_coords::Vector{Vector{Float64}}, filepath::String)
    # Build unique vertex map
    vertex_map = Dict{Tuple{Float64,Float64,Float64}, Int}()
    unique_coords = Vector{Vector{Float64}}()
    remapped_indices = Vector{Int}(undef, length(raw_coords))

    for (i, v) in enumerate(raw_coords)
        key = (v[1], v[2], v[3])
        idx = get(vertex_map, key, 0)
        if idx == 0
            push!(unique_coords, v)
            idx = length(unique_coords)
            vertex_map[key] = idx
        end
        remapped_indices[i] = idx
    end

    @info "STL deduplication: $(length(raw_coords)) → $(length(unique_coords)) vertices"

    # Build face list (every 3 raw vertices = 1 triangle)
    n_triangles = div(length(raw_coords), 3)
    faces = Vector{Vector{Int}}(undef, n_triangles)
    for t in 1:n_triangles
        base = (t - 1) * 3
        faces[t] = [remapped_indices[base + 1], remapped_indices[base + 2], remapped_indices[base + 3]]
    end

    mat = _to_matrix(unique_coords, filepath)
    face_mat = _faces_to_matrix(faces)
    return MeshData(mat, face_mat, nothing)
end

# ── Helpers ──────────────────────────────────────────────────

"""Convert a Vector{Vector{Float64}} to an Nx3 Matrix."""
function _to_matrix(coords::Vector{Vector{Float64}}, filepath::String)
    n = length(coords)
    n == 0 && error("No valid coordinates found in $filepath")

    mat = Matrix{Float64}(undef, n, 3)
    for i in 1:n
        mat[i, :] = coords[i]
    end
    return mat
end

"""Convert a Vector{Vector{Int}} of triangle indices to an Mx3 Matrix."""
function _faces_to_matrix(faces::Vector{Vector{Int}})
    n = length(faces)
    mat = Matrix{Int}(undef, n, 3)
    for i in 1:n
        mat[i, :] = faces[i]
    end
    return mat
end

end # module
