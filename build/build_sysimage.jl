# Build QA3D Julia sidecar as a standalone compiled executable
# Usage: julia build/build_sysimage.jl  (run from project root)
#
# Output: sidecar/ (ready for Electron bundling)
# The compiled binary communicates with the Electron app via stdin/stdout JSON.
# PackageCompiler is installed to the default Julia environment if missing.

# Ensure PackageCompiler is available (not a project dependency)
try
    @eval using PackageCompiler
catch
    import Pkg
    Pkg.add("PackageCompiler")
    @eval using PackageCompiler
end

const PROJECT_DIR = dirname(@__DIR__)
const SIDECAR_DIR = joinpath(PROJECT_DIR, "sidecar")

@info "Building QA3D sidecar..."
@info "  Project: $PROJECT_DIR"
@info "  Output:  $SIDECAR_DIR"
@info "  Platform: $(Sys.MACHINE)"
@info ""
@info "This may take 5-15 minutes..."

# Remove previous build
rm(SIDECAR_DIR, force=true, recursive=true)

create_app(
    PROJECT_DIR,
    SIDECAR_DIR;
    executables=["qa3d" => "julia_main"],
    precompile_execution_file=joinpath(@__DIR__, "precompile_workload.jl"),
    include_lazy_artifacts=true,
    incremental=false,
    force=true,
)

exe_name = Sys.iswindows() ? "qa3d.exe" : "qa3d"
@info "Sidecar built successfully: $(joinpath(SIDECAR_DIR, "bin", exe_name))"
@info ""
@info "Ready for Electron build — run: npm run build"

