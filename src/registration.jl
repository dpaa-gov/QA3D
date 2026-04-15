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

    # Build KD-tree on fixed cloud ONCE (it never changes)
    tree = KDTree(fixed')

    for i in 1:max_iterations
        # Find nearest neighbors: for each moving point, find closest fixed point
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

# ── Bidirectional Mean Distance (Chamfer Distance) ───────────
"""
Bidirectional mean distance (Chamfer distance).
Returns (mean_of_means, mean_A_to_B, mean_B_to_A).
"""
function bidirectional_mean_distance(A::Matrix{Float64}, B::Matrix{Float64})
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

"""
    register(scan, surface; ref_normals, tolerance) -> Dict

1. PCA-align both point clouds
2. Try all 8 axis reflections
3. Point-to-point ICP for each
4. Return best (lowest bidirectional mean distance) with per-point data and QA metrics

`ref_normals` — Nx3 matrix of per-vertex normals for the reference surface (for signed distance).
`tolerance`   — distance threshold for in-tolerance yield calculation.
"""
function register(scan::Matrix{Float64}, surface::Matrix{Float64};
                  ref_normals::Union{Matrix{Float64}, Nothing}=nothing,
                  tolerance::Float64=0.05)
    # PCA alignment (matches R: scale + eigen(var))
    scan_pca = pca_align(scan)
    surf_pca = pca_align(surface)

    # PCA-align the reference normals using the same eigenvector rotation
    surf_normals_pca = nothing
    if ref_normals !== nothing
        centered_surf = surface .- mean(surface, dims=1)
        C = cov(centered_surf)
        eig = eigen(C)
        rot = eig.vectors[:, end:-1:1]
        surf_normals_pca = ref_normals * rot
    end

    best_dist = Inf
    best_result = scan_pca
    best_reflection = 1
    best_ab = 0.0
    best_ba = 0.0

    # Thread all 8 reflections — each is fully independent
    tasks = map(enumerate(REFLECTIONS)) do (j, refl)
        Threads.@spawn begin
            reflected = apply_reflection(scan_pca, refl)
            registered = run_icp(surf_pca, reflected)
            dist, ab, ba = bidirectional_mean_distance(registered, surf_pca)
            @info "Reflection $j $(refl): Chamfer = $(round(dist, digits=4)) (A→B: $(round(ab, digits=4)), B→A: $(round(ba, digits=4)))"
            (j, refl, dist, ab, ba, registered)
        end
    end

    for t in tasks
        j, refl, dist, ab, ba, registered = fetch(t)
        if dist < best_dist
            best_dist = dist
            best_result = registered
            best_reflection = j
            best_ab = ab
            best_ba = ba
        end
    end

    # Compute per-point unsigned distances for visualization
    tree_surf = KDTree(surf_pca')
    idxs_scan, scan_dists = knn(tree_surf, best_result', 1)

    tree_scan = KDTree(best_result')
    _, surf_dists = knn(tree_scan, surf_pca', 1)

    # Flatten distance arrays
    scan_dist_vec = [scan_dists[i][1] for i in eachindex(scan_dists)]
    surf_dist_vec = [surf_dists[i][1] for i in eachindex(surf_dists)]

    # Combine all per-point distances for aggregate metrics
    all_dists = vcat(scan_dist_vec, surf_dist_vec)
    sd_val = std(all_dists)
    rmse_val = sqrt(mean(all_dists .^ 2))
    tem_val = sqrt(sum(all_dists .^ 2) / (2 * length(all_dists)))
    max_val = maximum(all_dists)
    max_ab = maximum(scan_dist_vec)
    max_ba = maximum(surf_dist_vec)

    # ── 95th Percentile Error ────────────────────────
    p95_ab = quantile(scan_dist_vec, 0.95)
    p95_ba = quantile(surf_dist_vec, 0.95)
    p95_bidir = quantile(all_dists, 0.95)

    # ── In-Tolerance Yield (%) ───────────────────────
    yield_pct = count(d -> d <= tolerance, scan_dist_vec) / length(scan_dist_vec) * 100

    # ── Signed Mean Distance (Scan → Reference) ─────
    signed_mean = 0.0
    scan_signed_dists = zeros(Float64, length(scan_dist_vec))
    if surf_normals_pca !== nothing
        idx_vec = [idxs_scan[i][1] for i in eachindex(idxs_scan)]
        for i in eachindex(scan_dist_vec)
            # Displacement vector from reference point to scan point
            ref_idx = idx_vec[i]
            disp = best_result[i, :] .- surf_pca[ref_idx, :]
            n_vec = surf_normals_pca[ref_idx, :]
            # Signed distance: positive = outside (bloating), negative = inside (shrinking)
            scan_signed_dists[i] = dot(disp, n_vec)
        end
        signed_mean = mean(scan_signed_dists)
    end

    return Dict(
        "status" => "complete",
        "chamferDist" => round(best_dist, digits=4),
        "bestReflection" => best_reflection,
        "meanAtoB" => round(best_ab, digits=4),
        "meanBtoA" => round(best_ba, digits=4),
        "sd" => round(sd_val, digits=4),
        "rmse" => round(rmse_val, digits=4),
        "tem" => round(tem_val, digits=4),
        "maxDist" => round(max_val, digits=4),
        "maxAtoB" => round(max_ab, digits=4),
        "maxBtoA" => round(max_ba, digits=4),
        "p95AtoB" => round(p95_ab, digits=4),
        "p95BtoA" => round(p95_ba, digits=4),
        "p95Bidir" => round(p95_bidir, digits=4),
        "signedMean" => round(signed_mean, digits=6),
        "yieldPct" => round(yield_pct, digits=1),
        "scanCoords" => vec(best_result'),
        "surfCoords" => vec(surf_pca'),
        "scanDistances" => [round(scan_dist_vec[i], digits=4) for i in eachindex(scan_dist_vec)],
        "surfDistances" => [round(surf_dist_vec[i], digits=4) for i in eachindex(surf_dist_vec)]
    )
end

end # module
