"""Trade-by-trade comparison of two Strategy Tester reports (regression evidence).

    python tools/compare_trades.py OLD_report.htm NEW_report.htm OUT.csv

A trade = an entry deal ("in") and its exit deal ("out"), in order (one position at a time). The SL comes
from the entry order's S/L in the Orders table. Writes every trade side by side with a match flag and
prints the count of trades and of mismatching trades.
"""
import csv
import io
import re
import sys


def cells(row):
    return [re.sub(r'<[^>]+>', '', c).replace('&nbsp;', ' ').strip()
            for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', row, re.S)]


def table(html, title):
    i = html.find('<b>%s</b>' % title)
    if i < 0:
        return []
    # Orders and Deals share one table: a section ends at the next section title or the table end.
    ends = [k for k in (html.find('<b>Deals</b>', i + 10) if title == 'Orders' else -1, html.find('</table>', i)) if k > 0]
    part = html[i:min(ends) if ends else len(html)]
    rows = [cells(r) for r in re.findall(r'<tr[^>]*>(.*?)</tr>', part, re.S)]
    return [r for r in rows if r]


def trades(path):
    html = io.open(path, encoding='utf-16').read()
    sl = {}
    for r in table(html, 'Orders'):
        if len(r) >= 7 and r[1].isdigit():
            sl[r[1]] = r[6]
    out, cur = [], None
    for r in table(html, 'Deals'):
        if len(r) < 13 or not r[1].isdigit():
            continue
        t, deal, typ, direction, vol, price, order, profit = r[0], r[1], r[3], r[4], r[5], r[6], r[7], r[10]
        if direction == 'in':
            cur = {'open_time': t, 'dir': typ.upper(), 'lots': vol, 'entry': price, 'sl': sl.get(order, '')}
        elif direction == 'out' and cur:
            cur.update({'close_time': t, 'exit': price, 'pl': profit.replace(' ', '')})
            out.append(cur)
            cur = None
    return out


def main(old_path, new_path, out_path):
    a, b = trades(old_path), trades(new_path)
    keys = ['open_time', 'dir', 'lots', 'entry', 'sl', 'close_time', 'exit', 'pl']
    n = max(len(a), len(b))
    bad = 0
    with io.open(out_path, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(['no'] + ['old_' + k for k in keys] + ['new_' + k for k in keys] + ['match'])
        for i in range(n):
            x = a[i] if i < len(a) else {}
            y = b[i] if i < len(b) else {}
            same = bool(x) and bool(y) and all(x.get(k) == y.get(k) for k in keys)
            bad += 0 if same else 1
            w.writerow([i + 1] + [x.get(k, '') for k in keys] + [y.get(k, '') for k in keys] + ['yes' if same else 'NO'])
    print('%s: old %d trades, new %d trades, mismatching %d' % (out_path, len(a), len(b), bad))


if __name__ == '__main__':
    main(*sys.argv[1:4])
