# Build QA3D as a standalone compiled application
# Usage: julia build/build_sysimage.jl  (run from project root)
#
# Output: dist/QA3D-compiled/ (standalone application directory)
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
const DIST_DIR = joinpath(PROJECT_DIR, "dist")
const APP_DIR = joinpath(DIST_DIR, "QA3D-compiled")

@info "Building QA3D compiled application..."
@info "  Project: $PROJECT_DIR"
@info "  Output:  $APP_DIR"
@info "  Platform: $(Sys.MACHINE)"
@info ""
@info "This may take 5-15 minutes..."

# Remove previous build
rm(APP_DIR, force=true, recursive=true)

create_app(
    PROJECT_DIR,
    APP_DIR;
    executables=["qa3d" => "julia_main"],
    precompile_execution_file=joinpath(@__DIR__, "precompile_script.jl"),
    include_lazy_artifacts=true,
    incremental=true,
    force=true,
)

@info "Compiled app built successfully: $APP_DIR"
@info "Executable: $(joinpath(APP_DIR, "bin", Sys.iswindows() ? "qa3d.exe" : "qa3d"))"
