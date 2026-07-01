#!/usr/bin/env bash

curl https://raw.githubusercontent.com/tristanisham/zvm/master/install.sh | bash

VERSION=0.16.0
$HOME/.zvm/self/zvm i $VERSION
$HOME/.zvm/self/zvm use $VERSION

make net
$HOME/.zvm/$VERSION/zig build --release=fast
cp ./zig-out/bin/pawnocchio .

