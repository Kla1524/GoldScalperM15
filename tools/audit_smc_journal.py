"""Audit a mode-3 SMC journal from the tester (GS15_smc_journal_*_tester.csv).

Usage: python tools/audit_smc_journal.py <smc_journal.csv> [deals.csv] [risk_pct] [min_rr]

Checks, for every traded setup:
  - one OPEN per setup ID (no duplicates);
  - OPEN comes after READY and CONFIRMED of the same setup, in time order;
  - planned risk <= target %, RR >= minimum;
and summarises why setups ended (invalidated / expired reasons) and results by period.
"""
import sys
import pandas as pd

path = sys.argv[1]
deals = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2].endswith('.csv') else None
risk_pct = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
min_rr = float(sys.argv[4]) if len(sys.argv) > 4 else 1.5

j = pd.read_csv(path)
j['t'] = pd.to_datetime(j['time'], format='%Y.%m.%d %H:%M:%S')
problems = []

opens = j[j.event == 'OPEN']
dup = opens.setup_id.value_counts()
for sid, n in dup[dup > 1].items():
    problems.append(f'{sid}: {n} OPEN events (duplicate entry)')
for _, o in opens.iterrows():
    s = j[j.setup_id == o.setup_id]
    ready = s[s.event == 'READY']
    conf = s[s.event == 'CONFIRMED']
    if ready.empty or conf.empty:
        problems.append(f'{o.setup_id}: OPEN without READY/CONFIRMED')
        continue
    if not (ready.t.min() <= conf.t.min() <= o.t):
        problems.append(f'{o.setup_id}: events out of order (ready {ready.t.min()}, confirmed {conf.t.min()}, open {o.t})')
    if o.risk_pct > risk_pct * 1.0001:
        problems.append(f'{o.setup_id}: planned risk {o.risk_pct:.3f}% > {risk_pct}%')
    if o.rr < min_rr - 1e-9:
        problems.append(f'{o.setup_id}: RR {o.rr:.2f} < {min_rr}')

print(f'events: {len(j)}  setups detected: {j[j.event == "DETECTED"].setup_id.nunique()}  ready: {j[j.event == "READY"].setup_id.nunique()}  '
      f'confirmed: {j[j.event == "CONFIRMED"].setup_id.nunique()}  opened: {len(opens)}')
print(f'audit problems: {len(problems)}')
for p in problems[:30]:
    print('  -', p)

ended = j[j.event.isin(['INVALIDATED', 'EXPIRED'])].copy()
ended['why'] = ended.reason.fillna('').str.replace(r'[\d.]+', '#', regex=True).str.slice(0, 70)
print('\nwhy setups ended (top 15):')
print(ended.groupby(['event', 'why']).size().sort_values(ascending=False).head(15).to_string())

if len(opens):
    print('\nplanned risk % of equity:', opens.risk_pct.describe().round(3).to_dict())
    print('planned RR:', opens.rr.describe().round(2).to_dict())

closes = j[j.event == 'CLOSE']
if len(closes):
    closes = closes.assign(year=closes.t.dt.year, win=closes.pl > 0)
    print('\nclosed trades by year (from the journal):')
    print(closes.groupby('year').agg(trades=('pl', 'size'), net=('pl', 'sum'), win_pct=('win', 'mean')).round(2).to_string())
    print('exit reasons:', closes.reason.value_counts().to_dict())
