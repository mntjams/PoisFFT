#!/bin/bash

set -ueo pipefail

NUM_NODES=$1
NTASKS_PER_NODE=$2
NPS_Y=$3
NPS_Z=$4

EXEC_DIR="./bin/gcc"
EXEC="${EXEC_DIR}/benchmark_mpi"

RESULT_DIR=$5

# Benchmark parameters
ITERS=30
GRID_START=512
GRID_END=512
# Not used, start == end
GRID_STEP=64

BCS_3D=(
    "P P P P P P"
    "D D D D D D"
    "N N N N N N"
    "DS DS DS DS DS DS"
    "NS NS NS NS NS NS"
    "P P P P NS NS"
    "P P P P DS DS"
    "P P P P DS NS"
    "P P P P NS DS"
    "P P P P D N"
    "P P P P N D"
    "P P NS NS NS NS"
)

mkdir -p "mapped/PoisFFT/$RESULT_DIR"

# Default is ucx for poisson-solver
export OMPI_MCA_pml=ob1

for prec in "float" "double"; do
    dim=3
    bcs=("${BCS_3D[@]}")
    nonuniform_vals=("no" "yes")

    for nonunif_val in "${nonuniform_vals[@]}"; do
        nonunif_str=$([ "$nonunif_val" = "yes" ] && echo "nonuniform-z" || echo "uniform")

        # nonuniform-z solver has a special set of allowed bcs
        if [ "$nonunif_val" = "yes" ]; then
            current_bcs=("P P P P NS NS" "NS NS NS NS NS NS")
        else
            current_bcs=("${bcs[@]}")
        fi

        for bc_args in "${current_bcs[@]}"; do
            # Strip spaces from BCs for the filename
            bc_name=$(echo "$bc_args" | tr -d ' ')

            OUT_FILE="${RESULT_DIR}/poisfft_distributed_${prec}_dim${dim}_${nonunif_str}_${bc_name}_N${NUM_NODES}_T${NTASKS_PER_NODE}.csv"

            if [ -f "mapped/PoisFFT/${OUT_FILE}" ]; then
                echo "Skipping $OUT_FILE (Already completed)"
                continue
            fi

            echo "=========================================================="
            echo "Running... Precision: $prec | Dim: $dim | NonuniformZ: $nonunif_val | BCs: $bc_args"

            # Charliecloud probably has some race condition that makes all processes in one socket fail (the others hang waiting for MPI sync)
            # This sleep is an ugly hotfix to that problem
            srun --mpi=pmix bash -c "sleep \$((SLURM_PROCID % 16)); exec ch-run -b mapped:/opt/build imgdir -- /bin/bash -c \"cd /opt/build/PoisFFT && $EXEC $prec $dim $nonunif_val $ITERS $GRID_START $GRID_END $GRID_STEP $OUT_FILE $NPS_Y $NPS_Z $bc_args\""

            echo "Finished, result in $OUT_FILE"
        done
    done
done

echo "All benchmarks completed."
