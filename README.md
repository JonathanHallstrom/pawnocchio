# pawnocchio

~2100 ELO CCRL based on play against [stash-bot](https://gitlab.com/mhouppin/stash-bot)

A/B, iterative deepening, qsearch, mvv-lva, pvs

## TODO
- lmr (loglog?)
- history

## Build instructions
1. Install zig (0.13.0)
2. `zig build --release=fast --prefix <installation path>` (for example `--prefix ~/.local` will put pawnocchio in `~/.local/bin/pawnocchio`)
