"""Trade-level analysis of a GoldScalperM15 tester journal (Common\\Files\\GS15_journal_*_tester.csv).

Usage: python tools/analyze_journal.py <journal.csv> <deposit> [risk_pct] [sl_atr] [slip_price] [contract]

Prints yearly results, losing streaks, expectancy and the REAL risk of every trade at entry
(lots x (SL distance + slippage) x contract) compared with the equity at that time.
Balance before each trade is rebuilt from the deposit and the closed P/L of the journal.
"""
import sys
import pandas as pd

path = sys.argv[1]
deposit = float(sys.argv[2])
risk_pct = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
sl_atr = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
slip = float(sys.argv[5]) if len(sys.argv) > 5 else 0.30      # 30 points on XM GOLD (0.01)
contract = float(sys.argv[6]) if len(sys.argv) > 6 else 100.0  # oz per lot, XM GOLD Standard

j = pd.read_csv(path)
j['open'] = pd.to_datetime(j['open_time'], format='%Y.%m.%d %H:%M')
j['close'] = pd.to_datetime(j['close_time'], format='%Y.%m.%d %H:%M')
j = j.sort_values('open').reset_index(drop=True)
j['bal_before'] = deposit + j['pl'].cumsum().shift(fill_value=0)
j['risk_money'] = j['lots'] * (j['atr_m15'] * sl_atr + slip) * contract
j['risk_pct'] = j['risk_money'] / j['bal_before'] * 100
j['year'] = j['open'].dt.year

n = len(j)
wins = j[j.pl > 0]
losses = j[j.pl < 0]
pf = wins.pl.sum() / -losses.pl.sum() if len(losses) else float('inf')
streak = mx = 0
for v in j.pl:
    if v < 0:
        streak += 1
        mx = max(mx, streak)
    elif v > 0:
        streak = 0
eq = deposit + j.pl.cumsum()
peak = eq.cummax().clip(lower=deposit)
dd = ((peak - eq) / peak * 100).max()

print(f'trades {n}  net {j.pl.sum():.2f}  PF {pf:.2f}  win% {len(wins)/n*100:.1f}  '
      f'avg win {wins.pl.mean():.2f}  avg loss {losses.pl.mean():.2f}  expectancy {j.pl.mean():.2f}  '
      f'max losing streak {mx}  closed-trade DD {dd:.1f}%')
print()
print('real risk at entry (% of balance before the trade):')
print(j['risk_pct'].describe(percentiles=[.05, .25, .5, .75, .95]).round(3).to_string())
over = j[j.risk_pct > risk_pct * 1.0001]
print(f'trades above the {risk_pct}% target: {len(over)} ({len(over)/n*100:.1f}%)')
if len(over):
    print(over[['open_time', 'lots', 'atr_m15', 'bal_before', 'risk_money', 'risk_pct', 'pl']].head(10).to_string(index=False))
print()
print('by year:')
g = j.groupby('year').agg(trades=('pl', 'size'), net=('pl', 'sum'), win_pct=('pl', lambda s: (s > 0).mean() * 100),
                          avg_risk_pct=('risk_pct', 'mean'), max_risk_pct=('risk_pct', 'max'))
print(g.round(2).to_string())
print()
late = j[(j.close.dt.date != j.open.dt.date)]
print(f'held past midnight: {len(late)}')
if len(late):
    print(late[['open_time', 'close_time', 'pl', 'exit_reason']].to_string(index=False))
print()
print('exit reasons:', j.exit_reason.value_counts().to_dict())
print('loss reason codes (losses):')
codes = losses.loss_reasons.fillna('').str.split('|').explode().value_counts()
print(codes.to_string())
