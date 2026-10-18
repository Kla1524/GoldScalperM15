"""Per-run statistics from Strategy Tester reports of a lab suite (closed deals only).

    python tools/lab_analyze.py reports/experiments/suite_20261017_lab1 > out.csv

For every run folder with a report.htm: trades, trades per trading day, win rate, net, worst day, worst
week, losing days in a row, max balance drawdown and the first day the balance fell below 50 % of the
deposit (account effectively blown).
"""
import csv
import datetime as dt
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare_trades import table  # noqa: E402


def num(x):
    x = x.replace(' ', '').replace('\xa0', '')
    try:
        return float(x)
    except ValueError:
        return None


def stats(path):
    html = io.open(path, encoding='utf-16').read()
    m = re.search(r'Initial Deposit:</td>\s*<td[^>]*><b>([\d\s.]+)</b>', html)
    deposit = num(m.group(1)) if m else 10000.0
    days, wins, losses, entries = {}, 0, 0, 0
    bal, peak, maxdd, blown = deposit, deposit, 0.0, ''
    for r in table(html, 'Deals'):
        if len(r) < 13 or not r[1].isdigit():
            continue
        t, direction = r[0], r[4]
        if direction == 'in':
            entries += 1
            continue
        if direction not in ('out', 'out by'):
            continue
        pl = (num(r[8]) or 0) + (num(r[9]) or 0) + (num(r[10]) or 0)
        d = t[:10]
        days[d] = days.get(d, 0) + pl
        wins += pl > 0
        losses += pl < 0
        bal = num(r[11]) if num(r[11]) is not None else bal + pl
        peak = max(peak, bal)
        maxdd = max(maxdd, (peak - bal) / peak * 100 if peak > 0 else 0)
        if not blown and bal < deposit * 0.5:
            blown = d
    seq = sorted(days.items())
    worst_day = min(seq, key=lambda kv: kv[1]) if seq else ('', 0)
    weeks = {}
    for d, v in seq:
        y, w, _ = dt.date(*map(int, d.split('.'))).isocalendar()
        weeks['%d-W%02d' % (y, w)] = weeks.get('%d-W%02d' % (y, w), 0) + v
    run = best = 0
    for _, v in seq:
        run = run + 1 if v < 0 else 0
        best = max(best, run)
    n = wins + losses
    return {
        'deposit': deposit, 'net': round(bal - deposit, 2), 'trades': entries, 'closes': n,
        'days_traded': len(seq), 'trades_per_day': round(entries / len(seq), 2) if seq else 0,
        'winrate_pct': round(wins / n * 100, 1) if n else 0,
        'losing_days_pct': round(sum(v < 0 for _, v in seq) / len(seq) * 100, 1) if seq else 0,
        'worst_day': worst_day[0], 'worst_day_pl': round(worst_day[1], 2),
        'worst_day_pct': round(worst_day[1] / deposit * 100, 1),
        'worst_week_pl': round(min(weeks.values()), 2) if weeks else 0,
        'max_losing_days_row': best, 'max_balance_dd_pct': round(maxdd, 1), 'blown_below_50pct_on': blown,
    }


def main(suite):
    rows = []
    for name in sorted(os.listdir(suite)):
        rep = os.path.join(suite, name, 'report.htm')
        if os.path.isfile(rep):
            row = {'run': name}
            row.update(stats(rep))
            rows.append(row)
    w = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()), lineterminator='\n')
    w.writeheader()
    w.writerows(rows)


if __name__ == '__main__':
    main(sys.argv[1])
