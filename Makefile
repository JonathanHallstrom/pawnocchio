# inspired by https://github.com/SnowballSH/Avalanche/blob/c44569afbee44716e18a9698430c1016438d3874/Makefile

.DEFAULT_GOAL := default

ifndef EXE
EXE=pawnocchio
endif

default:
	zig build --release=fast install

	mv ./zig-out/bin/pawnocchio $(EXE)
