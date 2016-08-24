#!/bin/bash

git clone https://github.com/marcomaggi/vicare.git

cd vicare
mkdir -p build
sh autogen.sh
cd build
../configure --enable-maintainer-mode
make -j8
sudo make install
