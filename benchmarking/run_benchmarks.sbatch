#!/bin/bash
#SBATCH -N 1
#SBATCH -n 4
#SBATCH -p GPU-shared
#SBATCH -o /jet/home/juliawei/dyn/dynamite/benchmarking/results/benchmark-opt1-%j.out
#SBATCH -e /jet/home/juliawei/dyn/dynamite/benchmarking/results/benchmark-opt1-%j.err
#SBATCH -t 01:00:00
#SBATCH --gres=gpu:4

source /jet/home/juliawei/dyn/load_dyn32.sh

for L in 18 20 22 24 26 28
do
	echo "For L = $L"
	for nproc in 1 2 4
	do

		mpirun -np $nproc python benchmark.py -L $L -H SYK --gpu --shell --mult --mult_count 10
	done
done

