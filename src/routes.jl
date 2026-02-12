# Routes for QA3D API
using .XYZRGBReader
using .SurfaceGenerator
using .Registration

function setup_routes()

# Heartbeat monitoring — auto-shutdown when browser closes
HEARTBEAT_TIMEOUT = 15.0
last_heartbeat = Ref(Base.time())
heartbeat_active = Ref(false)

# Serve main page
route("/") do
    Genie.Renderer.respond(read(joinpath(APP_ROOT[], "views", "index.html"), String), "text/html")
end

route("/favicon.svg") do
    filepath = joinpath(APP_ROOT[], "public", "favicon.svg")
    isfile(filepath) && return Genie.Renderer.respond(read(filepath, String), "image/svg+xml")
    Genie.Renderer.respond("", 404)
end

# Serve static files
route("/css/:file") do
    filepath = joinpath(APP_ROOT[], "public", "css", payload(:file))
    isfile(filepath) && return Genie.Renderer.respond(read(filepath, String), "text/css")
    Genie.Renderer.respond("Not found", 404)
end

route("/js/:file") do
    filepath = joinpath(APP_ROOT[], "public", "js", payload(:file))
    isfile(filepath) && return Genie.Renderer.respond(read(filepath, String), "application/javascript")
    Genie.Renderer.respond("Not found", 404)
end

route("/images/:file") do
    filepath = joinpath(APP_ROOT[], "public", "images", payload(:file))
    if isfile(filepath)
        content = read(filepath)
        return HTTP.Response(200,
            ["Content-Type" => "image/png",
             "Content-Length" => string(length(content))],
            body = content)
    end
    Genie.Renderer.respond("Not found", 404)
end

# Get user's home directory
route("/api/homedir") do
    return json(Dict("path" => homedir()))
end

# Get file info (point count) for density estimation
route("/api/fileinfo", method=POST) do
    data = jsonpayload()
    filepath = get(data, "filepath", "")
    if !isfile(filepath) || lowercase(splitext(filepath)[2]) != ".xyzrgb"
        return json(Dict("error" => "Invalid file"))
    end
    try
        coords = read_xyzrgb(filepath)
        return json(Dict("points" => size(coords, 1)))
    catch e
        return json(Dict("error" => string(e)))
    end
end

# Browse directories — returns entries with .xyzrgb file detection
route("/api/browse", method=POST) do
    data = jsonpayload()
    path = get(data, "path", "/")

    if !isdir(path)
        return json(Dict("error" => "Not a valid directory", "entries" => []))
    end

    entries = []
    try
        for name in readdir(path)
            try
                full_path = joinpath(path, name)
                ext = lowercase(splitext(name)[2])
                entry = Dict(
                    "name" => name,
                    "path" => full_path,
                    "isDirectory" => isdir(full_path),
                    "isModel" => isfile(full_path) && ext == ".xyzrgb"
                )
                push!(entries, entry)
            catch
                continue
            end
        end
    catch e
        return json(Dict("error" => string(e), "entries" => []))
    end

    sort!(entries, by = e -> (!e["isDirectory"], e["name"]))
    return json(Dict("entries" => entries, "currentPath" => path))
end

# Run comparison — stub for now
route("/api/compare", method=POST) do
    data = jsonpayload()
    filepath = get(data, "filepath", "")
    dim_x = get(data, "x", 0.0)
    dim_y = get(data, "y", 0.0)
    dim_z = get(data, "z", 0.0)
    density = get(data, "d", 1.0)

    # Validate file
    if !isfile(filepath) || lowercase(splitext(filepath)[2]) != ".xyzrgb"
        return json(Dict("error" => "Invalid .xyzrgb file"))
    end

    if dim_x <= 0 || dim_y <= 0 || dim_z <= 0 || density <= 0
        return json(Dict("error" => "All dimensions and density must be positive"))
    end

    try
        # Read scan model (xyz only, discard rgb)
        scan_coords = read_xyzrgb(filepath)

        # Generate reference box surface
        surface = generate_surface(Float64(dim_x), Float64(dim_y), Float64(dim_z), Float64(density))

        # Run PCA + ICP registration with 8-reflection search
        result = register(scan_coords, surface)

        # Return metrics + point cloud data for 3D visualization
        scan_reg = result["scan_registered"]
        surf = result["surface"]

        return json(Dict(
            "success" => true,
            "scanPoints" => size(scan_coords, 1),
            "surfacePoints" => size(surface, 1),
            "status" => result["status"],
            "bestDistance" => result["best_distance"],
            "bestReflection" => result["best_reflection"],
            "meanAtoB" => result["mean_a_to_b"],
            "meanBtoA" => result["mean_b_to_a"],
            # Flat coordinate arrays for Three.js BufferGeometry
            "scanCoords" => vec(scan_reg'),
            "surfCoords" => vec(surf'),
            "scanDistances" => result["scan_distances"],
            "surfDistances" => result["surface_distances"]
        ))
    catch e
        @error "Compare error" exception=(e, catch_backtrace())
        return json(Dict("error" => string(e)))
    end
end

# Heartbeat endpoint
route("/api/heartbeat", method=POST) do
    last_heartbeat[] = Base.time()
    if !heartbeat_active[]
        heartbeat_active[] = true
        @info "Heartbeat monitoring activated"
        @async begin
            while true
                sleep(5)
                if heartbeat_active[] && (Base.time() - last_heartbeat[] > HEARTBEAT_TIMEOUT)
                    @info "No heartbeat — shutting down..."
                    ccall(:_exit, Cvoid, (Cint,), 0)
                end
            end
        end
    end
    return json(Dict("ok" => true))
end

end # setup_routes
