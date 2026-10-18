"""Check the v1.53 close rules (written in advance) against the days GOLD actually stopped early (TickProbe, hindsight).

    python tools/check_close_rules.py <probe_days.txt>

Diagnosis only: the EA never sees the probe. Lists early-stopping weekdays the rules do not cover, and rule days
that turned out to be normal.
"""
import datetime as dt
import re
import sys


def nth_dow(y, m, dow, n):  # dow: 0 = Sunday ... 6 = Saturday (MQL convention)
    if n > 0:
        first = dt.date(y, m, 1)
        wd = (first.weekday() + 1) % 7
        return 1 + (dow - wd) % 7 + (n - 1) * 7
    d = dt.date(y, m + 1, 1) - dt.timedelta(days=1) if m < 12 else dt.date(y, 12, 31)
    while (d.weekday() + 1) % 7 != dow:
        d -= dt.timedelta(days=1)
    return d.day


def mismatch(d):
    y = d.year
    us_s, eu_s = dt.date(y, 3, nth_dow(y, 3, 0, 2)), dt.date(y, 3, nth_dow(y, 3, 0, -1))
    eu_e, us_e = dt.date(y, 10, nth_dow(y, 10, 0, -1)), dt.date(y, 11, nth_dow(y, 11, 0, 1))
    return us_s <= d < eu_s or eu_e <= d < us_e


def early(d):
    y, m, day, w = d.year, d.month, d.day, (d.weekday() + 1) % 7
    if m == 1 and day == nth_dow(y, 1, 1, 3): return 'MLK'
    if m == 2 and day == nth_dow(y, 2, 1, 3): return 'Presidents'
    if m == 5 and day == nth_dow(y, 5, 1, -1): return 'Memorial'
    if m == 9 and day == nth_dow(y, 9, 1, 1): return 'Labor'
    if m == 11 and day in (nth_dow(y, 11, 4, 4), nth_dow(y, 11, 4, 4) + 1): return 'Thanksgiving'
    if m == 12 and day in (24, 31) and 1 <= w <= 5: return 'Dec24/31'
    if m == 7 and ((day == 4 and 1 <= w <= 5) or (day == 3 and w == 5) or (day == 5 and w == 1)): return 'July4'
    if y >= 2022 and m == 6 and ((day == 19 and 1 <= w <= 5) or (day == 18 and w == 5) or (day == 20 and w == 1)): return 'Juneteenth'
    return ''


def main(path):
    miss, ok, normal_rule = [], 0, []
    for line in open(path, encoding='utf-8-sig'):
        m = re.match(r'(\S+) dow=(\d) first=(\S+) last=(\S+) ticks_after_2300=(\d+)', line.strip())
        if not m:
            continue
        d = dt.date(*map(int, m.group(1).split('.')))
        dow, last = int(m.group(2)), m.group(4)
        hh = int(last[:2]) + int(last[3:5]) / 60
        rule = early(d) or ('DST-mismatch' if mismatch(d) else '')
        stop = 24 if dow != 5 else 23.9
        is_early = hh < 23.5 and dow != 5 or (dow == 5 and hh < 21.2)
        if is_early and not rule:
            miss.append('%s dow=%d last=%s' % (m.group(1), dow, last))
        elif is_early:
            ok += 1
        elif rule and not is_early:
            normal_rule.append('%s %s (last tick %s)' % (m.group(1), rule, last))
    print('early-stopping days covered by the rules:', ok)
    print('early-stopping days NOT covered (%d):' % len(miss))
    for x in miss: print('   ', x)
    print('rule days that traded normally (%d):' % len(normal_rule))
    for x in normal_rule: print('   ', x)


if __name__ == '__main__':
    main(sys.argv[1])
