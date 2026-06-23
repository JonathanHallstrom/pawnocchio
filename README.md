<div align="center">

<img
  width="250"
  alt="Pawnocchio Logo"
  src="assets/main_pawnocchio-A.png">
 
<h3>pawnocchio</h3>
<b>Strongest UCI chess engine written in zig</b>

<br>
<br>

|         Version         | Release Date | [CCRL 40/15][ccrl 40/15] | [CCRL Blitz][ccrl Blitz] | [CEGT 40/20][cegt 40/20] | [ipman r9 list][ipman 10+1] | [Chess324 Top15][324top15]  |    [SP-CC Top 15 ][spcc]    |
|:-----------------------:|:------------:|:------------------------:|:------------------------:|:------------------------:|:---------------------------:|:---------------------------:|:---------------------------:|
| [1.9][v1.9]             |  2026-01-04  |           3587 (#10)     |           3727 (#13)     |           3569 (#11)     |             3537 (#20**)    |          3734 (#8)          |           3680 (#14)        |
| [1.8][v1.8]             |  2025-07-22  |           3564 (#20)     |           3697 (#16)     |           3544 (#18)     |             3517            |          3680 (#12)         |
| [1.7][v1.7]             |  2025-05-31  |           3528           |           3642           |           3491           |             3448            |
| [1.6.1][v1.6.1]         |  2025-05-15  |           3500*          |           3622           |           3440*          |
| [1.6][v1.6]             |  2025-04-27  |           3490           |           3600*          |           3433           |
| [1.5][v1.5]             |  2025-04-18  |           3450*          |           3500           |           3350           |
| [1.4.1][v1.4.1]         |  2025-04-05  |           3425           |           3450*          |
| [1.3.1415][v1.3.1415]   |  2025-03-14  |           3365           |           3401           |
| [1.3][v1.3]             |  2025-03-07  |           3201           |
| [1.2][v1.2]             |  2025-02-21  |           3120           |
| [1.1][v1.1]             |  2025-01-24  |           2432           |
| [1.0][v1.0]             |  2025-01-20  |           2100*          |

</div>
*estimated

**#12 if you only keep 1 version per engine

## Features
Supports FRC, also known as Chess960
### Search
The search is a standard alpha-beta search with many enhancements.

### Evaluation
The evaluation is done using a neural net trained on self play games from zero knowledge, as well as games played by [Vine](https://github.com/vine-chess/vine), the MCTS Chess engine that [@aronpetko](https://github.com/aronpetko) and I have been working on.
The networks are trained using the excellent open source [bullet](https://github.com/jw1912/bullet) neural network trainer. For specifics about the network please see [src/nnue.zig](src/nnue.zig).

## Build instructions
1. Get the network with `git submodule update --init --depth 1`
2. Install zig (0.15.2)
3. `zig build --release=fast --prefix <installation path>` (for example `--prefix ~/.local` will put pawnocchio in `~/.local/bin/pawnocchio`)
The Makefile is only intended to be used for testing on Openbench.

## Licensing
 - The code is licensed under the GPLv3 license. Full text can be found in LICENSE in the project root
 - The assets are licensed under the CC-BY-ND 4.0 license. Full text can be found in assets/LICENSE

## Credit
 - Many strong open source chess engines, but above all [Stormphrax](https://github.com/Ciekce/Stormphrax/) has been a massive source of inspiration
 - [Pyrrhic](https://github.com/JonathanHallstrom/Pyrrhic/tree/patch-1) by [Andrew Grant](https://github.com/AndyGrant) for tablebase probing, under the MIT license.
 - [src/bounded_array.zig](src/bounded_array.zig) from the [zig standard library](https://github.com/ziglang/zig/blob/6d1f0eca773e688c802e441589495b7bde2f9e3f/lib/std/bounded_array.zig) under the MIT License with some minor modifications.
 - [Jackal](https://github.com/TomaszJaworski777/Jackal) by [snekkers](https://github.com/TomaszJaworski777) for inspiration for styling this readme

[v1.0]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.0
[v1.1]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.1
[v1.2]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.2
[v1.3]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.3
[v1.3.1415]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.3.1415
[v1.4]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.4
[v1.4.1]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.4.1
[v1.5]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.5
[v1.6]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.6
[v1.6.1]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.6.1
[v1.7]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.7
[v1.7.2]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.7.2
[v1.8]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.8
[v1.9]:https://github.com/JonathanHallstrom/pawnocchio/releases/tag/v1.9

[324top15]:https://e4e6.com/324/
[ccrl 40/15]:https://www.computerchess.org.uk/ccrl/4040/cgi/compare_engines.cgi?family=pawnocchio
[ccrl Blitz]:https://www.computerchess.org.uk/ccrl/404/cgi/compare_engines.cgi?family=pawnocchio
[cegt 40/20]:http://www.cegt.net/40_40%20Rating%20List/40_40%20SingleVersion/rangliste.html
[ipman 10+1]:https://ipmanchess.yolasite.com/r9-7945hx.php
[spcc]:https://www.sp-cc.de/
