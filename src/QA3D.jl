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

Open a Chromium-based browser in app mode (no address bar/tabs).
Falls back to the default browser if no Chromium variant is found.
Works on Linux and Windows.
"""
function open_browser(url::String)
    try
        if Sys.islinux()
            # Try Chromium-based browsers in --app mode first
            for browser in ("google-chrome", "google-chrome-stable", "chromium-browser", "chromium", "microsoft-edge")
                if success(`which $browser`)
                    run(`$browser --app=$url --new-window`; wait=false)
                    return
                end
            end
            run(`xdg-open $url`; wait=false)
        elseif Sys.iswindows()
            # Try Chrome/Edge app mode on Windows
            for browser in (
                raw"C:\Program Files\Google\Chrome\Application\chrome.exe",
                raw"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                raw"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
            )
                if isfile(browser)
                    run(`$browser --app=$url --new-window`; wait=false)
                    return
                end
            end
            run(`cmd /c start $url`; wait=false)
        end
    catch e
        @warn "Could not open browser" exception=e
    end
end

function start_server(; port::Int=8001, open::Bool=true)
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

        # Suppress output only when no terminal is attached (double-click launch)
        if !isa(stdin, Base.TTY)
            devnull_io = open(Sys.iswindows() ? "NUL" : "/dev/null", "w")
            redirect_stdout(devnull_io)
            redirect_stderr(devnull_io)
            Base.CoreLogging.global_logger(Base.CoreLogging.SimpleLogger(devnull_io, Base.CoreLogging.Error))
        end

        start_server()
    catch e
        @error "QA3D fatal error" exception=(e, catch_backtrace())
        return 1
    end
    return 0
end

end
