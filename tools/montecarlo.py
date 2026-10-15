"""Monte Carlo of drawdown and losing streaks from backtest trades (modes 1/2 journal).

    python tools/montecarlo.py --risk 0.5 --n 10000 RUN_DIR [RUN_DIR ...]

Each trade's result in R (P/L / money at risk, see analyze_exp.py) is resampled:
  shuffle:   the same trades in a random order (how bad the order could have been);
  bootstrap: trades drawn with replacement, same count (also varies which trades occur).
Equity compounds at --risk % per trade: equity *= 1 + risk/100 * R.
Prints the observed value and the median / 95th / 99th percentile of the maximum drawdown (%)
and of the longest losing streak, per run and for all runs pooled.
"""
import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from analyze_exp import mode1_r  # noqa: E402


def max_dd(rs, risk):
    eq = peak = 1.0
    worst = 0.0
    for r in rs:
        eq *= 1.0 + risk / 100.0 * r
        peak = max(peak, eq)
        worst = max(worst, 1.0 - eq / peak)
    return 100.0 * worst


def max_streak(rs):
    best = cur = 0
    for r in rs:
        cur = cur + 1 if r < 0 else 0
        best = max(best, cur)
    return best


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p / 100.0 * (len(xs) - 1))))]


def simulate(label, rs, risk, n, rng):
    lines = ['%s: %d trades, observed max DD %.1f%%, longest losing streak %d' % (label, len(rs), max_dd(rs, risk), max_streak(rs))]
    for mode in ('shuffle', 'bootstrap'):
        dds, sts = [], []
        for _ in range(n):
            s = rs[:] if mode == 'shuffle' else [rng.choice(rs) for _ in rs]
            if mode == 'shuffle':
                rng.shuffle(s)
            dds.append(max_dd(s, risk))
            sts.append(max_streak(s))
        lines.append('    %-9s max DD %%: median %.1f  95%% %.1f  99%% %.1f | losing streak: median %d  95%% %d  99%% %d' % (
            mode, pct(dds, 50), pct(dds, 95), pct(dds, 99), pct(sts, 50), pct(sts, 95), pct(sts, 99)))
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('runs', nargs='+')
    ap.add_argument('--risk', type=float, default=0.5)
    ap.add_argument('--n', type=int, default=10000)
    ap.add_argument('--seed', type=int, default=20261015)
    ap.add_argument('--out', default='')
    a = ap.parse_args()
    rng = random.Random(a.seed)
    out, pooled = [], []
    for d in a.runs:
        rs = [t[3] for t in sorted(mode1_r(d), key=lambda t: t[0])]
        if not rs:
            continue
        pooled += rs
        out += simulate(os.path.basename(os.path.normpath(d)), rs, a.risk, a.n, rng)
    if len(a.runs) > 1 and pooled:
        out += simulate('pooled (runs in the order given)', pooled, a.risk, a.n, rng)
    text = 'Monte Carlo, %d resamples, risk %.2f%% per trade, seed %d\n' % (a.n, a.risk, a.seed) + '\n'.join(out) + '\n'
    if a.out:
        with open(a.out, 'w', encoding='utf-8') as f:
            f.write(text)
    print(text)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    main()
