#!/bin/bash


for L in 18 20 22 24 26 28
do
	echo "For L = $L"
	for nproc in 1 2 3
	do

		mpirun -np $nproc python benchmark.py -L $L -H SYK --gpu --shell --mult --mult_count 10
	done
done


