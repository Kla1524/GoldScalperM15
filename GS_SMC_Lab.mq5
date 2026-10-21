//+------------------------------------------------------------------+
//| GS_SMC_Lab.mq5 - Strategy Tester research only (refuses a live    |
//| chart). ICT / smart-money building blocks and trading models on   |
//| GOLD M15, each trade logged with the market regime at entry so    |
//| models can be matched to regimes (trend / sideways) afterwards.   |
//|                                                                    |
//| Building blocks: fractal swings, BOS / CHoCH (MSS) with           |
//| displacement, FVG (+ CE), order block, liquidity levels (Asian    |
//| range, previous day high/low), sweeps (SFP / turtle soup),        |
//| killzones, H1 bias, regime (ADX H1, Bollinger width).             |
//| Models (InpModel):                                                |
//|  1 Sweep - MSS - FVG retest (Asian range / PDH-PDL liquidity)     |
//|  2 Turtle soup / SFP at PDH-PDL                                   |
//|  3 Silver bullet: first FVG with the H1 bias in 10-11 / 17-18 srv |
//|  4 Order block retest after a BOS with displacement, H1 bias      |
//|  5 Range fade: Bollinger re-entry + RSI, sideways regime only     |
//| Rules shared with the live EA: SL always, risk % per trade, no    |
//| entries around high-impact USD news (file), no new trades after   |
//| the daily close, everything closed before the swap rollover.      |
//+------------------------------------------------------------------+
#property version "0.10"
#property strict
#include <Trade\Trade.mqh>

input group "=== General ==="
input int    InpModel          = 1;      // 1 sweep-MSS-FVG, 2 turtle soup, 3 silver bullet, 4 OB retest, 5 range fade
input double InpRiskPct        = 0.5;    // Risk % of equity per trade
input double InpRR             = 2.0;    // TP = R multiple of the SL distance (0 = no TP, daily close only)
input int    InpMaxTradesDay   = 3;      // Max trades a day for this model
input ulong  InpMagic          = 20261021;
input int    InpDailyCloseHour = 19;     // Close everything (server time); no new trades after it
input int    InpFridayCloseHour = 19;    // Friday close (server time)
input double InpMaxSpread      = 1.0;    // Max spread for an entry (price units)
input int    InpSLBufPts       = 50;     // Extra SL distance beyond the swing / sweep (points)
input double InpMinSL_ATR      = 0.5;    // SL at least this many M15 ATR
input double InpMaxSL_ATR      = 4.0;    // Skip setups whose SL is wider than this many ATR
input int    InpOrderBars      = 8;      // Pending entry orders expire after this many M15 bars

input group "=== Structure / zones ==="
input int    InpSwingLen       = 2;      // Fractal swing: bars on each side
input double InpDisplaceATR    = 1.0;    // Displacement candle: body >= ATR x
input int    InpSweepWindow    = 12;     // Bars after a sweep in which the MSS must come (model 1)
input bool   InpUseCE          = false;  // Enter at the FVG midpoint (consequent encroachment) instead of its edge

input group "=== Sessions (server time) ==="
input int    InpKZ1Start = 9;            // Killzone 1 (London) start
input int    InpKZ1End   = 12;           // Killzone 1 end
input int    InpKZ2Start = 14;           // Killzone 2 (New York) start
input int    InpKZ2End   = 18;           // Killzone 2 end
input int    InpRangeEndHour = 8;        // Asian range 00:00 - this hour

input group "=== Regime ==="
input int    InpRegimeFilter = 0;        // 0 off, 1 trend only (ADX H1 >= InpADXTrend), 2 sideways only (ADX H1 < InpADXRange)
input double InpADXTrend     = 25;
input double InpADXRange     = 20;

input group "=== News (tester file) ==="
input bool   InpNews = true;
input int    InpNewsMins = 15;
input string InpNewsFile = "GS15_news_USD.csv";

CTrade trade;
int hATR, hADX, hEMA50H1, hEMA200H1, hBB, hRSI;
datetime lastBar = 0;
datetime newsT[]; bool newsLoaded = false;
int dayKey = 0, tradesToday = 0;

// state
double swHi[3], swLo[3]; datetime swHiT[3], swLoT[3];   // last swings, [0] = latest
int    trendDir = 0;                                     // M15 structure: 1 up, -1 down
datetime sweepT = 0; int sweepDir = 0; double sweepExt = 0; // sweep of BSL -> sweepDir -1 (look for sells)

// journal of the open trade
struct Entry { ulong ticket; double risk; string model; double adx, bbw, atr; int bias; datetime t; };
Entry cur; bool curValid = false;
string journal = "GS15_journal_GOLD_20261013_tester.csv";

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER)) { Alert("GS_SMC_Lab is for the Strategy Tester only"); return INIT_FAILED; }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);
   hATR = iATR(_Symbol, PERIOD_M15, 14);
   hADX = iADX(_Symbol, PERIOD_H1, 14);
   hEMA50H1 = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200H1 = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hBB = iBands(_Symbol, PERIOD_M15, 20, 0, 2.0, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, PERIOD_M15, 14, PRICE_CLOSE);
   ArrayInitialize(swHi, 0); ArrayInitialize(swLo, 0);
   FileDelete(journal, FILE_COMMON);
   int f = FileOpen(journal, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(f != INVALID_HANDLE)
   {
      FileWrite(f, "model", "dir", "open", "close", "pl", "r", "adx_h1", "bb_width_atr", "atr", "h1_bias", "hour");
      FileClose(f);
   }
   return INIT_SUCCEEDED;
}

double B(int h, int buf, int sh) { double v[1]; return CopyBuffer(h, buf, sh, 1, v) == 1 ? v[0] : EMPTY_VALUE; }
double O(int i) { return iOpen(_Symbol, PERIOD_M15, i); }
double H(int i) { return iHigh(_Symbol, PERIOD_M15, i); }
double Lw(int i) { return iLow(_Symbol, PERIOD_M15, i); }
double C(int i) { return iClose(_Symbol, PERIOD_M15, i); }

//--- news (same file and DST rule as the live EA)
bool UsDst(datetime gmt)
{
   MqlDateTime d; TimeToStruct(gmt, d);
   MqlDateTime m; ZeroMemory(m); m.year = d.year; m.mon = 3; m.day = 1;
   datetime mar1 = StructToTime(m); TimeToStruct(mar1, m);
   datetime st = mar1 + ((1 + (7 - m.day_of_week) % 7) + 7 - 1) * 86400 + 7 * 3600;
   ZeroMemory(m); m.year = d.year; m.mon = 11; m.day = 1;
   datetime nov1 = StructToTime(m); TimeToStruct(nov1, m);
   datetime en = nov1 + ((1 + (7 - m.day_of_week) % 7) - 1) * 86400 + 6 * 3600;
   return gmt >= st && gmt < en;
}
bool NewsBlocked()
{
   if(!InpNews) return false;
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

//--- helpers
int Hour() { MqlDateTime t; TimeToStruct(TimeCurrent(), t); return t.hour; }
int Dow()  { MqlDateTime t; TimeToStruct(TimeCurrent(), t); return t.day_of_week; }
bool InKillzone(int h) { return (h >= InpKZ1Start && h < InpKZ1End) || (h >= InpKZ2Start && h < InpKZ2End); }
int  CloseHourToday() { return Dow() == 5 ? MathMin(InpDailyCloseHour, InpFridayCloseHour) : InpDailyCloseHour; }

int H1Bias()
{
   double e50 = B(hEMA50H1, 0, 1), e200 = B(hEMA200H1, 0, 1), c = iClose(_Symbol, PERIOD_H1, 1);
   if(e50 == EMPTY_VALUE || e200 == EMPTY_VALUE) return 0;
   if(c > e50 && e50 > e200) return 1;
   if(c < e50 && e50 < e200) return -1;
   return 0;
}
bool RegimeOK()
{
   if(InpRegimeFilter == 0) return true;
   double adx = B(hADX, 0, 1);
   if(adx == EMPTY_VALUE) return false;
   return InpRegimeFilter == 1 ? adx >= InpADXTrend : adx < InpADXRange;
}

int CountMine(bool orders)
{
   int n = 0;
   if(orders)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--) { ulong t = OrderGetTicket(i); if(t && OrderGetInteger(ORDER_MAGIC) == (long)InpMagic) n++; }
   }
   else
      for(int i = PositionsTotal() - 1; i >= 0; i--) { ulong t = PositionGetTicket(i); if(t && PositionGetInteger(POSITION_MAGIC) == (long)InpMagic) n++; }
   return n;
}
void CloseAllMine()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) { ulong t = PositionGetTicket(i); if(t && PositionGetInteger(POSITION_MAGIC) == (long)InpMagic) trade.PositionClose(t); }
   for(int i = OrdersTotal() - 1; i >= 0; i--) { ulong t = OrderGetTicket(i); if(t && OrderGetInteger(ORDER_MAGIC) == (long)InpMagic) trade.OrderDelete(t); }
}

double LotsFor(double slDist)
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double perLot = slDist / ts * tv;
   if(perLot <= 0) return 0;
   double lots = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0 / perLot;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < mn) return 0;   // strict risk: never above the target
   return MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
}

// Market or pending entry; SL given as a price; TP from InpRR.
void Enter(int dir, double price, double sl, bool pending, string model)
{
   double atr = B(hATR, 0, 1);
   double dist = MathAbs(price - sl);
   if(atr == EMPTY_VALUE || dist < InpMinSL_ATR * atr) { sl = dir > 0 ? price - InpMinSL_ATR * atr : price + InpMinSL_ATR * atr; dist = MathAbs(price - sl); }
   if(dist > InpMaxSL_ATR * atr) return;
   double lots = LotsFor(dist);
   if(lots <= 0) return;
   double tp = InpRR > 0 ? (dir > 0 ? price + InpRR * dist : price - InpRR * dist) : 0;
   price = NormalizeDouble(price, _Digits); sl = NormalizeDouble(sl, _Digits); tp = NormalizeDouble(tp, _Digits);
   datetime exp = TimeCurrent() + InpOrderBars * 900;
   datetime closeT = TimeCurrent() - TimeCurrent() % 86400 + CloseHourToday() * 3600;
   if(exp > closeT) exp = closeT;
   bool ok;
   if(!pending)
      ok = dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, tp, model) : trade.Sell(lots, _Symbol, 0, sl, tp, model);
   else
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(dir > 0 && price >= ask) ok = trade.Buy(lots, _Symbol, 0, sl, tp, model);
      else if(dir < 0 && price <= bid) ok = trade.Sell(lots, _Symbol, 0, sl, tp, model);
      else if(exp <= TimeCurrent() + 60) return;
      else ok = dir > 0 ? trade.BuyLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, exp, model)
                        : trade.SellLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, exp, model);
   }
   if(ok)
   {
      tradesToday++;
      cur.risk = lots * dist / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      cur.model = model; cur.adx = B(hADX, 0, 1); cur.atr = atr; cur.bias = H1Bias(); cur.t = TimeCurrent();
      double up = B(hBB, 1, 1), lo = B(hBB, 2, 1);
      cur.bbw = (up != EMPTY_VALUE && atr > 0) ? (up - lo) / atr : 0;
      curValid = true;
   }
}

void OnTradeTransaction(const MqlTradeTransaction &tr, const MqlTradeRequest &rq, const MqlTradeResult &rs)
{
   if(tr.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tr.deal)) return;
   if(HistoryDealGetInteger(tr.deal, DEAL_MAGIC) != (long)InpMagic) return;
   if(HistoryDealGetInteger(tr.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT || !curValid) return;
   double pl = HistoryDealGetDouble(tr.deal, DEAL_PROFIT) + HistoryDealGetDouble(tr.deal, DEAL_SWAP) + HistoryDealGetDouble(tr.deal, DEAL_COMMISSION);
   int dir = HistoryDealGetInteger(tr.deal, DEAL_TYPE) == DEAL_TYPE_SELL ? 1 : -1;
   int f = FileOpen(journal, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(f != INVALID_HANDLE)
   {
      FileSeek(f, 0, SEEK_END);
      MqlDateTime t; TimeToStruct(cur.t, t);
      FileWrite(f, cur.model, dir > 0 ? "BUY" : "SELL", TimeToString(cur.t), TimeToString(TimeCurrent()), DoubleToString(pl, 2),
                DoubleToString(cur.risk > 0 ? pl / cur.risk : 0, 3), DoubleToString(cur.adx, 1), DoubleToString(cur.bbw, 2),
                DoubleToString(cur.atr, 2), cur.bias, t.hour);
      FileClose(f);
   }
   curValid = false;
}

//--- structure update on each closed bar
void UpdateSwings()
{
   int L = InpSwingLen, i = L + 1;   // candidate pivot bar (fully confirmed)
   bool isHi = true, isLo = true;
   for(int k = 1; k <= L; k++)
   {
      if(H(i) <= H(i - k) || H(i) <= H(i + k)) isHi = false;
      if(Lw(i) >= Lw(i - k) || Lw(i) >= Lw(i + k)) isLo = false;
   }
   datetime t = iTime(_Symbol, PERIOD_M15, i);
   if(isHi && t != swHiT[0]) { for(int k = 2; k > 0; k--) { swHi[k] = swHi[k - 1]; swHiT[k] = swHiT[k - 1]; } swHi[0] = H(i); swHiT[0] = t; }
   if(isLo && t != swLoT[0]) { for(int k = 2; k > 0; k--) { swLo[k] = swLo[k - 1]; swLoT[k] = swLoT[k - 1]; } swLo[0] = Lw(i); swLoT[0] = t; }
}

// BOS / CHoCH on bar 1: +1 bullish break with displacement, -1 bearish, 0 none.
int StructureBreak()
{
   double atr = B(hATR, 0, 1);
   if(atr == EMPTY_VALUE || swHi[0] == 0 || swLo[0] == 0) return 0;
   bool displaced = MathAbs(C(1) - O(1)) >= InpDisplaceATR * atr;
   if(C(1) > swHi[0] && C(2) <= swHi[0] && displaced) return 1;
   if(C(1) < swLo[0] && C(2) >= swLo[0] && displaced) return -1;
   return 0;
}

// Latest FVG on bars 3-2-1 in a direction: true + zone.
bool FVG(int dir, double &top, double &bot)
{
   if(dir > 0 && Lw(1) > H(3)) { top = Lw(1); bot = H(3); return true; }
   if(dir < 0 && H(1) < Lw(3)) { top = Lw(3); bot = H(1); return true; }
   return false;
}

bool AsianRange(double &hi, double &lo)
{
   datetime d0 = TimeCurrent() - TimeCurrent() % 86400;
   double hs[], ls[];
   if(CopyHigh(_Symbol, PERIOD_M15, d0, d0 + InpRangeEndHour * 3600 - 1, hs) < 4 || CopyLow(_Symbol, PERIOD_M15, d0, d0 + InpRangeEndHour * 3600 - 1, ls) < 4) return false;
   hi = hs[ArrayMaximum(hs)]; lo = ls[ArrayMinimum(ls)];
   return true;
}

// Bar 1 swept a level: wick through, close back on the other side.
int SweepOf(double hiLvl, double loLvl, double &ext)
{
   if(hiLvl > 0 && H(1) > hiLvl && C(1) < hiLvl) { ext = H(1); return -1; }   // BSL taken -> look for sells
   if(loLvl > 0 && Lw(1) < loLvl && C(1) > loLvl) { ext = Lw(1); return 1; }  // SSL taken -> look for buys
   return 0;
}

void OnTick()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   int key = t.year * 1000 + t.day_of_year;
   if(key != dayKey) { dayKey = key; tradesToday = 0; sweepT = 0; }
   if(t.hour >= CloseHourToday()) { if(CountMine(false) + CountMine(true) > 0) CloseAllMine(); return; }
   datetime bar = iTime(_Symbol, PERIOD_M15, 0);
   if(bar == lastBar) return;
   lastBar = bar;

   UpdateSwings();
   int brk = StructureBreak();
   if(brk != 0) trendDir = brk;

   if(t.hour < 1) return;
   if(CountMine(false) > 0 || CountMine(true) > 0) return;      // one setup at a time per model
   if(tradesToday >= InpMaxTradesDay) return;
   if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID) > InpMaxSpread) return;
   if(NewsBlocked() || !RegimeOK()) return;
   double atr = B(hATR, 0, 1);
   if(atr == EMPTY_VALUE) return;
   double buf = InpSLBufPts * _Point;
   double pdh = iHigh(_Symbol, PERIOD_D1, 1), pdl = iLow(_Symbol, PERIOD_D1, 1);

   if(InpModel == 1)   // Sweep - MSS - FVG retest
   {
      double ah, al;
      if(t.hour >= InpRangeEndHour && AsianRange(ah, al))
      {
         double ext; int sd = SweepOf(MathMax(ah, 0), al, ext);
         if(sd == 0) sd = SweepOf(pdh, pdl, ext);
         if(sd != 0 && InKillzone(t.hour)) { sweepT = bar; sweepDir = sd; sweepExt = ext; }
         else if(sweepT > 0 && sd == sweepDir) sweepExt = sweepDir < 0 ? MathMax(sweepExt, ext) : MathMin(sweepExt, ext);
      }
      if(sweepT > 0 && (bar - sweepT) / 900 <= InpSweepWindow && brk == sweepDir)
      {
         double top, bot;
         if(FVG(sweepDir, top, bot))
         {
            double entry = InpUseCE ? (top + bot) / 2 : (sweepDir > 0 ? top : bot);
            double sl = sweepDir > 0 ? sweepExt - buf : sweepExt + buf;
            Enter(sweepDir, entry, sl, true, "M1_sweep_mss_fvg");
            sweepT = 0;
         }
      }
   }
   else if(InpModel == 2)   // Turtle soup / SFP at PDH-PDL
   {
      double ext; int sd = SweepOf(pdh, pdl, ext);
      if(sd != 0 && InKillzone(t.hour))
         Enter(sd, sd > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID), sd > 0 ? ext - buf : ext + buf, false, "M2_turtle_soup");
   }
   else if(InpModel == 3)   // Silver bullet
   {
      if((t.hour == 10 || t.hour == 17))
      {
         int bias = H1Bias(); double top, bot;
         if(bias != 0 && FVG(bias, top, bot) && MathAbs(C(2) - O(2)) >= InpDisplaceATR * atr * 0.5)
         {
            double entry = InpUseCE ? (top + bot) / 2 : (bias > 0 ? top : bot);
            double sl = bias > 0 ? Lw(3) - buf : H(3) + buf;
            Enter(bias, entry, sl, true, "M3_silver_bullet");
         }
      }
   }
   else if(InpModel == 4)   // Order block retest after BOS with displacement, with the H1 bias
   {
      int bias = H1Bias();
      if(brk != 0 && brk == bias && InKillzone(t.hour))
      {
         // order block = last opposite-colour candle before the displacement bar (bars 2..6)
         for(int i = 2; i <= 6; i++)
         {
            bool opp = brk > 0 ? C(i) < O(i) : C(i) > O(i);
            if(!opp) continue;
            double entry = brk > 0 ? H(i) : Lw(i);
            double sl = brk > 0 ? Lw(i) - buf : H(i) + buf;
            Enter(brk, entry, sl, true, "M4_ob_retest");
            break;
         }
      }
   }
   else if(InpModel == 5)   // Range fade (sideways)
   {
      double adx = B(hADX, 0, 1), up = B(hBB, 1, 1), lo = B(hBB, 2, 1), mid = B(hBB, 0, 1), up2 = B(hBB, 1, 2), lo2 = B(hBB, 2, 2), rsi = B(hRSI, 0, 1);
      if(adx != EMPTY_VALUE && adx < InpADXRange && rsi != EMPTY_VALUE)
      {
         if(C(2) < lo2 && C(1) > lo && rsi < 40)
            Enter(1, SymbolInfoDouble(_Symbol, SYMBOL_ASK), Lw(1) - 1.0 * atr, false, "M5_range_fade");
         else if(C(2) > up2 && C(1) < up && rsi > 60)
            Enter(-1, SymbolInfoDouble(_Symbol, SYMBOL_BID), H(1) + 1.0 * atr, false, "M5_range_fade");
      }
   }
}
