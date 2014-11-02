#!/usr/bin/env sh

set -e

# clone the repository
git clone https://github.com/manz/ff4.git ff4
cd ff4

# create the python 3 virtualenv
virtualenv VE_ff4 -p `python3.4-config --exec-prefix`/bin/python3.4

# install dependencies
source VE_ff4/bin/activate
pip install -r requirements.txt

# build the patch ?
python3.4 build.py
