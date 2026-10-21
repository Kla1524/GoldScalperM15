"""SMC lab: results per model and per market regime from the trade journals.

    python tools/smc_analyze.py reports/experiments/<suite>

For each run folder with GS15_journal_GOLD_20261013_tester.csv: trades, win %, total R, average R,
profit factor, and the same split by ADX(H1) at entry (<20 sideways, 20-25, >=25 trending),
by killzone hour block and by whether the trade went with the H1 bias.
"""
import csv
import os
import sys


def stats(rows):
    rs = [float(r['r']) for r in rows]
    if not rs:
        return '-'
    win = sum(x > 0 for x in rs)
    gp = sum(x for x in rs if x > 0)
    gl = -sum(x for x in rs if x < 0)
    pf = gp / gl if gl > 0 else float('inf')
    return 'n=%d win=%.0f%% R=%+.1f avgR=%+.3f PF=%.2f' % (len(rs), win / len(rs) * 100, sum(rs), sum(rs) / len(rs), pf)


def main(suite):
    for name in sorted(os.listdir(suite)):
        j = os.path.join(suite, name, 'GS15_journal_GOLD_20261013_tester.csv')
        if not os.path.isfile(j):
            continue
        rows = list(csv.DictReader(open(j, encoding='utf-8', errors='ignore')))
        print('\n%s: %s' % (name, stats(rows)))
        b = lambda r: float(r['adx_h1'])
        print('   ADX<20      %s' % stats([r for r in rows if b(r) < 20]))
        print('   ADX 20-25   %s' % stats([r for r in rows if 20 <= b(r) < 25]))
        print('   ADX>=25     %s' % stats([r for r in rows if b(r) >= 25]))
        withb = [r for r in rows if (r['dir'] == 'BUY' and r['h1_bias'] == '1') or (r['dir'] == 'SELL' and r['h1_bias'] == '-1')]
        agst = [r for r in rows if (r['dir'] == 'BUY' and r['h1_bias'] == '-1') or (r['dir'] == 'SELL' and r['h1_bias'] == '1')]
        print('   with H1 bias %s' % stats(withb))
        print('   against bias %s' % stats(agst))
        for lo, hi in ((0, 9), (9, 12), (12, 14), (14, 18), (18, 24)):
            print('   hour %02d-%02d   %s' % (lo, hi, stats([r for r in rows if lo <= int(r['hour']) < hi])))


if __name__ == '__main__':
    main(sys.argv[1])
