# pawnocchio

Strongest UCI Chess engine written in zig

## Strength

|         Version         | [CCRL 40/15][ccrl 40/15] | [CCRL Blitz][ccrl Blitz] |
|:-----------------------:|:------------------------:|:-------------------------:
| [1.6][v1.6]             |           3500*          |           3600*          |
| [1.5][v1.5]             |           3450*          |           3500           |
| [1.4.1][v1.4.1]         |           3425           |           3450*          |
| [1.3.1415][v1.3.1415]   |           3365           |           3401           |
| [1.3][v1.3]             |           3201           |           3230*          |
| [1.2][v1.2]             |           3120           |           3150*          |
| [1.1][v1.1]             |           2432           |           2450*          |
| [1.0][v1.0]             |           2100*          |           2150*          |

*estimated

## Features
Supports FRC, also known as Chess960
### Search
The search is a standard alpha-beta search with the following enhancements:
- Iterative deepening
- Quiescence search
- Aspiration windows
- Principal variation search
- Transposition table
  - Move ordering
  - Cutoffs
  - Static evaluation correction
- MVV and SEE ordering of captures
- History Heuristic (standard history, 1 ply conthist, and noisy history) 
- Reverse futility pruning
- Null move pruning
- Razoring
- Mate distance pruning
- History pruning
- Singular extensions
  - Double extension
  - Multicut
  - Negative extensions
- Correction history

### Evaluation
The evaluation is done using a neural net trained entirely on self play games from zero knowledge using the excellent open source [bullet](https://github.com/jw1912/bullet) neural network trainer.
The architecture of the network is (768x8hm -> 1024)x2 -> 1x8

## Build instructions
1. Install zig (0.14.0)
2. `zig build --release=fast --prefix <installation path>` (for example `--prefix ~/.local` will put pawnocchio in `~/.local/bin/pawnocchio`)

[v1.0]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.0
[v1.1]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.1
[v1.2]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.2
[v1.3]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.3
[v1.3.1415]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.3.1415
[v1.4]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.4
[v1.4.1]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.4.1
[v1.5]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.5
[v1.6]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.6

[ccrl 40/15]:https://www.computerchess.org.uk/ccrl/4040/cgi/compare_engines.cgi?family=pawnocchio
[ccrl Blitz]:https://www.computerchess.org.uk/ccrl/404/cgi/compare_engines.cgi?family=pawnocchio
