"""W1 follow-up analysis (18 Oct 2026).

    python tools/w1_analyze.py

1. Per run: net, equity DD (report), trades, net per year, worst year.
2. S1fix (close at 20:00) vs S2 (no daily close): where the difference comes from - trades held past
   midnight (their P/L and swap), how many S1fix trades S2 never took (because it was still holding), and
   whether the first trade of a day does better than the later ones.
3. Swap timing: positions closed before 00:00 server pay no swap, positions held past it do.
"""
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare_trades import table  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'reports', 'experiments')


def num(x):
    try:
        return float(x.replace(' ', '').replace('\xa0', ''))
    except ValueError:
        return 0.0


def load(path):
    html = io.open(path, encoding='utf-16').read()
    dd = re.search(r'Equity Drawdown Relative:</td>\s*<td[^>]*><b>([\d.]+)%', html)
    out, cur = [], None
    for r in table(html, 'Deals'):
        if len(r) < 13 or not r[1].isdigit():
            continue
        if r[4] == 'in':
            cur = {'open': r[0], 'dir': r[3]}
        elif r[4] in ('out', 'out by') and cur:
            cur.update({'close': r[0], 'swap': num(r[9]), 'pl': num(r[8]) + num(r[9]) + num(r[10])})
            out.append(cur)
            cur = None
    return out, (float(dd.group(1)) if dd else None)


def years(tr):
    y = {}
    for t in tr:
        y[t['open'][:4]] = y.get(t['open'][:4], 0) + t['pl']
    return y


def section1(suites):
    print('run,net,equity_dd_pct,trades,worst_year,worst_year_pl,per_year')
    for s in suites:
        d = os.path.join(ROOT, s)
        for n in sorted(os.listdir(d)):
            p = os.path.join(d, n, 'report.htm')
            if not os.path.isfile(p):
                continue
            tr, dd = load(p)
            y = years(tr)
            wy = min(y.items(), key=lambda kv: kv[1]) if y else ('', 0)
            print('%s,%.2f,%s,%d,%s,%.2f,"%s"' % (n, sum(t['pl'] for t in tr), dd, len(tr), wy[0], wy[1],
                                                  ' '.join('%s:%+.0f' % kv for kv in sorted(y.items()))))


def section2(tag):
    a, _ = load(os.path.join(ROOT, 'suite_20261018_w1', 'S1fix_sl2tp2_trend_close_%s' % tag, 'report.htm'))
    b, _ = load(os.path.join(ROOT, 'suite_20261017_exits', 'S2_sl2tp2_trend_noclose_%s' % tag, 'report.htm'))
    over = [t for t in b if t['close'][:10] != t['open'][:10]]
    same = [t for t in b if t['close'][:10] == t['open'][:10]]
    opens_b = {t['open'] for t in b}
    missed = [t for t in a if t['open'] not in opens_b]
    extra = [t for t in b if t['open'] not in {x['open'] for x in a}]
    print('\n[%s] S1fix net %.2f (%d trades) | S2 net %.2f (%d trades)' % (tag, sum(t['pl'] for t in a), len(a), sum(t['pl'] for t in b), len(b)))
    print('  S2 trades held past midnight: %d, P/L %.2f (of which swap %.2f); same-day trades: %d, P/L %.2f'
          % (len(over), sum(t['pl'] for t in over), sum(t['swap'] for t in over), len(same), sum(t['pl'] for t in same)))
    print('  S1fix trades S2 did not take (S2 still holding or the day differed): %d, their P/L in S1fix %.2f'
          % (len(missed), sum(t['pl'] for t in missed)))
    print('  S2 trades S1fix did not take: %d, P/L %.2f' % (len(extra), sum(t['pl'] for t in extra)))
    # first vs later trades of the day in S1fix
    seen, first, later = set(), [], []
    for t in a:
        (later if t['open'][:10] in seen else first).append(t)
        seen.add(t['open'][:10])
    for name, g in (('first trade of the day', first), ('2nd+ trades of the day', later)):
        w = sum(t['pl'] > 0 for t in g)
        print('  S1fix %s: %d trades, win %.1f%%, P/L %.2f' % (name, len(g), w / len(g) * 100 if g else 0, sum(t['pl'] for t in g)))


def section3():
    b, _ = load(os.path.join(ROOT, 'suite_20261017_exits', 'S2_sl2tp2_trend_noclose_VALRT', 'report.htm'))
    held = [t for t in b if t['close'][:10] != t['open'][:10]]
    sameday = [t for t in b if t['close'][:10] == t['open'][:10]]
    print('\nSwap timing (S2 real ticks): held past 00:00 server: %d trades, %d with swap != 0; closed the same server day: %d trades, %d with swap != 0'
          % (len(held), sum(t['swap'] != 0 for t in held), len(sameday), sum(t['swap'] != 0 for t in sameday)))
    late = [t for t in sameday if t['close'][11:13] == '23']
    print('  closed between 23:00 and 23:59 server: %d trades, swap total %.2f' % (len(late), sum(t['swap'] for t in late)))


if __name__ == '__main__':
    section1(['suite_20261018_w1'])
    for tag in ('DEV', 'VAL', 'VALRT'):
        section2(tag)
    section3()
