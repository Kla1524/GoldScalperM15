//+------------------------------------------------------------------+
//| GS15_Lab.mq5 - Strategy Tester experiments only (never on a       |
//| live chart). Two ideas from a YouTube clip, tested against the     |
//| live system (Asian-range breakout, 1 trade a day, 0.5 % risk):     |
//|  1 = EMA 20/50 + Stochastic pullback, many trades, fixed risk      |
//|  2 = RSI martingale grid: lot x2 on each step against, basket      |
//|      closed at a profit target or at a basket stop (% of equity)   |
//|  3 = news straddle (TikTok clip): BUY STOP + SELL STOP around the  |
//|      price before NFP / CPI / Fed decisions, one cancels the other |
//+------------------------------------------------------------------+
#property copyright "GoldScalper lab"
#property version   "0.10"
#property strict

#include <Trade\Trade.mqh>

input group "=== General ==="
input int    InpStrategy      = 1;        // 1 = EMA20/50 + Stochastic, 2 = RSI martingale grid, 3 = news straddle
input ulong  InpMagic         = 20261017; // Magic number
input double InpMaxSpread     = 1.00;     // Max spread for a new entry (price units)
input int    InpStartHour     = 1;        // New entries from (hour, server time)
input int    InpEndHour       = 23;       // No new entries from (hour, server time)
input bool   InpCloseFriday   = true;     // Close everything before the weekend
input int    InpFridayCloseHour = 21;     // Friday close hour (server time)

input group "=== News filter (tester file, same as the live EA) ==="
input bool   InpNewsInTester   = true;    // Block new entries around high-impact USD news
input int    InpNewsMinsBefore = 15;      // Minutes before the event
input int    InpNewsMinsAfter  = 15;      // Minutes after the event
input string InpNewsFile       = "GS15_news_USD.csv"; // Common\Files

input group "=== 1: EMA 20/50 + Stochastic ==="
input double InpRiskPct     = 0.5;   // Risk % of equity per trade
input int    InpEmaFast     = 20;    // Fast EMA
input int    InpEmaSlow     = 50;    // Slow EMA (the pullback line)
input int    InpStochK      = 14;    // Stochastic %K
input int    InpStochD      = 3;     // Stochastic %D
input int    InpStochSlow   = 3;     // Stochastic slowing
input double InpStochLow    = 20;    // Oversold level (buys)
input double InpStochHigh   = 80;    // Overbought level (sells)
input int    InpTouchBars   = 3;     // The pullback touched the slow EMA within this many closed bars
input int    InpSLPts       = 0;     // SL in points (0 = ATR based)
input int    InpTPPts       = 0;     // TP in points (0 = R multiple of the SL)
input int    InpATRPeriod   = 14;    // ATR period
input double InpSL_ATR      = 1.5;   // SL = ATR x (when InpSLPts = 0)
input double InpTP_R        = 1.0;   // TP = SL x (when InpTPPts = 0)
input int    InpMaxTradesDay = 0;    // Max trades a day (0 = unlimited)

input group "=== 2: RSI martingale grid ==="
input double InpBaseLot     = 0.50;  // First lot (clip: 0.01 on a $200 account = 0.50 on $10,000)
input double InpLotMult     = 2.0;   // Lot multiplier for each added level
input int    InpMaxLevels   = 4;     // Max orders in a basket (0.01, 0.02, 0.04, 0.08 = 4)
input int    InpGridStepPts = 500;   // Add a level after the price moves this many points against the last entry
input int    InpRSIPeriod   = 14;    // RSI period
input double InpRSIHigh     = 70;    // RSI crosses up through this -> SELL
input double InpRSILow      = 30;    // RSI crosses down through this -> BUY
input int    InpBasketTPPts = 300;   // Close the basket when its profit >= first lot x this many points
input double InpBasketSLPct = 27.5;  // Close the basket when its loss >= this % of the equity at its start (clip: $55 of $200)

input group "=== 3: news straddle ==="
input string InpNEvents      = "Nonfarm Payrolls,CPI,Fed Interest Rate Decision"; // Exact event names ("" = every high-impact USD event)
input int    InpNMinsBefore  = 2;     // Place the two stop orders this many minutes before the event
input int    InpNDistPts     = 300;   // Distance of each stop order from the price (points; 100 points = $1)
input int    InpNSLPts       = 500;   // SL (points from the order price)
input int    InpNTPPts       = 1000;  // TP (points, 0 = none)
input int    InpNTrailPts    = 0;     // Trailing SL distance once in profit by this much (points, 0 = off)
input int    InpNExpiryMin   = 10;    // Delete orders not filled this many minutes after the event
input int    InpNHoldMin     = 60;    // Close the trade this many minutes after the event

CTrade trade;
datetime evT[];
int      evI = 0;
datetime evDone = 0;
int      nEvents = 0, nFilled = 0, nBoth = 0, nWins = 0;
double   nSlipSum = 0, nSlipMax = 0;
int      nSlipCount = 0;
int hEmaF = INVALID_HANDLE, hEmaS = INVALID_HANDLE, hSto = INVALID_HANDLE, hAtr = INVALID_HANDLE, hRsi = INVALID_HANDLE;
datetime lastBar = 0;
datetime newsT[];
bool newsLoaded = false;
double basketStartEq = 0;
int    dayTrades = 0, dayKey = 0;
int    maxLevelsSeen = 0;
double maxBasketLot = 0, worstBasket = 0;

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER))
   {
      Alert("GS15_Lab is for the Strategy Tester only");
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);
   hAtr = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   if(InpStrategy == 1)
   {
      hEmaF = iMA(_Symbol, PERIOD_M15, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
      hEmaS = iMA(_Symbol, PERIOD_M15, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
      hSto  = iStochastic(_Symbol, PERIOD_M15, InpStochK, InpStochD, InpStochSlow, MODE_SMA, STO_LOWHIGH);
   }
   else
      hRsi = iRSI(_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(InpStrategy == 3)
      PrintFormat("LAB news stats: events %d, filled %d, both sides filled %d, avg entry slippage %.0f pts, max %.0f pts",
                  nEvents, nFilled, nBoth, nSlipCount > 0 ? nSlipSum / nSlipCount : 0.0, nSlipMax);
   if(InpStrategy == 2)
      PrintFormat("LAB grid stats: max levels %d, max basket lot %.2f, worst basket %.2f", maxLevelsSeen, maxBasketLot, worstBasket);
}

double Buf(int h, int buf, int shift)
{
   double v[1];
   if(CopyBuffer(h, buf, shift, 1, v) != 1) return EMPTY_VALUE;
   return v[0];
}

//--- news (same file and windows as the live EA's tester mode)
bool UsDst(datetime gmt)
{
   MqlDateTime d; TimeToStruct(gmt, d);
   MqlDateTime m; ZeroMemory(m); m.year = d.year; m.mon = 3; m.day = 1;
   datetime mar1 = StructToTime(m); TimeToStruct(mar1, m);
   int sunMar = 1 + (7 - m.day_of_week) % 7;
   datetime st = mar1 + (sunMar + 7 - 1) * 86400 + 7 * 3600;
   ZeroMemory(m); m.year = d.year; m.mon = 11; m.day = 1;
   datetime nov1 = StructToTime(m); TimeToStruct(nov1, m);
   int sunNov = 1 + (7 - m.day_of_week) % 7;
   datetime en = nov1 + (sunNov - 1) * 86400 + 6 * 3600;
   return gmt >= st && gmt < en;
}

bool NewsBlocked()
{
   if(!InpNewsInTester) return false;
   if(!newsLoaded)
   {
      newsLoaded = true;
      int f = FileOpen(InpNewsFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
      if(f == INVALID_HANDLE) { Print("LAB: news file not found - filter off"); return false; }
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
      PrintFormat("LAB: %d news events loaded", n);
   }
   int n = ArraySize(newsT);
   if(n == 0) return false;
   datetime now = TimeCurrent(), lo = now - InpNewsMinsAfter * 60;
   int a = 0, b = n;
   while(a < b) { int mid = (a + b) / 2; if(newsT[mid] < lo) a = mid + 1; else b = mid; }
   return a < n && newsT[a] <= now + InpNewsMinsBefore * 60;
}

bool EntryAllowed()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(t.hour < InpStartHour || t.hour >= InpEndHour) return false;
   if(t.day_of_week == 5 && t.hour >= InpFridayCloseHour - 1) return false;
   if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID) > InpMaxSpread) return false;
   if(NewsBlocked()) return false;
   return true;
}

double NormLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / step + 1e-9) * step;
   return MathMax(mn, MathMin(mx, lot));
}

double MoneyPerPointLot()
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return tv / ts * _Point;   // money for 1 point with 1 lot
}

int CountPos(double &lots, double &profit, double &lastPrice, double &lastLot, int &dir)
{
   int n = 0; lots = 0; profit = 0; lastPrice = 0; lastLot = 0; dir = 0;
   long lastT = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetInteger(POSITION_MAGIC) != (long)InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      n++;
      double v = PositionGetDouble(POSITION_VOLUME);
      lots += v;
      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      long ot = PositionGetInteger(POSITION_TIME_MSC);
      if(ot >= lastT) { lastT = ot; lastPrice = PositionGetDouble(POSITION_PRICE_OPEN); lastLot = v; }
   }
   return n;
}

void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetInteger(POSITION_MAGIC) != (long)InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      trade.PositionClose(tk);
   }
}

bool MarginOk(ENUM_ORDER_TYPE type, double lot)
{
   double price = type == ORDER_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double m;
   if(!OrderCalcMargin(type, _Symbol, lot, price, m)) return false;
   return m < AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9;
}

//--- 1: EMA 20/50 + Stochastic
void Strategy1(bool newBar)
{
   if(!newBar) return;
   double lots, profit, lp, ll; int dir;
   if(CountPos(lots, profit, lp, ll, dir) > 0) return;
   if(InpMaxTradesDay > 0 && dayTrades >= InpMaxTradesDay) return;
   if(!EntryAllowed()) return;
   double ef = Buf(hEmaF, 0, 1), es = Buf(hEmaS, 0, 1);
   double k1 = Buf(hSto, 0, 1), d1 = Buf(hSto, 1, 1), k2 = Buf(hSto, 0, 2), d2 = Buf(hSto, 1, 2);
   double atr = Buf(hAtr, 0, 1);
   if(ef == EMPTY_VALUE || es == EMPTY_VALUE || k1 == EMPTY_VALUE || atr == EMPTY_VALUE) return;
   double c1 = iClose(_Symbol, PERIOD_M15, 1);
   bool touchL = false, touchH = false;
   for(int i = 1; i <= InpTouchBars; i++)
   {
      double e = Buf(hEmaS, 0, i);
      if(iLow(_Symbol, PERIOD_M15, i) <= e)  touchL = true;
      if(iHigh(_Symbol, PERIOD_M15, i) >= e) touchH = true;
   }
   int sig = 0;
   if(ef > es && c1 > es && touchL && k2 <= d2 && k1 > d1 && MathMin(k1, k2) < InpStochLow)  sig = 1;
   if(ef < es && c1 < es && touchH && k2 >= d2 && k1 < d1 && MathMax(k1, k2) > InpStochHigh) sig = -1;
   if(sig == 0) return;
   double slDist = InpSLPts > 0 ? InpSLPts * _Point : InpSL_ATR * atr;
   double tpDist = InpTPPts > 0 ? InpTPPts * _Point : InpTP_R * slDist;
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
   double lot = NormLot(riskMoney / (slDist / _Point * MoneyPerPointLot()));
   if(lot * slDist / _Point * MoneyPerPointLot() > riskMoney * 1.5) return;   // min lot too big for the risk
   ENUM_ORDER_TYPE type = sig > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!MarginOk(type, lot)) return;
   double px = sig > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble(px - sig * slDist, _Digits), tp = NormalizeDouble(px + sig * tpDist, _Digits);
   if(trade.PositionOpen(_Symbol, type, lot, px, sl, tp, "lab ema-stoch"))
      dayTrades++;
}

//--- 2: RSI martingale grid
void Strategy2(bool newBar)
{
   double lots, profit, lastPx, lastLot; int dir;
   int n = CountPos(lots, profit, lastPx, lastLot, dir);
   double mpp = MoneyPerPointLot();
   if(n > 0)
   {
      if(profit < worstBasket) worstBasket = profit;
      // basket exits
      if(profit >= InpBaseLot * InpBasketTPPts * mpp) { CloseAll(); return; }
      if(basketStartEq > 0 && -profit >= basketStartEq * InpBasketSLPct / 100.0) { CloseAll(); return; }
      // add a level against the basket
      if(n < InpMaxLevels)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         bool add = dir > 0 ? (lastPx - ask) >= InpGridStepPts * _Point : (bid - lastPx) >= InpGridStepPts * _Point;
         if(add)
         {
            double lot = NormLot(lastLot * InpLotMult);
            ENUM_ORDER_TYPE type = dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            if(MarginOk(type, lot) && trade.PositionOpen(_Symbol, type, lot, dir > 0 ? ask : bid, 0, 0, "lab grid L" + IntegerToString(n + 1)))
            {
               maxLevelsSeen = MathMax(maxLevelsSeen, n + 1);
               maxBasketLot = MathMax(maxBasketLot, lots + lot);
            }
         }
      }
      return;
   }
   if(!newBar || !EntryAllowed()) return;
   double r1 = Buf(hRsi, 0, 1), r2 = Buf(hRsi, 0, 2);
   if(r1 == EMPTY_VALUE || r2 == EMPTY_VALUE) return;
   int sig = 0;
   if(r2 < InpRSIHigh && r1 >= InpRSIHigh) sig = -1;
   if(r2 > InpRSILow && r1 <= InpRSILow)   sig = 1;
   if(sig == 0) return;
   double lot = NormLot(InpBaseLot);
   ENUM_ORDER_TYPE type = sig > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!MarginOk(type, lot)) return;
   basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(trade.PositionOpen(_Symbol, type, lot, sig > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID), 0, 0, "lab grid L1"))
   {
      maxLevelsSeen = MathMax(maxLevelsSeen, 1);
      maxBasketLot = MathMax(maxBasketLot, lot);
   }
}

//--- 3: news straddle
void LoadEvents()
{
   int f = FileOpen(InpNewsFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(f == INVALID_HANDLE) { Print("LAB: news file not found"); return; }
   FileReadString(f);
   int n = 0;
   while(!FileIsEnding(f))
   {
      string q[];
      if(StringSplit(FileReadString(f), ',', q) < 4) continue;
      if((int)StringToInteger(q[2]) < 3 || q[1] != "USD") continue;
      if(InpNEvents != "" && StringFind("," + InpNEvents + ",", "," + q[3] + ",") < 0) continue;
      datetime t = StringToTime(q[0]);
      t += (UsDst(t) ? 3 : 2) * 3600;
      if(n > 0 && evT[n - 1] == t) continue;   // CPI, CPI m/m, CPI y/y at the same time
      ArrayResize(evT, n + 1, 1024);
      evT[n++] = t;
   }
   FileClose(f);
   ArraySort(evT);
   PrintFormat("LAB: %d news events for the straddle", n);
}

int CountOrders()
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk > 0 && OrderGetInteger(ORDER_MAGIC) == (long)InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol) n++;
   }
   return n;
}

void DeleteOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk > 0 && OrderGetInteger(ORDER_MAGIC) == (long)InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
         trade.OrderDelete(tk);
   }
}

void Strategy3()
{
   static bool loaded = false;
   if(!loaded) { loaded = true; LoadEvents(); }
   int n = ArraySize(evT);
   datetime now = TimeCurrent();
   while(evI < n && evT[evI] + InpNHoldMin * 60 < now && evT[evI] != evDone) evI++;
   double lots, profit, lp, ll; int dir;
   int pos = CountPos(lots, profit, lp, ll, dir);
   int ord = CountOrders();
   if(pos > 0 && ord > 0) DeleteOrders();                       // one filled: cancel the other
   if(pos > 0 && InpNTrailPts > 0)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
         bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
         double px = buy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
         double gain = (buy ? px - open : open - px) / _Point;
         if(gain < InpNTrailPts) continue;
         double nsl = NormalizeDouble(buy ? px - InpNTrailPts * _Point : px + InpNTrailPts * _Point, _Digits);
         if((buy && nsl > sl + _Point) || (!buy && (sl == 0 || nsl < sl - _Point)))
            trade.PositionModify(tk, nsl, PositionGetDouble(POSITION_TP));
      }
   }
   if(evDone > 0)
   {
      if(ord > 0 && now >= evDone + InpNExpiryMin * 60) DeleteOrders();
      if(pos > 0 && now >= evDone + InpNHoldMin * 60) CloseAll();
      if(now >= evDone + InpNHoldMin * 60) evDone = 0;
      return;
   }
   if(evI >= n || pos > 0 || ord > 0) return;
   datetime ev = evT[evI];
   if(now < ev - InpNMinsBefore * 60 || now >= ev) return;
   MqlDateTime t; TimeToStruct(now, t);
   if(t.day_of_week == 5 && t.hour >= InpFridayCloseHour - 1) return;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double risk = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
   double lot = NormLot(risk / (InpNSLPts * MoneyPerPointLot()));
   if(lot * InpNSLPts * MoneyPerPointLot() > risk * 1.5) return;
   double b = NormalizeDouble(ask + InpNDistPts * _Point, _Digits), sP = NormalizeDouble(bid - InpNDistPts * _Point, _Digits);
   trade.BuyStop(lot, b, _Symbol, NormalizeDouble(b - InpNSLPts * _Point, _Digits), InpNTPPts > 0 ? NormalizeDouble(b + InpNTPPts * _Point, _Digits) : 0, ORDER_TIME_GTC, 0, "lab news buy");
   trade.SellStop(lot, sP, _Symbol, NormalizeDouble(sP + InpNSLPts * _Point, _Digits), InpNTPPts > 0 ? NormalizeDouble(sP - InpNTPPts * _Point, _Digits) : 0, ORDER_TIME_GTC, 0, "lab news sell");
   evDone = ev;
   nEvents++;
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(InpStrategy != 3 || trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagic) return;
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
   {
      static datetime lastEv = 0;
      if(lastEv == evDone) nBoth++; else nFilled++;
      lastEv = evDone;
      ulong ord = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
      if(HistoryOrderSelect(ord))
      {
         double slip = MathAbs(HistoryDealGetDouble(trans.deal, DEAL_PRICE) - HistoryOrderGetDouble(ord, ORDER_PRICE_OPEN)) / _Point;
         nSlipSum += slip; nSlipCount++; nSlipMax = MathMax(nSlipMax, slip);
      }
   }
   else if(HistoryDealGetDouble(trans.deal, DEAL_PROFIT) > 0) nWins++;
}

void OnTick()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   int key = t.year * 1000 + t.day_of_year;
   if(key != dayKey) { dayKey = key; dayTrades = 0; }
   if(InpCloseFriday && t.day_of_week == 5 && t.hour >= InpFridayCloseHour)
   {
      CloseAll();
      return;
   }
   datetime bar = iTime(_Symbol, PERIOD_M15, 0);
   bool newBar = bar != lastBar;
   lastBar = bar;
   if(InpStrategy == 1)      Strategy1(newBar);
   else if(InpStrategy == 2) Strategy2(newBar);
   else                      Strategy3();
}
