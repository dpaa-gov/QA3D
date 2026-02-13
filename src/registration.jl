module Registration

export register

using LinearAlgebra
using MultivariateStats
using NearestNeighbors
using Statistics

# ── PCA alignment ────────────────────────────────────────────
"""
Center and PCA-align a point cloud.
Matches the R implementation: scale(x, scale=F) %*% eigen(var(x))\$vectors
"""
function pca_align(pts::Matrix{Float64})
    centered = pts .- mean(pts, dims=1)
    C = cov(centered)
    eig = eigen(C)
    # eigen() returns ascending order; R's eigen() returns descending
    # Reverse to match R behavior
    aligned = centered * eig.vectors[:, end:-1:1]
    return aligned
end

# ── 8 Reflection patterns ────────────────────────────────────
const REFLECTIONS = [
    ( 1,  1,  1),  # original
    (-1, -1, -1),
    ( 1, -1, -1),
    (-1,  1, -1),
    (-1, -1,  1),
    ( 1,  1, -1),
    ( 1, -1,  1),
    (-1,  1,  1),
]

function apply_reflection(pts::Matrix{Float64}, r::Tuple{Int,Int,Int})
    out = copy(pts)
    out[:, 1] .*= r[1]
    out[:, 2] .*= r[2]
    out[:, 3] .*= r[3]
    return out
end

# ── SVD rigid body alignment (point-to-point) ────────────────
"""
Compute rigid transformation (R, t) aligning `moving` to `target`
using SVD of the cross-covariance matrix (Arun et al. 1987).
Returns rotation matrix R and translation vector t.
"""
function rigid_transform_svd(moving::Matrix{Float64}, target::Matrix{Float64})
    cm = mean(moving, dims=1)
    ct = mean(target, dims=1)

    # Center
    P = moving .- cm
    Q = target .- ct

    # Cross-covariance
    H = P' * Q

    U, S, Vt = svd(H)
    V = Vt  # Julia's svd returns V, not Vt

    # Ensure proper rotation (det = +1)
    d = det(V * U')
    D = diagm([1.0, 1.0, d < 0 ? -1.0 : 1.0])

    R = V * D * U'
    t = vec(ct) - R * vec(cm)

    return R, t
end

"""
Apply rigid transformation to an Nx3 matrix.
"""
function apply_transform(pts::Matrix{Float64}, R::Matrix{Float64}, t::Vector{Float64})
    return (R * pts')' .+ t'
end

# ── Point-to-point ICP ───────────────────────────────────────
"""
Run point-to-point ICP on two Nx3 matrices.
Returns registered moving point cloud.
"""
function run_icp(fixed::Matrix{Float64}, moving::Matrix{Float64};
                 max_iterations::Int=100, tolerance::Float64=1e-6)

    current = copy(moving)
    prev_error = Inf

    for i in 1:max_iterations
        # Find nearest neighbors: for each moving point, find closest fixed point
        tree = KDTree(fixed')
        idxs, dists = knn(tree, current', 1)

        # Build correspondence arrays
        idx_vec = [idxs[j][1] for j in eachindex(idxs)]
        target_pts = fixed[idx_vec, :]

        # Compute rigid transform
        R, t = rigid_transform_svd(current, target_pts)

        # Apply transform
        current = apply_transform(current, R, t)

        # Check convergence
        mean_error = mean([dists[j][1] for j in eachindex(dists)])
        if abs(prev_error - mean_error) < tolerance
            @info "ICP converged after $i iterations (error: $(round(mean_error, digits=6)))"
            break
        end
        prev_error = mean_error
    end

    return current
end

# ── Bidirectional Hausdorff (mean of means) ──────────────────
"""
Bidirectional mean Hausdorff distance.
Returns (mean_of_means, mean_A_to_B, mean_B_to_A).
Matches R implementation: mean(mean_AB, mean_BA).
"""
function hausdorff_bidirectional(A::Matrix{Float64}, B::Matrix{Float64})
    # A → B
    tree_b = KDTree(B')
    _, dists_ab = knn(tree_b, A', 1)
    mean_ab = mean([dists_ab[i][1] for i in eachindex(dists_ab)])

    # B → A
    tree_a = KDTree(A')
    _, dists_ba = knn(tree_a, B', 1)
    mean_ba = mean([dists_ba[i][1] for i in eachindex(dists_ba)])

    return (mean_ab + mean_ba) / 2, mean_ab, mean_ba
end

using JSON3

# ── Main entry point ─────────────────────────────────────────
"""
    register(scan, surface; data_dir=nothing) -> Dict

1. PCA-align both point clouds
2. Try all 8 axis reflections
3. Point-to-point ICP for each
4. Return best (lowest bidirectional Hausdorff)

If `data_dir` is provided, per-point distances and coordinates are written
directly to a temp JSON file (never held in the return Dict).
"""
function register(scan::Matrix{Float64}, surface::Matrix{Float64};
                  data_dir::Union{String,Nothing}=nothing)
    # PCA alignment (matches R: scale + eigen(var))
    scan_pca = pca_align(scan)
    surf_pca = pca_align(surface)

    best_dist = Inf
    best_result = scan_pca
    best_reflection = 1
    best_ab = 0.0
    best_ba = 0.0

    for (j, refl) in enumerate(REFLECTIONS)
        reflected = apply_reflection(scan_pca, refl)
        registered = run_icp(surf_pca, reflected)
        dist, ab, ba = hausdorff_bidirectional(registered, surf_pca)

        @info "Reflection $j $(refl): Hausdorff = $(round(dist, digits=4)) (A→B: $(round(ab, digits=4)), B→A: $(round(ba, digits=4)))"

        if dist < best_dist
            best_dist = dist
            best_result = registered
            best_reflection = j
            best_ab = ab
            best_ba = ba
        end
    end

    result = Dict(
        "status" => "complete",
        "best_distance" => round(best_dist, digits=4),
        "best_reflection" => best_reflection,
        "mean_a_to_b" => round(best_ab, digits=4),
        "mean_b_to_a" => round(best_ba, digits=4)
    )

    # If data_dir provided, compute per-point distances and stream to file
    if data_dir !== nothing
        mkpath(data_dir)
        data_id = "result_$(round(Int, time() * 1000))"
        data_file = joinpath(data_dir, "$data_id.json")

        # Compute per-point distances
        tree_surf = KDTree(surf_pca')
        _, scan_dists = knn(tree_surf, best_result', 1)

        tree_scan = KDTree(best_result')
        _, surf_dists = knn(tree_scan, surf_pca', 1)

        # Stream directly to file — large arrays never enter the Dict
        open(data_file, "w") do io
            JSON3.write(io, Dict(
                "scanCoords" => vec(best_result'),
                "surfCoords" => vec(surf_pca'),
                "scanDistances" => [round(scan_dists[i][1], digits=4) for i in eachindex(scan_dists)],
                "surfDistances" => [round(surf_dists[i][1], digits=4) for i in eachindex(surf_dists)]
            ))
        end

        result["dataFile"] = "/data/$data_id.json"
    end

    return result
end

end # module
