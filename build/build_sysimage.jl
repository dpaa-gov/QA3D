# Build QA3D sysimage for faster startup
# Usage: julia --project=. build/build_sysimage.jl
#
# Output: dist/qa3d_sysimage.so (Linux), dist/qa3d_sysimage.dll (Windows),
#         dist/qa3d_sysimage.dylib (macOS)

using PackageCompiler

# Determine output extension based on platform
const SYSIMAGE_EXT = if Sys.iswindows()
    "dll"
elseif Sys.isapple()
    "dylib"
else
    "so"
end

const PROJECT_DIR = dirname(@__DIR__)
const DIST_DIR = joinpath(PROJECT_DIR, "dist")
const SYSIMAGE_PATH = joinpath(DIST_DIR, "qa3d_sysimage.$SYSIMAGE_EXT")

# Create dist directory
mkpath(DIST_DIR)

const PACKAGES = [
    :Genie,
    :HTTP,
    :JSON3,
    :LinearAlgebra,
    :MultivariateStats,
    :NearestNeighbors,
    :Statistics,
]

@info "Building QA3D sysimage..."
@info "  Project: $PROJECT_DIR"
@info "  Output:  $SYSIMAGE_PATH"
@info "  Platform: $(Sys.MACHINE)"
@info ""
@info "This may take 2-5 minutes..."

create_sysimage(
    PACKAGES;
    sysimage_path=SYSIMAGE_PATH,
    precompile_execution_file=joinpath(@__DIR__, "precompile_script.jl"),
    project=PROJECT_DIR,
)

@info "Sysimage built successfully: $SYSIMAGE_PATH"
@info "Size: $(round(filesize(SYSIMAGE_PATH) / 1024 / 1024, digits=1)) MB"
