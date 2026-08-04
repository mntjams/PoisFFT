#!/bin/bash

set -ueo pipefail

NODE="volta05"

srun -p gpu-short-teach -N 1 --ntasks-per-node 1 -w "$NODE" -c 16 ch-run -b mapped:/opt/build imgdir -- /bin/bash -c "cd /opt/build/PoisFFT && ./local_benchmarks.sh"
