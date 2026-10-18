"""Session-guard audit (v1.53): close audit from the tester log + trades that closed on a later day.

    python tools/guard_analyze.py <agent log> <start byte> <suite folder> <run1,run2,...>

The runs must be listed in the order the suite ran them. For each run: closes by kind (daily close, Friday,
summer-time mismatch week, US holiday early close, LATE = closed on a later day), how many were sent after the
deadline, closes that needed more than one tick, and every trade that closed on a later server day.
"""
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from w1_analyze import load  # noqa: E402


def segments(log, start):
    with open(log, 'rb') as f:
        f.seek(start)
        text = f.read().decode('utf-16-le', errors='ignore')
    parts = re.split(r'testing of Experts\\MyEA\\Dev\\GS15_dev\.ex5 from', text)
    return parts[1:]


def main(log, start, suite, runs):
    segs = segments(log, int(start))
    print('runs in log: %d, runs listed: %d' % (len(segs), len(runs)))
    for name, seg in zip(runs, segs):
        audits = re.findall(r'CLOSEAUDIT #(\d+) kind=([^=]+?) deadline=(\S+ \S+) sent=(\S+ \S+)', seg)
        done = dict(re.findall(r'CLOSEDONE #(\d+) at (\S+ \S+)', seg))
        kinds = {}
        late_sent, not_done = 0, []
        for tk, kind, deadline, sent in audits:
            kinds[kind] = kinds.get(kind, 0) + 1
            if kind.startswith('LATE'):
                continue
            if sent[:16] > deadline[:16] and sent[11:13] != deadline[11:13]:
                late_sent += 1
            if tk not in done:
                not_done.append(tk)
        tr, dd = load(os.path.join(suite, name, 'report.htm'))
        later = [t for t in tr if t['close'][:10] != t['open'][:10]]
        print('\n%s: net %.2f, equity DD %s%%, trades %d' % (name, sum(t['pl'] for t in tr), dd, len(tr)))
        print('  closes by rule: ' + ', '.join('%s %d' % kv for kv in sorted(kinds.items())))
        print('  sent more than an hour after the deadline: %d; audit without a confirmed close: %d' % (late_sent, len(not_done)))
        print('  trades closed on a later server day: %d, swap %.2f' % (len(later), sum(t['swap'] for t in later)))
        for t in later:
            print('     %s -> %s  swap %.2f  P/L %.2f' % (t['open'], t['close'], t['swap'], t['pl']))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(','))
