# Precompile script for sysimage — exercises key code paths
using Genie
using HTTP
using JSON3
using LinearAlgebra
using MultivariateStats
using NearestNeighbors
using Statistics

# Force compilation of commonly used functions
JSON3.read("{\"test\": 1}")
