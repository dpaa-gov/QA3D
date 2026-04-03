module MeshReader

export read_mesh, SUPPORTED_EXTENSIONS

using Statistics

const SUPPORTED_EXTENSIONS = Set([".xyzrgb", ".obj", ".ply", ".stl"])

"""
    read_mesh(filepath::String) -> Matrix{Float64}

Read a 3D mesh/point cloud file and return an Nx3 coordinate matrix.
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

    return _to_matrix(coords, filepath)
end

# ── OBJ ──────────────────────────────────────────────────────

"""
Read an .obj file — extract vertex positions from lines starting with `v `.
"""
function read_obj(filepath::String)
    lines = readlines(filepath)
    coords = Vector{Vector{Float64}}()

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
        end
    end

    return _to_matrix(coords, filepath)
end

# ── PLY ──────────────────────────────────────────────────────

"""
Read a .ply file — supports ASCII, binary_little_endian, and binary_big_endian.
Extracts x, y, z from the vertex element block.
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

    # Find vertex count and property layout
    n_vertices = 0
    vertex_props = String[]  # property type names in order
    vertex_prop_types = String[]  # property data types in order
    in_vertex_element = false

    for line in header_lines
        stripped = strip(line)

        if startswith(stripped, "element vertex")
            n_vertices = parse(Int, split(stripped)[3])
            in_vertex_element = true
        elseif startswith(stripped, "element ") && in_vertex_element
            # Hit a new element — stop collecting vertex properties
            break
        elseif in_vertex_element && startswith(stripped, "property ")
            parts = split(stripped)
            # "property <type> <name>"
            if length(parts) >= 3 && parts[1] == "property" && parts[2] != "list"
                push!(vertex_prop_types, parts[2])
                push!(vertex_props, parts[3])
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
        return _read_ply_ascii(filepath, header_lines, n_vertices, xi, yi, zi)
    else
        is_little = format == "binary_little_endian"
        return _read_ply_binary(filepath, header_byte_offset, n_vertices,
                                vertex_props, vertex_prop_types, xi, yi, zi, is_little)
    end
end

function _read_ply_ascii(filepath, header_lines, n_vertices, xi, yi, zi)
    lines = readlines(filepath)

    # Find where data starts (after end_header)
    data_start = 0
    for (i, line) in enumerate(lines)
        if strip(line) == "end_header"
            data_start = i + 1
            break
        end
    end

    coords = Vector{Vector{Float64}}()
    for i in data_start:min(data_start + n_vertices - 1, length(lines))
        parts = split(strip(lines[i]))
        length(parts) >= max(xi, yi, zi) || continue
        x = parse(Float64, parts[xi])
        y = parse(Float64, parts[yi])
        z = parse(Float64, parts[zi])
        push!(coords, [x, y, z])
    end

    return _to_matrix(coords, filepath)
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

function _read_ply_binary(filepath, header_byte_offset, n_vertices,
                          vertex_props, vertex_prop_types, xi, yi, zi, is_little)
    # Compute byte offsets for each property
    prop_offsets = Int[]
    offset = 0
    for dtype in vertex_prop_types
        push!(prop_offsets, offset)
        offset += get(PLY_TYPE_SIZES, dtype, 4)
    end
    vertex_stride = offset

    mat = Matrix{Float64}(undef, n_vertices, 3)

    open(filepath, "r") do io
        seek(io, header_byte_offset)
        buf = read(io, vertex_stride * n_vertices)

        for i in 1:n_vertices
            base = (i - 1) * vertex_stride
            for (col, pi) in enumerate([xi, yi, zi])
                dtype = vertex_prop_types[pi]
                jtype = PLY_TYPE_MAP[dtype]
                nbytes = PLY_TYPE_SIZES[dtype]
                start = base + prop_offsets[pi] + 1
                raw = buf[start:start+nbytes-1]
                if !is_little
                    reverse!(raw)
                end
                val = reinterpret(jtype, raw)[1]
                mat[i, col] = Float64(val)
            end
        end
    end

    return mat
end

# ── STL ──────────────────────────────────────────────────────

"""
Read an .stl file — supports ASCII and binary. Deduplicates vertices.
"""
function read_stl(filepath::String)
    # Detect ASCII vs binary: ASCII files start with "solid " followed by a name,
    # and contain "facet normal". Binary files have an 80-byte header.
    bytes = open(filepath, "r") do io
        read(io, min(256, filesize(filepath)))
    end

    # Check if first non-whitespace content looks like ASCII STL
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
    # Read first ~1KB to check for facet keyword
    bytes = open(filepath, "r") do io
        read(io, min(1024, filesize(filepath)))
    end
    return occursin("facet", String(bytes))
end

function _read_stl_ascii(filepath::String)
    lines = readlines(filepath)
    coords = Vector{Vector{Float64}}()

    for line in lines
        stripped = strip(line)
        if startswith(stripped, "vertex ")
            parts = split(stripped)
            length(parts) >= 4 || continue
            x = parse(Float64, parts[2])
            y = parse(Float64, parts[3])
            z = parse(Float64, parts[4])
            push!(coords, [x, y, z])
        end
    end

    mat = _to_matrix(coords, filepath)
    return _deduplicate(mat)
end

function _read_stl_binary(filepath::String)
    open(filepath, "r") do io
        # 80-byte header (skip)
        read(io, 80)
        # Number of triangles (UInt32, little-endian)
        n_triangles = ltoh(read(io, UInt32))

        # Each facet: 12 bytes normal + 36 bytes vertices (3×3 Float32) + 2 bytes attribute
        coords = Vector{Vector{Float64}}()
        sizehint!(coords, n_triangles * 3)

        for _ in 1:n_triangles
            # Skip normal (3 × Float32 = 12 bytes)
            read(io, 12)
            # Read 3 vertices
            for _ in 1:3
                x = Float64(ltoh(read(io, Float32)))
                y = Float64(ltoh(read(io, Float32)))
                z = Float64(ltoh(read(io, Float32)))
                push!(coords, [x, y, z])
            end
            # Skip attribute byte count (2 bytes)
            read(io, 2)
        end

        mat = _to_matrix(coords, filepath)
        return _deduplicate(mat)
    end
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

"""Deduplicate rows of an Nx3 matrix (for STL)."""
function _deduplicate(mat::Matrix{Float64})
    unique_rows = unique(mat, dims=1)
    @info "STL deduplication: $(size(mat, 1)) → $(size(unique_rows, 1)) vertices"
    return unique_rows
end

end # module
