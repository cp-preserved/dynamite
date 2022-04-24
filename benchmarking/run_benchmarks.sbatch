#!/bin/bash
#SBATCH -N 1
#SBATCH -n 4
#SBATCH -p GPU-shared
#SBATCH -o /jet/home/juliawei/dyn/dynamite/benchmarking/results/benchmark-%j.out
#SBATCH -e /jet/home/juliawei/dyn/dynamite/benchmarking/results/benchmark-%j.err
#SBATCH -t 00:15:00
#SBATCH --gres=gpu:4


mpirun -np 1 python benchmark.py -L 25 -H ising --gpu --shell --mult --mult_count 10

mpirun -np 2 python benchmark.py -L 25 -H ising --gpu --shell --mult --mult_count 10

mpirun -np 4 python benchmark.py -L 25 -H ising --gpu --shell --mult --mult_count 10

