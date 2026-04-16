module DimensionalAnalysis

export analyze_dimensions

using LinearAlgebra
using Statistics

"""
    fit_plane(points::Matrix{Float64}) -> (normal, d, centroid, rmse)

Fit a least-squares plane to Nx3 points using SVD of the centered coordinates.
Returns:
- `normal`   — unit normal vector of the fitted plane
- `d`        — signed distance from origin (plane eq: n·x = d)
- `centroid` — centroid of the point cluster
- `rmse`     — planarity RMSE (flatness)
"""
function fit_plane(points::Matrix{Float64})
    centroid = vec(mean(points, dims=1))
    centered = points .- centroid'

    F = svd(centered)
    # The right singular vector corresponding to the smallest singular value
    # is the plane normal (direction of least variance)
    normal = F.V[:, 3]
    d = dot(normal, centroid)

    # Planarity RMSE: signed distances of each point to the fitted plane
    residuals = centered * normal
    rmse = sqrt(mean(residuals .^ 2))

    return normal, d, centroid, rmse
end

"""
    analyze_dimensions(scan_pts, surf_pts, dim_x, dim_y, dim_z) -> Dict

Analyze dimensional accuracy of a registered scan against known block dimensions.

After ICP registration, the scan is in the PCA-aligned reference frame where
each axis corresponds to a block dimension. This function:
1. Determines which PCA axis maps to which input dimension (by matching ranges)
2. Assigns each scan point to its nearest reference face (6 faces, Voronoi-style)
3. Fits a least-squares plane to each face cluster
4. Reports per-axis: measured dimension, error, parallelism angle, and face flatness

Returns a Dict with key `"dimensionalAnalysis"` containing a vector of per-axis results.
"""
function analyze_dimensions(scan_pts::Matrix{Float64}, surf_pts::Matrix{Float64},
                            dim_x::Float64, dim_y::Float64, dim_z::Float64;
                            trim_pct::Float64=10.0)
    nominal_dims = [dim_x, dim_y, dim_z]
    dim_labels = ["X", "Y", "Z"]
    trim_frac = clamp(trim_pct, 0.0, 40.0) / 100.0

    # ── Step 1: Map PCA axes to input dimensions ────────────────
    # After PCA alignment, the reference surface spans some range along each axis.
    # Match these ranges to the known dimensions to determine the mapping.
    ref_ranges = [maximum(surf_pts[:, k]) - minimum(surf_pts[:, k]) for k in 1:3]

    dim_order   = sortperm(nominal_dims)   # indices that sort dims ascending
    range_order = sortperm(ref_ranges)     # indices that sort ranges ascending

    axis_to_dim = zeros(Int, 3)  # axis_to_dim[pca_axis] = dim_index (1=X, 2=Y, 3=Z)
    for i in 1:3
        axis_to_dim[range_order[i]] = dim_order[i]
    end

    # ── Step 2: Assign each scan point to its nearest face ──────
    # 6 faces defined by reference surface extents along each PCA axis
    n_scan = size(scan_pts, 1)
    face_mins = [minimum(surf_pts[:, k]) for k in 1:3]
    face_maxs = [maximum(surf_pts[:, k]) for k in 1:3]

    # assignments[i] = face id (1..6)
    #   odd  = min face for axis (2k-1 → axis k, min side)
    #   even = max face for axis (2k   → axis k, max side)
    assignments = Vector{Int}(undef, n_scan)

    for i in 1:n_scan
        min_dist = Inf
        best_face = 0
        for k in 1:3
            d_min = abs(scan_pts[i, k] - face_mins[k])
            d_max = abs(scan_pts[i, k] - face_maxs[k])
            if d_min < min_dist
                min_dist = d_min
                best_face = 2k - 1
            end
            if d_max < min_dist
                min_dist = d_max
                best_face = 2k
            end
        end
        assignments[i] = best_face
    end

    # ── Step 3–4: Fit planes and compute metrics per axis pair ──
    results = Dict{String,Any}[]

    for pca_axis in 1:3
        dim_idx = axis_to_dim[pca_axis]
        nominal = nominal_dims[dim_idx]
        label   = dim_labels[dim_idx]

        min_face_id = 2 * pca_axis - 1
        max_face_id = 2 * pca_axis

        min_mask = assignments .== min_face_id
        max_mask = assignments .== max_face_id

        min_count = count(min_mask)
        max_count = count(max_mask)

        if min_count < 10 || max_count < 10
            @warn "Insufficient points for $label face pair (min=$min_count, max=$max_count)"
            push!(results, Dict{String,Any}(
                "axis"         => label,
                "nominal"      => round(nominal, digits=4),
                "measured"     => 0.0,
                "error"        => 0.0,
                "parallelism"  => 0.0,
                "flatnessNeg"  => 0.0,
                "flatnessPos"  => 0.0,
                "pointsNeg"    => min_count,
                "pointsPos"    => max_count,
                "valid"        => false
            ))
            continue
        end

        min_face_pts = scan_pts[min_mask, :]
        max_face_pts = scan_pts[max_mask, :]

        # Trim edge/corner points: exclude points within trim_pct% of the
        # face boundary along the other two axes to avoid rounded edge contamination
        if trim_frac > 0
            other_axes = setdiff(1:3, pca_axis)
            for oa in other_axes
                span = face_maxs[oa] - face_mins[oa]
                margin = trim_frac * span
                lo = face_mins[oa] + margin
                hi = face_maxs[oa] - margin
                min_keep = [lo <= min_face_pts[i, oa] <= hi for i in 1:size(min_face_pts, 1)]
                max_keep = [lo <= max_face_pts[i, oa] <= hi for i in 1:size(max_face_pts, 1)]
                min_face_pts = min_face_pts[min_keep, :]
                max_face_pts = max_face_pts[max_keep, :]
            end

            # Re-check point counts after trimming
            if size(min_face_pts, 1) < 10 || size(max_face_pts, 1) < 10
                @warn "Insufficient points for $label face pair after edge trimming ($(size(min_face_pts,1))/$(size(max_face_pts,1)))"
                push!(results, Dict{String,Any}(
                    "axis"         => label,
                    "nominal"      => round(nominal, digits=4),
                    "measured"     => 0.0,
                    "error"        => 0.0,
                    "parallelism"  => 0.0,
                    "flatnessNeg"  => 0.0,
                    "flatnessPos"  => 0.0,
                    "pointsNeg"    => size(min_face_pts, 1),
                    "pointsPos"    => size(max_face_pts, 1),
                    "valid"        => false
                ))
                continue
            end
        end

        # Fit independent planes to each face cluster
        n_min, d_min, c_min, rmse_min = fit_plane(min_face_pts)
        n_max, d_max, c_max, rmse_max = fit_plane(max_face_pts)

        # Orient both normals to point in the positive PCA axis direction
        if n_min[pca_axis] < 0
            n_min = -n_min
            d_min = -d_min
        end
        if n_max[pca_axis] < 0
            n_max = -n_max
            d_max = -d_max
        end

        # Measured distance: project inter-centroid vector onto average normal
        avg_normal = normalize(n_min + n_max)
        measured = abs(dot(c_max - c_min, avg_normal))

        # Dimension error (positive = scan is larger than nominal)
        error_val = measured - nominal

        # Parallelism: angle between face normals (0° = perfectly parallel)
        cos_angle = clamp(dot(n_min, n_max), -1.0, 1.0)
        parallelism_deg = acosd(abs(cos_angle))

        @info "$label axis: nominal=$(round(nominal, digits=3)), " *
              "measured=$(round(measured, digits=4)), " *
              "error=$(round(error_val, digits=4)), " *
              "parallelism=$(round(parallelism_deg, digits=4))°, " *
              "flatness −/+ = $(round(rmse_min, digits=4))/$(round(rmse_max, digits=4))"

        push!(results, Dict{String,Any}(
            "axis"         => label,
            "nominal"      => round(nominal, digits=4),
            "measured"     => round(measured, digits=4),
            "error"        => round(error_val, digits=4),
            "parallelism"  => round(parallelism_deg, digits=4),
            "flatnessNeg"  => round(rmse_min, digits=4),
            "flatnessPos"  => round(rmse_max, digits=4),
            "pointsNeg"    => min_count,
            "pointsPos"    => max_count,
            "valid"        => true
        ))
    end

    # Sort by axis label for consistent display (X, Y, Z)
    sort!(results, by = r -> r["axis"])

    return Dict{String,Any}("dimensionalAnalysis" => results)
end

end # module
