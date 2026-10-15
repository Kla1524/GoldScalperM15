"""Metrics for a GoldScalperM15 experiment suite (one folder per backtest run).

    python tools/analyze_exp.py reports/experiments/suite_20261015_exp1

Per run: net profit, profit factor, max equity drawdown and trade count (from the suite's
summary.csv), and from the trades themselves: win rate, average trade, expectancy in R and the
longest losing streak.

R = the money the trade risked when it was opened:
  mode 1/2: stop distance InpSL_ATR (4.0) x M15 ATR at entry (journal) x lots x contract size (100)
  mode 3:   |entry - SL| x lots x contract size, from the SMC journal (OPEN rows)
Mode 3: also the reasons why setups ended without a trade. Mode 1 news variants: the trades of the
no-news run that the filter removed, matched by day and direction.
Writes metrics.csv and report_tables.txt into the suite folder.
"""
import csv
import io
import os
import re
import sys
from collections import Counter, OrderedDict

CONTRACT = 100.0   # XM GOLD: 1 lot = 100 oz
SL_ATR = 4.0       # mode 1/2 default stop, x M15 ATR


def read_csv(path):
    if not os.path.exists(path):
        return []
    with io.open(path, encoding='utf-8-sig', errors='replace') as f:
        return list(csv.DictReader(f))


def inputs_of(run_dir):
    vals = {}
    p = os.path.join(run_dir, 'inputs.set')
    if os.path.exists(p):
        for line in io.open(p, encoding='utf-8-sig', errors='replace'):
            if '=' in line:
                k, v = line.strip().split('=', 1)
                vals[k] = v
    return vals


def streak(pls):
    best = cur = 0
    for x in pls:
        cur = cur + 1 if x < 0 else 0
        best = max(best, cur)
    return best


def mode1_r(run_dir):
    rows = read_csv(os.path.join(run_dir, 'GS15_journal_GOLD_20261013_tester.csv'))
    out = []
    for r in rows:
        try:
            risk = SL_ATR * float(r['atr_m15']) * float(r['lots']) * CONTRACT
            out.append((r['open_time'], r['dir'], float(r['pl']), float(r['pl']) / risk if risk > 0 else 0.0))
        except (KeyError, ValueError):
            pass
    return out


def mode3_r(run_dir):
    rows = read_csv(os.path.join(run_dir, 'GS15_smc_journal_GOLD_20261013_tester.csv'))
    opened = {}
    out = []
    for r in rows:
        if r.get('event') == 'OPEN':
            try:
                opened[r['setup_id']] = (r['time'], r['dir'], abs(float(r['entry']) - float(r['sl'])) * float(r['lots']) * CONTRACT)
            except ValueError:
                pass
        elif r.get('event') == 'CLOSE' and r['setup_id'] in opened:
            t, d, risk = opened[r['setup_id']]
            pl = float(r['pl'] or 0)
            out.append((t, d, pl, pl / risk if risk > 0 else 0.0))
    return out, rows


def norm_reason(s):
    s = re.sub(r'\s*\(target.*$', '', s)   # the CSV row is cut at the comma inside '(target x, stop y)'
    s = re.sub(r'(?<![A-Za-z0-9.])\d+(\.\d+)?', '#', s)   # keep H1 / M15 / M5
    return re.sub(r'\s+', ' ', s).strip()


def main(suite):
    summary = OrderedDict((r['Run'], r) for r in read_csv(os.path.join(suite, 'summary.csv')))
    metrics, notes = [], []
    trades_by_run = {}
    for name, s in summary.items():
        d = os.path.join(suite, name)
        inp = inputs_of(d)
        mode3 = inp.get('InpTradeStyle') == '3'
        deals = read_csv(os.path.join(d, 'deals.csv'))
        pls = [float(x['PL']) for x in deals if x.get('PL') not in (None, '')]
        if mode3:
            tr, smc_rows = mode3_r(d)
        else:
            tr, smc_rows = mode1_r(d), []
        trades_by_run[name] = tr
        n = len(pls)
        rs = [t[3] for t in tr]
        m = OrderedDict()
        m['Run'] = name
        m['Net'] = float(s.get('Net') or 0)
        m['PF'] = s.get('PF')
        m['DDpct'] = s.get('DDpct')
        m['Trades'] = int(float(s.get('Trades') or 0))
        m['WinPct'] = round(100.0 * sum(1 for x in pls if x > 0) / n, 1) if n else 0
        m['AvgTrade'] = round(sum(pls) / n, 2) if n else 0
        m['ExpR'] = round(sum(rs) / len(rs), 3) if rs else ''
        m['MaxLossStreak'] = streak(pls)
        metrics.append(m)
        if mode3:
            reasons = Counter(norm_reason(r.get('reason', '')) for r in smc_rows if r.get('event') in ('INVALIDATED', 'EXPIRED'))
            ev = Counter(r.get('event') for r in smc_rows)
            notes.append('%s: detected %d, ready %d, confirmed %d, opened %d' % (name, ev['DETECTED'], ev['READY'], ev['CONFIRMED'], ev['OPEN']))
            for k, v in reasons.most_common(6):
                notes.append('    %4d  %s' % (v, k))

    # Mode 1 news variants vs the no-news run of the same period: which trades the filter removed.
    news = []
    for name in summary:
        if not name.startswith('N') or name.startswith('N0_'):
            continue
        period = name.rsplit('_', 1)[1]
        base = next((b for b in summary if b.startswith('N0_') and b.endswith('_' + period)), None)
        if not base:
            continue
        key = lambda t: (t[0][:10], t[1])
        have = {key(t) for t in trades_by_run[name]}
        gone = [t for t in trades_by_run[base] if key(t) not in have]
        news.append('%s vs %s: %d trades removed, their P/L %+.2f USD, %+.2f R' % (
            name, base, len(gone), sum(t[2] for t in gone), sum(t[3] for t in gone)))

    with io.open(os.path.join(suite, 'metrics.csv'), 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(metrics[0].keys()))
        w.writeheader()
        w.writerows(metrics)
    lines = ['%-34s %10s %5s %6s %6s %6s %9s %7s %6s' % ('Run', 'Net', 'PF', 'DD%', 'Trades', 'Win%', 'AvgTrade', 'ExpR', 'MaxLS')]
    for m in metrics:
        lines.append('%-34s %10.2f %5s %6s %6d %6.1f %9.2f %7s %6d' % (m['Run'], m['Net'], m['PF'], m['DDpct'], m['Trades'], m['WinPct'], m['AvgTrade'], m['ExpR'], m['MaxLossStreak']))
    text = '\n'.join(lines + ['', 'News filter: trades removed (vs no news)'] + news + ['', 'Mode 3 funnel and reasons setups ended'] + notes) + '\n'
    io.open(os.path.join(suite, 'report_tables.txt'), 'w', encoding='utf-8').write(text)
    print(text)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    main(sys.argv[1])
