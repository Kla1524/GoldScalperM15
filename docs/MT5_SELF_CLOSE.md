# MT5 terminal closing by itself (15 Oct 2026)

The demo MT5 (portable, D:\MT5_GoldScalper) closed itself four times on 15 Oct 2026, always with a normal
exit ("exit with code 0", the EA removed first), and always a few seconds after another MT5 terminal on
the same PC started:

| Live terminal closed | Another terminal started just before |
|---|---|
| 15:59:31 | test copy (D:\MT5_Tester) started 15:59:19, logged in to the same demo account 15:59:23 |
| 17:03:30 | test copy started 17:03:17, logged in 17:03:22 |
| 19:26:29 | test copy started 19:26:21, logged in 19:26:25 |
| 21:07:04 | the user opened the original MT5 (C:\Program Files) - its journal starts 21:07:08 |

Not every start of a second terminal closed the live one (several test runs did not), and when the live
terminal was started while the test copy was already running, both kept running. The cause is not proven.
Every case so far: a terminal that starts while the live one runs.

What we do until it is understood:
- Do not open another MT5 (or MetaEditor) on the PC while the trading terminal runs.
- Backtests run only when the market is closed (weekend), with the live terminal closed after checking
  there is no position or pending order.
- The backtest suite logs every terminal's folder and process id before and after each run and whether the
  live terminal still runs; the test terminal starts minimised.
- At logon, tools/autostart asks Yes / No before starting the trading terminal (it never starts a second one).

Next step (weekend): reproduce with the market closed - start a test copy as-is, then one with fresh
configuration files, then the original MT5 - and see which ones close the live terminal.
