//+------------------------------------------------------------------+
//| GS_Sessions.mq5 - London / New York range breakout for the demo   |
//| Opening-range breakout on three session ranges, each its own      |
//| system (own magic, max 1 trade a day each), rules fixed IN        |
//| ADVANCE (21 Oct 2026, see SESSION_RULES.txt) - no tuning:         |
//|                                                                    |
//|  ASIA   range 00:00-08:00 server, entries 08:00-18:00 server       |
//|         (= the live EA)                                            |
//|  LONDON range = first London hour 08:00-09:00 London time,         |
//|         entries 09:00-12:00 London time                           |
//|         London = server - 2 h, or server - 3 h in the weeks when   |
//|         US summer time is on and UK/EU summer time is off          |
//|  NEWYORK range = 08:00-09:00 New York time, entries 09:00-11:00 NY  |
//|         New York = server - 7 h all year (both follow US DST)      |
//| Same for all: signal = first M15 close beyond the range with the   |
//| previous close inside; volatility filter ATR(D1) >= 1.6 % of       |
//| price; confidence score >= 1 (D1 EMA50, H1 EMA200, ADX H1 20-30,   |
//| RSI >= 70 / <= 30); spread <= 1.0; no entries +/-15 min around     |
//| high-impact USD news; SL = 4 x ATR(M15); no TP; strict risk-%      |
//| lots; close at 19:00 server (22:50 in mismatch weeks is never      |
//| earlier; 18:00 on US holiday early closes), Friday 19:00 too;      |
//| daily loss limit 3 % of balance across all systems.                |
//+------------------------------------------------------------------+
#property version "0.10"
#property strict
#include <Trade\Trade.mqh>

input int    InpSessions       = 6;      // bit mask: 1 Asia, 2 London, 4 New York (Asia runs in GoldScalperM15)
input double InpRiskPct        = 0.5;    // risk % of equity per trade (each system)
input double InpSL_ATR         = 4.0;
input double InpMinDailyATRPct = 1.6;
input int    InpMinConfidence  = 1;
input double InpMaxSpread      = 1.0;
input int    InpNewsMins       = 15;
input string InpNewsFile       = "GS15_news_USD.csv";
input int    InpCloseHour      = 19;     // server; no new trades from here
input int    InpHolidayCloseHour = 18;
input double InpMaxDailyLossPct = 3.0;
input ulong  InpMagicBase      = 20261100; // + 1 Asia, + 2 London, + 3 New York

CTrade trade;
int hATR, hATRD1, hEMA50D1, hEMA200H1, hADXH1, hRSI;
datetime lastBar = 0, newsT[];
bool newsLoaded = false;
string journal = "GS15_journal_GOLD_20261013_tester.csv";
double dayStartBal = 0; int dayKey = 0;
int tradedDay[4];                    // day key of the last trade per system
double riskOpen[4];                  // money at risk of each system's open trade
ulong  openTicket[4];
datetime openTime[4];
// overlap statistics
int    overlapEntries = 0;           // entries made while another system had a position
double maxDayRiskPct = 0;            // highest sum of open risk (% of equity) seen

string SysName(int s) { return s == 1 ? "ASIA" : s == 2 ? "LONDON" : "NEWYORK"; }
void Note(string m) { string full = "GS_Sessions " + _Symbol + ": " + m; Print(full); if(!MQLInfoInteger(MQL_TESTER)) SendNotification(full); }

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER))
   {
      if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO) { Alert("GS_Sessions: demo accounts only"); return INIT_FAILED; }
      for(long c = ChartFirst(); c >= 0; c = ChartNext(c))
         if(c != ChartID() && ChartSymbol(c) == _Symbol && ChartGetString(c, CHART_EXPERT_NAME) == MQLInfoString(MQL_PROGRAM_NAME))
         { Alert("GS_Sessions already runs on another chart"); return INIT_FAILED; }
      // restore today's state after a restart: a system that already traded today does not trade again
      MqlDateTime t; TimeToStruct(TimeCurrent(), t); int key = t.year * 1000 + t.day_of_year;
      datetime d0 = TimeCurrent() - TimeCurrent() % 86400;
      if(HistorySelect(d0, TimeCurrent() + 60))
         for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
         {
            ulong d = HistoryDealGetTicket(i); long mg = HistoryDealGetInteger(d, DEAL_MAGIC);
            if(mg > (long)InpMagicBase && mg <= (long)InpMagicBase + 3 && HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN) tradedDay[(int)(mg - (long)InpMagicBase)] = key;
         }
      Note(StringFormat("GS_Sessions started (London %s, New York %s), risk %.2f%% per system", (InpSessions & 2) ? "on" : "off", (InpSessions & 4) ? "on" : "off", InpRiskPct));
   }
   ArrayInitialize(tradedDay, 0); ArrayInitialize(riskOpen, 0); ArrayInitialize(openTicket, 0);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);
   hATR = iATR(_Symbol, PERIOD_M15, 14);
   hATRD1 = iATR(_Symbol, PERIOD_D1, 14);
   hEMA50D1 = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200H1 = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hADXH1 = iADX(_Symbol, PERIOD_H1, 14);
   hRSI = iRSI(_Symbol, PERIOD_M15, 14, PRICE_CLOSE);

   if(MQLInfoInteger(MQL_TESTER)) FileDelete(journal, FILE_COMMON); else journal = "GS_Sessions_journal_GOLD.csv";
   int f = FileIsExist(journal, FILE_COMMON) ? INVALID_HANDLE : FileOpen(journal, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(f != INVALID_HANDLE) { FileWrite(f, "system", "dir", "open", "close", "pl", "r", "risk", "overlap"); FileClose(f); }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintFormat("SESSIONS stats: entries while another system was open %d, max open risk %.2f%% of equity", overlapEntries, maxDayRiskPct);
}

double B(int h, int buf, int sh) { double v[1]; return CopyBuffer(h, buf, sh, 1, v) == 1 ? v[0] : EMPTY_VALUE; }

//--- calendar rules (same as the live EA v1.53)
datetime MakeDate(int y, int m, int d) { MqlDateTime t; ZeroMemory(t); t.year = y; t.mon = m; t.day = d; return StructToTime(t); }
int NthDow(int y, int m, int dow, int n)
{
   if(n > 0) { MqlDateTime t; TimeToStruct(MakeDate(y, m, 1), t); return 1 + (dow - t.day_of_week + 7) % 7 + (n - 1) * 7; }
   for(int last = 31; last > 20; last--) { MqlDateTime t; TimeToStruct(MakeDate(y, m, last), t); if(t.mon == m && t.day_of_week == dow) return last; }
   return 31;
}
bool UsDstDay(datetime day) { MqlDateTime t; TimeToStruct(day, t); return day >= MakeDate(t.year, 3, NthDow(t.year, 3, 0, 2)) && day < MakeDate(t.year, 11, NthDow(t.year, 11, 0, 1)); }
bool EuDstDay(datetime day) { MqlDateTime t; TimeToStruct(day, t); return day >= MakeDate(t.year, 3, NthDow(t.year, 3, 0, -1)) && day < MakeDate(t.year, 10, NthDow(t.year, 10, 0, -1)); }
bool Mismatch(datetime day) { return UsDstDay(day) != EuDstDay(day); }
bool USEarlyClose(datetime day)
{
   MqlDateTime t; TimeToStruct(day, t); int y = t.year, m = t.mon, d = t.day, w = t.day_of_week;
   if(m == 1 && d == NthDow(y, 1, 1, 3)) return true;
   if(m == 2 && d == NthDow(y, 2, 1, 3)) return true;
   if(m == 5 && d == NthDow(y, 5, 1, -1)) return true;
   if(m == 9 && d == NthDow(y, 9, 1, 1)) return true;
   if(m == 11 && (d == NthDow(y, 11, 4, 4) || d == NthDow(y, 11, 4, 4) + 1)) return true;
   if(m == 12 && (d == 24 || d == 31) && w >= 1 && w <= 5) return true;
   if(m == 7 && ((d == 4 && w >= 1 && w <= 5) || (d == 3 && w == 5) || (d == 5 && w == 1))) return true;
   if(y >= 2022 && m == 6 && ((d == 19 && w >= 1 && w <= 5) || (d == 18 && w == 5) || (d == 20 && w == 1))) return true;
   return false;
}
datetime Deadline(datetime day) { return day + (USEarlyClose(day) ? InpHolidayCloseHour : InpCloseHour) * 3600; }

// Range and entry window of a system on a server day (server times).
void Window(int s, datetime day, datetime &rs, datetime &re, datetime &es, datetime &ee)
{
   if(s == 1) { rs = day; re = day + 8 * 3600; es = re; ee = day + 18 * 3600; return; }
   if(s == 2) { int off = Mismatch(day) ? 3 : 2; rs = day + (8 + off) * 3600; re = rs + 3600; es = re; ee = day + (12 + off) * 3600; return; }
   rs = day + 15 * 3600; re = rs + 3600; es = re; ee = day + 18 * 3600;   // New York 08-09 / entries 09-11 NY
}

//--- news
bool UsDst(datetime gmt) { return UsDstDay(gmt - gmt % 86400); }
bool NewsBlocked()
{
   if(!newsLoaded)
   {
      newsLoaded = true;
      int f = FileOpen(InpNewsFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
      if(f == INVALID_HANDLE) return false;
      FileReadString(f);
      int n = 0;
      while(!FileIsEnding(f))
      {
         string p[];
         if(StringSplit(FileReadString(f), ',', p) < 4) continue;
         if((int)StringToInteger(p[2]) < 3 || p[1] != "USD") continue;
         datetime t = StringToTime(p[0]);
         ArrayResize(newsT, n + 1, 4096);
         newsT[n++] = t + (UsDst(t) ? 3 : 2) * 3600;
      }
      FileClose(f);
      ArraySort(newsT);
   }
   int n = ArraySize(newsT); if(n == 0) return false;
   datetime now = TimeCurrent(), lo = now - InpNewsMins * 60;
   int a = 0, b = n;
   while(a < b) { int mid = (a + b) / 2; if(newsT[mid] < lo) a = mid + 1; else b = mid; }
   return a < n && newsT[a] <= now + InpNewsMins * 60;
}

int Confidence(int dir)
{
   int sc = 0;
   double e50 = B(hEMA50D1, 0, 1), c1 = iClose(_Symbol, PERIOD_D1, 1);
   if(e50 != EMPTY_VALUE && (dir > 0 ? c1 > e50 : c1 < e50)) sc++;
   double e200 = B(hEMA200H1, 0, 1), ch = iClose(_Symbol, PERIOD_H1, 1);
   if(e200 != EMPTY_VALUE && (dir > 0 ? ch > e200 : ch < e200)) sc++;
   double adx = B(hADXH1, 0, 1);
   if(adx != EMPTY_VALUE && adx >= 20 && adx <= 30) sc++;
   double rsi = B(hRSI, 0, 1);
   if(rsi != EMPTY_VALUE && (dir > 0 ? rsi >= 70 : rsi <= 30)) sc++;
   return sc;
}

double LotsFor(double slDist, double &risk)
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double perLot = (slDist + 30 * _Point) / ts * tv;      // + slippage allowance, like the live EA
   double lots = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0 / perLot;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < mn) return 0;
   risk = lots * slDist / ts * tv;
   return lots;
}

ulong PosOf(int s)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) { ulong t = PositionGetTicket(i); if(t && PositionGetInteger(POSITION_MAGIC) == (long)(InpMagicBase + s)) return t; }
   return 0;
}

void OnTradeTransaction(const MqlTradeTransaction &tr, const MqlTradeRequest &rq, const MqlTradeResult &rs)
{
   if(tr.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tr.deal)) return;
   long mg = HistoryDealGetInteger(tr.deal, DEAL_MAGIC);
   int s = (int)(mg - (long)InpMagicBase);
   if(s < 1 || s > 3 || HistoryDealGetInteger(tr.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   double pl = HistoryDealGetDouble(tr.deal, DEAL_PROFIT) + HistoryDealGetDouble(tr.deal, DEAL_SWAP) + HistoryDealGetDouble(tr.deal, DEAL_COMMISSION);
   int f = FileOpen(journal, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(f != INVALID_HANDLE)
   {
      FileSeek(f, 0, SEEK_END);
      FileWrite(f, SysName(s), HistoryDealGetInteger(tr.deal, DEAL_TYPE) == DEAL_TYPE_SELL ? "BUY" : "SELL", TimeToString(openTime[s]),
                TimeToString(TimeCurrent()), DoubleToString(pl, 2), DoubleToString(riskOpen[s] > 0 ? pl / riskOpen[s] : 0, 3),
                DoubleToString(riskOpen[s], 2), openTicket[s] == 1 ? 1 : 0);
      FileClose(f);
   }
   if(!MQLInfoInteger(MQL_TESTER)) Note(StringFormat("%s closed | P/L %.2f (%.2f R)", SysName(s), pl, riskOpen[s] > 0 ? pl / riskOpen[s] : 0));
   riskOpen[s] = 0;
}

double TodayPL()
{
   datetime d0 = TimeCurrent() - TimeCurrent() % 86400;
   double p = 0;
   if(HistorySelect(d0, TimeCurrent() + 60))
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong d = HistoryDealGetTicket(i);
         long mg = HistoryDealGetInteger(d, DEAL_MAGIC);
         if(mg > (long)InpMagicBase && mg <= (long)InpMagicBase + 3)
            p += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
      }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i); long mg = PositionGetInteger(POSITION_MAGIC);
      if(t && mg > (long)InpMagicBase && mg <= (long)InpMagicBase + 3) p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return p;
}

void OnTick()
{
   datetime now = TimeCurrent(), day = now - now % 86400;
   MqlDateTime t; TimeToStruct(now, t);
   int key = t.year * 1000 + t.day_of_year;
   if(key != dayKey) { dayKey = key; dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE); }

   // close at the deadline (and anything left from an earlier day)
   datetime dl = Deadline(day);
   for(int s = 1; s <= 3; s++)
   {
      ulong p = PosOf(s);
      if(p > 0 && PositionSelectByTicket(p) && (now >= dl || (datetime)PositionGetInteger(POSITION_TIME) < day))
      { trade.SetExpertMagicNumber(InpMagicBase + s); trade.PositionClose(p); }
   }
   // open risk statistics
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), openRisk = 0;
   for(int s = 1; s <= 3; s++) if(PosOf(s) > 0) openRisk += riskOpen[s];
   if(eq > 0) maxDayRiskPct = MathMax(maxDayRiskPct, openRisk / eq * 100.0);

   datetime bar = iTime(_Symbol, PERIOD_M15, 0);
   if(bar == lastBar) return;
   lastBar = bar;
   if(now >= dl || t.day_of_week == 0 || t.day_of_week == 6) return;
   if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID) > InpMaxSpread) return;
   if(NewsBlocked()) return;
   if(InpMaxDailyLossPct > 0 && TodayPL() <= -dayStartBal * InpMaxDailyLossPct / 100.0) return;
   double d1atr = B(hATRD1, 0, 1), d1c = iClose(_Symbol, PERIOD_D1, 1);
   if(InpMinDailyATRPct > 0 && (d1atr == EMPTY_VALUE || d1c <= 0 || d1atr / d1c * 100.0 < InpMinDailyATRPct)) return;
   double atr = B(hATR, 0, 1);
   if(atr == EMPTY_VALUE || atr <= 0) return;

   datetime b1 = iTime(_Symbol, PERIOD_M15, 1);
   double c1 = iClose(_Symbol, PERIOD_M15, 1), c2 = iClose(_Symbol, PERIOD_M15, 2);
   for(int s = 1; s <= 3; s++)
   {
      if((InpSessions & (1 << (s - 1))) == 0 || tradedDay[s] == key || PosOf(s) > 0) continue;
      datetime rs, re, es, ee;
      Window(s, day, rs, re, es, ee);
      if(b1 < es || now >= ee || now >= dl) continue;      // the signal bar must close after the range
      double hs[], ls[];
      if(CopyHigh(_Symbol, PERIOD_M15, rs, re - 1, hs) < 2 || CopyLow(_Symbol, PERIOD_M15, rs, re - 1, ls) < 2) continue;
      double hi = hs[ArrayMaximum(hs)], lo = ls[ArrayMinimum(ls)];
      int dir = (c1 > hi && c2 <= hi) ? 1 : (c1 < lo && c2 >= lo) ? -1 : 0;
      if(dir == 0) continue;
      if(InpMinConfidence > 0 && Confidence(dir) < InpMinConfidence) continue;
      double slDist = InpSL_ATR * atr, risk = 0;
      double lots = LotsFor(slDist, risk);
      if(lots <= 0) continue;
      double px = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizeDouble(dir > 0 ? px - slDist : px + slDist, _Digits);
      bool others = false;
      for(int o = 1; o <= 3; o++) if(o != s && PosOf(o) > 0) others = true;
      trade.SetExpertMagicNumber(InpMagicBase + s);
      if(dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, 0, SysName(s)) : trade.Sell(lots, _Symbol, 0, sl, 0, SysName(s)))
      {
         tradedDay[s] = key; riskOpen[s] = risk; openTime[s] = now; openTicket[s] = others ? 1 : 0;
         if(others) overlapEntries++;
         if(!MQLInfoInteger(MQL_TESTER)) Note(StringFormat("%s opened %s %.2f lot | range %.2f-%.2f | SL %.2f | risk %.2f", SysName(s), dir > 0 ? "BUY" : "SELL", lots, lo, hi, sl, risk));
      }
   }
}
