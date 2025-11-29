#!/usr/bin/bash

curl https://raw.githubusercontent.com/tristanisham/zvm/master/install.sh | bash

VERSION=0.15.2
$HOME/.zvm/self/zvm i $VERSION
$HOME/.zvm/$VERSION/zig build --release=fast
cp ./zig-out/bin/pawnocchio .

