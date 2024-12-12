# inspired by https://github.com/SnowballSH/Avalanche/blob/c44569afbee44716e18a9698430c1016438d3874/Makefile

.DEFAULT_GOAL := default

MV=mv ./zig-out/bin/$(EXE) .

default:
	zig build --release=fast -Dname=$(EXE) install

ifdef EXE
	$(MV)
endif