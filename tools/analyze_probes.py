"""Research probes of a suite (InpProbeLog = true), per run.

    python tools/analyze_probes.py reports/experiments/suite_20261015_exp2

kind 1 (modes 1/2): signals skipped because a position was open. Hypothetical result in R: exit at the
  stop (-1 R) or at the daily close, whichever came first (prices on the exit side, so the spread is in).
kind 2 (mode 3): every M5 confirmation. MFE / MAE in R after 4/8/16/32 M15 bars, how often the stop was
  reached by then, and what a fixed target of k R would have earned with the 1 R stop within 32 bars:
  +k if the move reached k R before the stop, -1 if the stop came first, 0 if neither (open after 32 bars).
Writes probes.txt into the suite folder and prints it.
"""
import csv
import glob
import io
import os
import sys


def rows_of(run_dir):
    files = glob.glob(os.path.join(run_dir, 'GS15_probe_*.csv'))
    if not files:
        return []
    with io.open(files[0], encoding='utf-8-sig', errors='replace') as f:
        return list(csv.DictReader(f))


def mean(xs):
    return sum(xs) / len(xs) if xs else float('nan')


def main(suite):
    out = []
    for d in sorted(glob.glob(os.path.join(suite, '*'))):
        if not os.path.isdir(d):
            continue
        rows = rows_of(d)
        if not rows:
            continue
        name = os.path.basename(d)
        k1 = [r for r in rows if r['kind'] == '1']
        k2 = [r for r in rows if r['kind'] == '2']
        if k1:
            rs = [float(r['exit_r']) for r in k1 if r['exit_r'] != '']
            out.append('%s: %d skipped signals (position open), hypothetical expectancy %+.3f R, win %.1f%%, '
                       'stop hit %.1f%%, sum %+.1f R' % (
                           name, len(rs), mean(rs), 100.0 * sum(1 for x in rs if x > 0) / len(rs),
                           100.0 * sum(1 for x in rs if x <= -0.999) / len(rs), sum(rs)))
        if k2:
            out.append('%s: %d mode-3 confirmations' % (name, len(k2)))
            out.append('    bars  MFE(avg R)  MAE(avg R)  stop reached')
            for n in (4, 8, 16, 32):
                mfe = [float(r['mfe%d' % n]) for r in k2]
                mae = [float(r['mae%d' % n]) for r in k2]
                hit = sum(1 for r in k2 if r['sl_hit'] == '1' and int(r['sl_bar']) <= n)
                out.append('    %4d  %10.2f  %10.2f  %10.1f%%' % (n, mean(mfe), mean(mae), 100.0 * hit / len(k2)))
            out.append('    fixed target, 1 R stop, 32 bars:  k   reached first  stop first  expectancy')
            for k in (0.5, 1.0, 1.5, 2.0, 3.0):
                win = sum(1 for r in k2 if float(r['mfe_before_sl_r']) >= k)
                loss = sum(1 for r in k2 if r['sl_hit'] == '1' and float(r['mfe_before_sl_r']) < k)
                exp = (win * k - loss) / len(k2)
                out.append('                                    %3.1f  %12.1f%%  %9.1f%%  %+9.3f R' % (
                    k, 100.0 * win / len(k2), 100.0 * loss / len(k2), exp))
    text = '\n'.join(out) + '\n'
    io.open(os.path.join(suite, 'probes.txt'), 'w', encoding='utf-8').write(text)
    print(text)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    main(sys.argv[1])
