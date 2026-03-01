## Precompile workload for PackageCompiler sysimage
## Exercises hot paths so they're AOT-compiled into the sysimage

using JSON3

# JSON round-trip (sidecar protocol)
json_str = JSON3.write(Dict("command" => "fileinfo", "filepath" => "/tmp/test.xyzrgb"))
JSON3.read(json_str, Dict{String,Any})

# === ICP / Scientific packages ===
using NearestNeighbors
using Statistics
using MultivariateStats
using LinearAlgebra

# KD-tree operations (hot path in ICP)
pts = rand(3, 500)
tree = KDTree(pts)
knn(tree, pts[:, 1], 10)

# Linear algebra (used in rigid body transforms)
A = rand(6, 6)
b = rand(6)
A \ b

M = rand(4, 4)
inv(M)
det(M)

# Statistics (used in convergence checks)
data = rand(100)
mean(data)
std(data)

# Covariance + eigen (used in PCA alignment)
C = cov(rand(3, 10), dims=2)
eigen(C)

# PCA-style operations
fit(PCA, rand(3, 50))

println("Precompilation workload complete")
