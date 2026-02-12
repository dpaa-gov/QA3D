module QA3D

using Genie
using Genie.Router
using Genie.Renderer.Json
using Genie.Requests
using HTTP
using JSON3

# Runtime app root — set by julia_main() or app.jl before server launch
const APP_ROOT = Ref{String}(pwd())

# Include all source at compile time
include("xyzrgb_reader.jl")
include("surface_generator.jl")
include("registration.jl")
include("routes.jl")

"""
    open_browser(url)

Open the default browser to `url`. Works on Linux, macOS, and Windows.
"""
function open_browser(url::String)
    try
        if Sys.islinux()
            run(`xdg-open $url`; wait=false)
        elseif Sys.isapple()
            run(`open $url`; wait=false)
        elseif Sys.iswindows()
            run(`cmd /c start $url`; wait=false)
        end
    catch e
        @warn "Could not open browser" exception=e
    end
end

function start_server(; port::Int=8000, open::Bool=true)
    setup_routes()
    Genie.config.run_as_server = true
    Genie.config.server_port = port
    Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*"
    Genie.config.path_build = "public"

    # Start server async, open browser, then block
    up(port, async=true)
    open && open_browser("http://127.0.0.1:$port")
    @info "QA3D running at http://127.0.0.1:$port — press Ctrl+C to stop"

    # Block until interrupted
    try
        while true
            sleep(1)
        end
    catch e
        e isa InterruptException || rethrow()
        @info "Shutting down..."
    end
end

# Entry point for compiled executable
function julia_main()::Cint
    try
        # Set working directory and APP_ROOT to the compiled app root
        app_dir = dirname(dirname(realpath(Base.julia_cmd().exec[1])))
        cd(app_dir)
        APP_ROOT[] = app_dir

        # When launched without a terminal (e.g. double-click from file manager),
        # redirect output to a log file so the pipe buffer doesn't fill up
        # and block the process during heavy computation
        if !isatty(stdout)
            log_path = joinpath(app_dir, "qa3d.log")
            log_io = open(log_path, "w")
            redirect_stdout(log_io)
            redirect_stderr(log_io)
        end

        start_server()
    catch e
        @error "QA3D fatal error" exception=(e, catch_backtrace())
        return 1
    end
    return 0
end

end
