module DimensionalAnalysis

export analyze_dimensions

using LinearAlgebra
using Statistics

"""
    fit_plane(points::Matrix{Float64}) -> (normal, d, centroid, rmse, max_dev)

Fit a least-squares plane to Nx3 points using SVD of the centered coordinates.
Returns:
- `normal`   — unit normal vector of the fitted plane
- `d`        — signed distance from origin (plane eq: n·x = d)
- `centroid` — centroid of the point cluster
- `rmse`     — planarity RMSE (flatness)
- `max_dev`  — maximum absolute deviation from the plane
"""
function fit_plane(points::Matrix{Float64})
    centroid = vec(mean(points, dims=1))
    centered = points .- centroid'

    F = svd(centered)
    # The right singular vector corresponding to the smallest singular value
    # is the plane normal (direction of least variance)
    normal = F.V[:, 3]
    d = dot(normal, centroid)

    # Planarity: signed distances of each point to the fitted plane
    residuals = centered * normal
    rmse = sqrt(mean(residuals .^ 2))
    max_dev = maximum(abs.(residuals))

    return normal, d, centroid, rmse, max_dev
end

"""
    analyze_dimensions(scan_pts, surf_pts, dim_x, dim_y, dim_z; trim_pct) -> Dict

Analyze dimensional accuracy of a registered scan against known block dimensions.

After ICP registration, the scan is in the PCA-aligned reference frame where
each axis corresponds to a block dimension. This function:
1. Determines which PCA axis maps to which input dimension (by matching ranges)
2. Assigns each scan point to its nearest reference face (6 faces, Voronoi-style)
3. Fits a least-squares plane to each face cluster (with optional edge trimming)
4. Reports per-axis: measured dimension, error, parallelism, flatness, max deviation
5. Reports perpendicularity between adjacent face pairs
6. Reports volume comparison (nominal vs. measured)

Returns a Dict with keys:
- `"dimensionalAnalysis"` — per-axis metrics
- `"perpendicularity"` — adjacent face angle deviations from 90°
- `"volumeAnalysis"` — nominal vs. measured volume
"""
function analyze_dimensions(scan_pts::Matrix{Float64}, surf_pts::Matrix{Float64},
                            dim_x::Float64, dim_y::Float64, dim_z::Float64;
                            trim_pct::Float64=10.0)
    nominal_dims = [dim_x, dim_y, dim_z]
    dim_labels = ["X", "Y", "Z"]
    trim_frac = clamp(trim_pct, 0.0, 40.0) / 100.0

    # ── Step 1: Map PCA axes to input dimensions ────────────────
    ref_ranges = [maximum(surf_pts[:, k]) - minimum(surf_pts[:, k]) for k in 1:3]

    dim_order   = sortperm(nominal_dims)
    range_order = sortperm(ref_ranges)

    axis_to_dim = zeros(Int, 3)
    for i in 1:3
        axis_to_dim[range_order[i]] = dim_order[i]
    end

    # ── Step 2: Assign each scan point to its nearest face ──────
    n_scan = size(scan_pts, 1)
    face_mins = [minimum(surf_pts[:, k]) for k in 1:3]
    face_maxs = [maximum(surf_pts[:, k]) for k in 1:3]

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

    # ── Step 3: Fit planes and compute per-axis metrics ─────────
    results = Dict{String,Any}[]
    face_normals = Dict{Int, Vector{Float64}}()  # face_id => oriented normal
    measured_dims = Float64[]  # store measured dimensions for volume calc

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
                "maxDevNeg"    => 0.0,
                "maxDevPos"    => 0.0,
                "pointsNeg"    => min_count,
                "pointsPos"    => max_count,
                "valid"        => false
            ))
            push!(measured_dims, nominal)
            continue
        end

        min_face_pts = scan_pts[min_mask, :]
        max_face_pts = scan_pts[max_mask, :]

        # Trim edge/corner points
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

            if size(min_face_pts, 1) < 10 || size(max_face_pts, 1) < 10
                @warn "Insufficient points for $label after edge trimming"
                push!(results, Dict{String,Any}(
                    "axis"         => label,
                    "nominal"      => round(nominal, digits=4),
                    "measured"     => 0.0,
                    "error"        => 0.0,
                    "parallelism"  => 0.0,
                    "flatnessNeg"  => 0.0,
                    "flatnessPos"  => 0.0,
                    "maxDevNeg"    => 0.0,
                    "maxDevPos"    => 0.0,
                    "pointsNeg"    => size(min_face_pts, 1),
                    "pointsPos"    => size(max_face_pts, 1),
                    "valid"        => false
                ))
                push!(measured_dims, nominal)
                continue
            end
        end

        # Fit independent planes to each face cluster
        n_min, d_min, c_min, rmse_min, maxdev_min = fit_plane(min_face_pts)
        n_max, d_max, c_max, rmse_max, maxdev_max = fit_plane(max_face_pts)

        # Orient both normals to point in the positive PCA axis direction
        if n_min[pca_axis] < 0
            n_min = -n_min
            d_min = -d_min
        end
        if n_max[pca_axis] < 0
            n_max = -n_max
            d_max = -d_max
        end

        # Store normals for perpendicularity computation
        face_normals[min_face_id] = n_min
        face_normals[max_face_id] = n_max

        # Measured distance
        avg_normal = normalize(n_min + n_max)
        measured = abs(dot(c_max - c_min, avg_normal))
        push!(measured_dims, measured)

        # Dimension error
        error_val = measured - nominal

        # Parallelism
        cos_angle = clamp(dot(n_min, n_max), -1.0, 1.0)
        parallelism_deg = acosd(abs(cos_angle))

        @info "$label axis: nominal=$(round(nominal, digits=3)), " *
              "measured=$(round(measured, digits=4)), " *
              "error=$(round(error_val, digits=4)), " *
              "parallelism=$(round(parallelism_deg, digits=4))°, " *
              "flatness −/+ = $(round(rmse_min, digits=4))/$(round(rmse_max, digits=4)), " *
              "maxDev −/+ = $(round(maxdev_min, digits=4))/$(round(maxdev_max, digits=4))"

        push!(results, Dict{String,Any}(
            "axis"         => label,
            "nominal"      => round(nominal, digits=4),
            "measured"     => round(measured, digits=4),
            "error"        => round(error_val, digits=4),
            "parallelism"  => round(parallelism_deg, digits=4),
            "flatnessNeg"  => round(rmse_min, digits=4),
            "flatnessPos"  => round(rmse_max, digits=4),
            "maxDevNeg"    => round(maxdev_min, digits=4),
            "maxDevPos"    => round(maxdev_max, digits=4),
            "pointsNeg"    => min_count,
            "pointsPos"    => max_count,
            "valid"        => true
        ))
    end

    # Sort by axis label for consistent display (X, Y, Z)
    sort!(results, by = r -> r["axis"])

    # ── Step 4: Perpendicularity (adjacent face pairs) ──────────
    # For a rectangular block, adjacent faces should meet at 90°.
    # There are 3 axis-pair groups (XY, XZ, YZ), each with 4 edges.
    perp_results = Dict{String,Any}[]
    axis_pairs = [(1,2), (1,3), (2,3)]

    for (ax1, ax2) in axis_pairs
        label1 = dim_labels[axis_to_dim[ax1]]
        label2 = dim_labels[axis_to_dim[ax2]]
        pair_label = "$label1-$label2"

        angles = Float64[]
        for s1 in [2ax1-1, 2ax1]          # min/max faces of axis 1
            for s2 in [2ax2-1, 2ax2]      # min/max faces of axis 2
                if haskey(face_normals, s1) && haskey(face_normals, s2)
                    cos_a = clamp(abs(dot(face_normals[s1], face_normals[s2])), 0.0, 1.0)
                    angle = acosd(cos_a)   # angle between normals
                    push!(angles, angle)
                end
            end
        end

        if !isempty(angles)
            mean_dev = mean(abs.(angles .- 90.0))
            max_dev = maximum(abs.(angles .- 90.0))
            push!(perp_results, Dict{String,Any}(
                "edges"    => pair_label,
                "meanDev"  => round(mean_dev, digits=4),
                "maxDev"   => round(max_dev, digits=4),
                "valid"    => true
            ))
        end
    end

    # Sort perpendicularity by edge label
    sort!(perp_results, by = r -> r["edges"])

    # ── Step 5: Volume comparison ──────────────────────────────
    nominal_vol = dim_x * dim_y * dim_z
    measured_vol = length(measured_dims) == 3 ? prod(measured_dims) : nominal_vol
    vol_error = measured_vol - nominal_vol
    vol_error_pct = (vol_error / nominal_vol) * 100.0

    volume_result = Dict{String,Any}(
        "nominal"   => round(nominal_vol, digits=2),
        "measured"  => round(measured_vol, digits=2),
        "error"     => round(vol_error, digits=2),
        "errorPct"  => round(vol_error_pct, digits=3)
    )

    @info "Volume: nominal=$(round(nominal_vol, digits=2)), " *
          "measured=$(round(measured_vol, digits=2)), " *
          "error=$(round(vol_error, digits=2)) ($(round(vol_error_pct, digits=3))%)"

    return Dict{String,Any}(
        "dimensionalAnalysis" => results,
        "perpendicularity"    => perp_results,
        "volumeAnalysis"      => volume_result
    )
end

end # module
