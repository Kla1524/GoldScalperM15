"""Bundle the full MT5 reports of the baseline, W1a and T6 and write one overview page.

    python tools/candidate_reports.py <tester reports folder> <output folder>

Copies each report (.htm + graph .png files) and writes overview.html (UTF-8) with, per run: trades,
profit factor, equity drawdown, average win / loss, max consecutive losses, the equity graph, and
net P/L by year and by month (closed trades).
"""
import html as H
import io
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare_trades import table  # noqa: E402

RUNS = [('Baseline (v1.52 defaults)', 'REG152'), ('W1a: close 23:00 server', 'W1a_close23'), ('T6: TP 6 ATR (1:1.5)', 'T6_tp6')]
PERIODS = [('VALRT', 'Real ticks, 14 Oct 2024 - 12 Oct 2026'), ('VAL', '1-minute OHLC, 2024 - 12 Oct 2026'), ('DEV', '1-minute OHLC, 2018 - 2023')]
FIELDS = ['Total Net Profit', 'Profit Factor', 'Total Trades', 'Equity Drawdown Maximal', 'Equity Drawdown Relative',
          'Balance Drawdown Maximal', 'Average profit trade', 'Average loss trade', 'Maximum consecutive losses ($)',
          'Profit Trades (% of total)', 'Expected Payoff', 'Recovery Factor', 'Sharpe Ratio']


def field(text, name):
    m = re.search(re.escape(name) + r':</td>\s*<td[^>]*><b>([^<]*)</b>', text)
    return m.group(1).strip() if m else '-'


def num(x):
    try:
        return float(x.replace(' ', '').replace('\xa0', ''))
    except ValueError:
        return 0.0


def monthly(text):
    by = {}
    for r in table(text, 'Deals'):
        if len(r) >= 13 and r[1].isdigit() and r[4] in ('out', 'out by'):
            k = r[0][:7]
            by[k] = by.get(k, 0) + num(r[8]) + num(r[9]) + num(r[10])
    return by


def main(src, out):
    os.makedirs(out, exist_ok=True)
    parts = ['<!doctype html><meta charset="utf-8"><title>GoldScalper candidates</title>',
             '<style>body{font:14px Segoe UI,Arial;margin:16px;max-width:1200px}table{border-collapse:collapse;margin:6px 0 16px}'
             'td,th{border:1px solid #ccc;padding:3px 7px;text-align:right}th{background:#eee}td:first-child{text-align:left}'
             '.neg{color:#b00}.grid{display:flex;flex-wrap:wrap;gap:12px}.card{flex:1 1 360px}img{max-width:100%}</style>',
             '<h1>Baseline / W1a / T6 - MT5 Strategy Tester reports</h1>',
             '<p>XM GOLD M15, $10,000, risk 0.5% per trade, news filter +/-15 min, EA v1.52. Equity drawdown includes open (floating) P/L. '
             'The full MT5 reports are next to this page (open the .htm files). For education and research only - not investment advice.</p>']
    for ptag, pname in PERIODS:
        parts.append('<h2>%s</h2><table><tr><th>Metric</th>%s</tr>' % (pname, ''.join('<th>%s</th>' % H.escape(r[0]) for r in RUNS)))
        texts = []
        for _, rtag in RUNS:
            base = 'night_%s_%s' % (rtag, ptag)
            t = io.open(os.path.join(src, base + '.htm'), encoding='utf-16').read()
            texts.append((base, t))
            for f in os.listdir(src):
                if f.startswith(base + '.') or f.startswith(base + '-'):
                    shutil.copy2(os.path.join(src, f), os.path.join(out, f))
        for fld in FIELDS:
            parts.append('<tr><td>%s</td>%s</tr>' % (fld, ''.join('<td>%s</td>' % H.escape(field(t, fld)) for _, t in texts)))
        parts.append('</table><div class="grid">')
        for (label, _), (base, t) in zip(RUNS, texts):
            parts.append('<div class="card"><b>%s</b><br><img src="%s.png" alt="equity graph"><br><a href="%s.htm">full MT5 report</a></div>' % (H.escape(label), base, base))
        parts.append('</div>')
        months = [monthly(t) for _, t in texts]
        keys = sorted(set().union(*months))
        years = sorted({k[:4] for k in keys})
        parts.append('<h3>Net by year</h3><table><tr><th>Year</th>%s</tr>' % ''.join('<th>%s</th>' % H.escape(r[0]) for r in RUNS))
        for y in years:
            vals = [sum(v for k, v in m.items() if k.startswith(y)) for m in months]
            parts.append('<tr><td>%s</td>%s</tr>' % (y, ''.join('<td class="%s">%+.2f</td>' % ('neg' if v < 0 else '', v) for v in vals)))
        parts.append('</table><details><summary>Net by month</summary><table><tr><th>Month</th>%s</tr>' % ''.join('<th>%s</th>' % H.escape(r[0]) for r in RUNS))
        for k in keys:
            vals = [m.get(k, 0) for m in months]
            parts.append('<tr><td>%s</td>%s</tr>' % (k, ''.join('<td class="%s">%+.2f</td>' % ('neg' if v < 0 else '', v) for v in vals)))
        parts.append('</table></details>')
    io.open(os.path.join(out, 'overview.html'), 'w', encoding='utf-8').write('\n'.join(parts))
    print('written', out)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
