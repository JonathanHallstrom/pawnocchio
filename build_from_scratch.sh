#!/usr/bin/bash

curl https://raw.githubusercontent.com/tristanisham/zvm/master/install.sh | bash

VERSION=0.14.1
$HOME/.zvm/self/zvm i $VERSION
$HOME/.zvm/self/zvm use $VERSION

git submodule update --init --recursive --depth 1
$HOME/.zvm/$VERSION/zig build --release=fast
cp ./zig-out/bin/pawnocchio .

