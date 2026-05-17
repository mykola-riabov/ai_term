#!/bin/sh
#
# Compile & Install Aiterm build dependencies
#
set -e
set -x
export LANG=C.UTF-8

mkdir -p _aiterm-deps && cd _aiterm-deps

# GtkD
git clone --depth 1 --branch=v3.11.0 https://github.com/gtkd-developers/GtkD.git gtkd
cd gtkd/

make -j"$(nproc)" \
    shared \
		prefix=/usr

make -j"$(nproc)" \
		install-shared \
		install-headers \
		prefix=/usr

cd ../

# cleanup
cd .. && rm -rf _aiterm-deps
