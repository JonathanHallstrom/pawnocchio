zig build-exe -OReleaseFast src/datagen.zig
time bash -c 'for i in {1..32}; do
    ./datagen -o out$i.vf -g 100 -n 5000 -r 4 &
done
wait'
for i in {1..32}; do
    echo out$i.bin
    /home/jonathanhallstrom/dev/rust/viridithas/target/release/viridithas splat ~/dev/zig/pawnocchio/out$i.vf out$i.bin
done