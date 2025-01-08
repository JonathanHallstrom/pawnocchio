# inspired by https://github.com/SnowballSH/Avalanche/blob/c44569afbee44716e18a9698430c1016438d3874/Makefile

.DEFAULT_GOAL := default

ifndef EXE
EXE=pawnocchio
endif
ifeq ($(OS),Windows_NT)
MV=move .\zig-out\bin\pawnocchio.exe $(EXE).exe
else
MV=mv ./zig-out/bin/pawnocchio $(EXE)
endif

default:
	zig build --release=fast install
	@$(MV)