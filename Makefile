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

net:
	-git submodule update --init --recursive --depth 1

ifdef EVALFILE
NET_SPECIFIER=-Dnet=$(EVALFILE)
else
NET_SPECIFIER=
endif

default: net
	zig build --release=safe install $(NET_SPECIFIER)
	@$(MV)
