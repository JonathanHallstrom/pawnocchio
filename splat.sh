echo $1
for i in $(seq 1 $1); do
    rm -fr tmp$i.bin
    (/home/jonathanhallstrom/dev/rust/viridithas/target/release/viridithas splat --cfg-path=4pc.toml --pgn ~/dev/zig/pawnocchio/out$i.vf tmp$i.bin && 
     /home/jonathanhallstrom/dev/rust/viridithas/target/release/viridithas splat --cfg-path=4pc.toml ~/dev/zig/pawnocchio/out$i.vf out$i.bin) &
done
wait
for i in $(seq 1 $1); do
    rm -fr tmp$i.bin
done

for i in $(seq 1 $1); do
    /home/jonathanhallstrom/dev/rust/bullet/target/release/bullet-utils shuffle --mem-used-mb 1024 --input out$i.bin --output shuffled$i.bin
done


/home/jonathanhallstrom/dev/rust/bullet/target/release/bullet-utils interleave shuffled?*bin --output shuffled.bin
