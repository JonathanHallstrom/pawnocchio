echo $1
zig build-exe -OReleaseFast -fomit-frame-pointer -mcpu=znver5 src/datagen.zig
for i in $(seq 1 $1); do
    echo starting $i
    ./datagen -o out$i.vf -g 3000_000 -n 5000 -r 6 &
done
wait