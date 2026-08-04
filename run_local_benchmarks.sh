#!/bin/bash

set -ueo pipefail

NODE="volta05"

for CORES in 1 2 4 8 16 32 64; do
    echo "=========================================================="
    echo "Starting PoisFFT benchmarks with ${CORES} cores..."
    echo "=========================================================="

    srun -p gpu-short-teach -N 1 --ntasks-per-node 1 -w "$NODE" -c "$CORES" ch-run -b mapped:/opt/build imgdir -- /bin/bash -c "cd /opt/build/PoisFFT && ./local_benchmarks.sh ./bin/gcc/results/cores_${CORES}"
done

echo "All multi-core sweeps completed for PoisFFT."
