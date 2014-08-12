#!/usr/bin/env sh
rm assets/bank1.dat
rm assets/bank1.ptr
./insert.py
make clean
make

