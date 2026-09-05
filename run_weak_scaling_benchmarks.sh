#!/bin/bash

set -ueo pipefail

# Format: NODES, TASKS, NPS_Y, NPS_Z, NODE_NAMES, GRID_SIZE, NODES_SATURATED
# We scale the global GRID_SIZE so that the local grid elements per NODE remains constant.
CONFIGS=(
    "1 8 2 4 volta05 161 0.25"
    "1 16 4 4 volta05 203 0.5"
    "1 32 4 8 volta05 256 0.5 1"
    "2 48 4 12 volta[02,05] 323 2"
    "3 64 8 8 volta[02,03,05] 369 3"
)

# Only allocate and run weak_scaling_benchmarks locally,
# that script will then call the benchmarks using srun
for cfg in "${CONFIGS[@]}"; do
    CFG_ARR=(${cfg})
    NUM_NODES=${CFG_ARR[0]}
    NTASKS=${CFG_ARR[1]}
    NPS_Y=${CFG_ARR[2]}
    NPS_Z=${CFG_ARR[3]}
    NODES=${CFG_ARR[4]}
    GRID_SIZE=${CFG_ARR[5]}

    # Currently unused
    NODES_SATURATED=${CFG_ARR[5]}

    # No multithreading
    salloc -p gpu-ffa-gpulab -c 1 --threads-per-core=1 -N $NUM_NODES -n $NTASKS -w "$NODES" -t 12:00:00 ./mapped/PoisFFT/weak_scaling_benchmarks.sh $NUM_NODES $NTASKS $NPS_Y $NPS_Z $GRID_SIZE "./bin/gcc/results/weak_scaling/"
done
