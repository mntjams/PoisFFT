#!/bin/bash

set -ueo pipefail

NODE="bw01"
CORES=48

srun -p gpu-ffa-gpulab -N 1 --ntasks-per-node 1 -w "$NODE" -c "$CORES" --threads-per-core=1 -t 12:00:00 ch-run -b mapped:/opt/build imgdir -- /bin/bash -c "cd /opt/build/PoisFFT && ./local_benchmarks.sh ./bin/gcc/results/cores_${CORES}"
