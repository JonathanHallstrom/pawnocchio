echo $1
zig build-exe -OReleaseFast src/datagen.zig
for i in $(seq 1 $1); do
    echo starting $i
    ./datagen -o out$i.vf -g 3000_000 -n 5000 -r 4 &
done
wait