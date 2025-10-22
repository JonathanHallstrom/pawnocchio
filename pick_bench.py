#!/usr/bin/env python3
import sys
import random
from collections import defaultdict
import chess

TARGET = 100 

def safe_piececount(fen: str) -> int | None:
    try:
        board = chess.Board(fen)
        return len(board.piece_map())
    except Exception:
        return None

def main():
    # Read from file or stdin
    if not sys.stdin.isatty():
        lines = sys.stdin.read().splitlines()
    else:
        with open("fens.txt") as f:
            lines = f.read().splitlines()

    fens = [ln.strip() for ln in lines if ln.strip()]
    groups = defaultdict(list)

    for fen in fens:
        pc = safe_piececount(fen)
        if pc is not None:
            groups[pc].append(fen)

    if not groups:
        print("No valid FENs parsed.", file=sys.stderr)
        sys.exit(1)

    pcs = sorted(groups.keys())
    total = sum(len(v) for v in groups.values())
    need = min(TARGET, total)
    k = len(pcs)

    base, extra = divmod(need, k)
    targets = {pc: base + (i < extra) for i, pc in enumerate(pcs)}

    selected = []
    for pc in pcs:
        random.shuffle(groups[pc])
        selected.extend(groups[pc][:targets[pc]])

    remaining = need - len(selected)
    if remaining > 0:
        pool = [fen for pc in pcs for fen in groups[pc][targets[pc]:]]
        random.shuffle(pool)
        selected.extend(pool[:remaining])

    for s in sorted(selected[:need]):
        print(s)

if __name__ == "__main__":
    main()
