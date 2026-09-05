#!/bin/bash

set -ueo pipefail

# Format: NODES, TASKS, NPS_Y, NPS_Z, NODE_NAMES, NODES_SATURATED
# NPS_Y and NPS_Z are MPI grid divisions passed to the solver.
# votla04 is currently down and we need at least 2 GPUs per node
# with poisson-solver (and mirror this config here) so volta01 cannot be used
CONFIGS=(
    "1 8 2 4 volta05 0.25"
    "1 16 4 4 volta05 0.5"
    "1 32 4 8 volta05 1"
    "2 48 4 12 volta[02,05] 2"
    "3 64 8 8 volta[02,03,05] 3"
)

# Only allocate and run strong_scaling_benchmarks locally,
# that script will then call the benchmarks using srun
for cfg in "${CONFIGS[@]}"; do
    CFG_ARR=(${cfg})
    NUM_NODES=${CFG_ARR[0]}
    NTASKS=${CFG_ARR[1]}
    NPS_Y=${CFG_ARR[2]}
    NPS_Z=${CFG_ARR[3]}
    NODES=${CFG_ARR[4]}

    # Currently unused
    NODES_SATURATED=${CFG_ARR[5]}

    # No multithreading
    salloc -p gpu-ffa-gpulab -c 1 --mem-per-cpu=4G --threads-per-core=1 -N $NUM_NODES -n $NTASKS -w "$NODES" -t 12:00:00 ./mapped/PoisFFT/strong_scaling_benchmarks.sh $NUM_NODES $NTASKS $NPS_Y $NPS_Z "./bin/gcc/results/strong_scaling/"
done
