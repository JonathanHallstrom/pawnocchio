#! /usr/bin/python3

# https://github.com/folkertvanheusden/Dog/blob/master/app/src/linux-windows/build/matefinder.py
# written by folkert van heusden
# mit license

import chess
import chess.engine
import getopt
import psutil
import sys
import time
from multiprocessing import Process, Queue

    
epd_file = None
proc = None
time_limit = 0.5
num_procs = psutil.cpu_count()

def help():
    print('-f x  epd file to process')
    print('-e x  chess-program (UCI) to test')
    print(f'-t x  time limit per move (in seconds, default: {time_limit})')
    print(f'-T n  number of threads (default: {num_procs})')
    print('-h    this help')

try:
    opts, args = getopt.getopt(sys.argv[1:], 'f:e:t:T:h')

except getopt.GetoptError as err:
    print(err)
    help()
    sys.exit(2)

for o, a in opts:
    if o == '-f':
        epd_file = a
    elif o == '-e':
        proc = a
    elif o == '-t':
        time_limit = float(a)
    elif o == '-T':
        num_procs = int(a)
    elif o == '-h':
        help()
        sys.exit(0)

if epd_file == None or proc == None:
    help()
    sys.exit(1)

def do_it(q_in, q_out):
    engine = chess.engine.SimpleEngine.popen_uci(proc)

    while True:
        msg = q_in.get()
        if msg == None:
            break

        try:
            b = chess.Board(msg)

            result = engine.play(b, chess.engine.Limit(time=time_limit), info=chess.engine.INFO_SCORE)

            score = result.info['score'].white()
            if score.is_mate() or abs(score.score()) > 9800:
                q_out.put(1)
            else:
                q_out.put(0)
        except Exception as e:
            print(f'Problem: {e}')
            q_out.put(-1)

            try:
                engine.quit()
                engine = chess.engine.SimpleEngine.popen_uci(proc)
            except Exception as e:
                print(f'Problem "{e}" while recovering, aborting...')
                break

    q_out.put(None)

    engine.quit()

q_in = Queue()
q_out = Queue()
processes =  []
for i in range(num_procs):
    p = Process(target=do_it, args=(q_out, q_in,))
    p.start()
    processes.append(p)

start = time.time()
n_queued = 0
for line in open(epd_file, 'r').readlines():
    line = line.rstrip('\n')
    # only using the fen here
    parts = line.split()
    q_out.put(' '.join(parts[0:4]))
    n_queued += 1

for i in range(num_procs):
    q_out.put(None)

ok = 0
nok = 0
errors = 0
finished = 0

while True:
    msg = q_in.get()
    if msg == None:
        finished += 1
        if finished == num_procs:
            break
    elif msg == 1:
        ok += 1
    elif msg == 0:
        nok += 1
    else:
        errors += 1

end = time.time()

total_n = ok + nok
print(f'% ok: {ok * 100 / total_n:.2f}, total processed: {total_n}, total queued: {n_queued}, errors: {errors}, took: {end - start:.3f}')

for p in processes:
    p.join()