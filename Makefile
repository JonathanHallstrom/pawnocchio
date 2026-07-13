# inspired by https://github.com/SnowballSH/Avalanche/blob/c44569afbee44716e18a9698430c1016438d3874/Makefile

.DEFAULT_GOAL := default

ifndef EXE
EXE=pawnocchio
endif

ifeq ($(OS),Windows_NT)
MV=move .\zig-out\bin\pawnocchio.exe $(EXE).exe
RM=del /q
RM_DIR=rd /s /q
else
MV=mv ./zig-out/bin/pawnocchio $(EXE)
RM=rm -f
RM_DIR=rm -rf
endif

DEFAULT_NET=pp_big5.nnue
NET_URL=https://github.com/JonathanHallstrom/pawnocchio-nets/releases/download/$(DEFAULT_NET)/$(DEFAULT_NET)

ifndef EVALFILE
EVALFILE=$(DEFAULT_NET)
endif

$(DEFAULT_NET):
	wget -O $(DEFAULT_NET) $(NET_URL)

.PHONY: net default clean

net: $(DEFAULT_NET)

default: $(EVALFILE)
	zig build --release=fast install -Dnet=$(EVALFILE)
	@$(MV)

clean:
	-$(RM_DIR) .zig-cache zig-cache zig-out
	-$(RM) $(DEFAULT_NET)
