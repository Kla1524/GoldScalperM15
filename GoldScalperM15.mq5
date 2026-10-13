//+------------------------------------------------------------------+
//|                                              GoldScalperM15.mq5  |
//|  XAUUSD M15 intraday EA. Default (v1.30): Asian-range breakout    |
//|  on volatile days, wide ATR stop, flat by 20:00 (no swap).         |
//|  Other selectable strategies: EMA pullback, Donchian, RSI(2).     |
//|  Fixed lot, ATR-based SL/TP, breakeven, trailing stop,            |
//|  session / spread / daily-trade / daily-loss / news filters,      |
//|  on-chart control panel and phone push notifications.             |
//+------------------------------------------------------------------+
#property copyright "Personal EA"
#property version   "1.31"
#property description "XAUUSD M15 intraday - Asian-range breakout, volatility & news filters, panel"

#include <Trade\Trade.mqh>

enum ENUM_STRATEGY
{
   STRAT_PULLBACK = 0,  // EMA pullback (v1.x)
   STRAT_BREAKOUT = 1,  // Donchian breakout ตามเทรนด์
   STRAT_RSI2     = 2,  // RSI(2) ย่อตัวในเทรนด์
   STRAT_ORB      = 3   // Opening Range Breakout (กรอบราคาช่วงเช้า)
};

enum ENUM_LOT_MODE
{
   LOT_FIXED = 0,  // Lot คงที่
   LOT_RISK  = 1   // คำนวณจาก % ความเสี่ยง (Balance × Risk% ÷ SL)
};

//--- inputs
input group "=== ทั่วไป ==="
input ENUM_LOT_MODE   InpLotMode         = LOT_FIXED; // วิธีกำหนด Lot
input double          InpLots            = 0.01;      // Lot คงที่ (ใช้เมื่อเลือก Lot คงที่)
input double          InpRiskPct         = 1.0;       // % ความเสี่ยงต่อไม้ (ใช้เมื่อเลือกคำนวณจาก %)
input ulong           InpMagic           = 20261013;  // Magic number
input ENUM_TIMEFRAMES InpTF              = PERIOD_M15;// Timeframe สัญญาณ
input ENUM_STRATEGY   InpStrategy        = STRAT_ORB; // กลยุทธ์
input bool            InpAllowBuy        = true;      // อนุญาตฝั่ง Buy
input bool            InpAllowSell       = true;      // อนุญาตฝั่ง Sell

input group "=== สัญญาณเข้า ==="
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_CURRENT; // TF ของ EMA เทรนด์ (CURRENT = ใช้ TF สัญญาณ)
input int    InpTrendEMA    = 200;   // EMA เทรนด์
input int    InpFastEMA     = 9;     // [Pullback] EMA เร็ว
input int    InpSlowEMA     = 21;    // [Pullback] EMA ช้า
input int    InpBreakoutBars = 20;   // [Breakout] จำนวนแท่ง Donchian
input int    InpRSI2Period  = 2;     // [RSI2] RSI period
input double InpRSI2Entry   = 10.0;  // [RSI2] Buy เมื่อ RSI < x (Sell เมื่อ > 100-x)
input double InpRSI2Exit    = 70.0;  // [RSI2] ปิด Buy เมื่อ RSI > x (ปิด Sell เมื่อ < 100-x, 0 = ปิด)
input bool   InpUseTrend    = false; // ใช้ตัวกรอง EMA เทรนด์ (Pullback ใช้เสมอ)
input int    InpRangeStartHour = 0;  // [ORB] เริ่มวัดกรอบ (ชั่วโมง เวลาเซิร์ฟเวอร์)
input int    InpRangeEndHour   = 8;  // [ORB] จบกรอบ / เริ่มรอเบรก (ชั่วโมง)
input int    InpRSIPeriod   = 14;    // [Pullback] RSI period
input double InpRSIBuyMin   = 50.0;  // RSI ขั้นต่ำฝั่ง Buy
input double InpRSIBuyMax   = 70.0;  // RSI สูงสุดฝั่ง Buy (กันไล่ราคา)
input double InpRSISellMin  = 30.0;  // RSI ขั้นต่ำฝั่ง Sell (กันไล่ราคา)
input double InpRSISellMax  = 50.0;  // RSI สูงสุดฝั่ง Sell

input group "=== SL / TP (คูณ ATR) ==="
input int    InpATRPeriod   = 14;    // ATR period
input double InpSL_ATR      = 4.0;   // SL = ATR x
input double InpTP_ATR      = 0.0;   // TP = ATR x (0 = ไม่ตั้ง TP)
input double InpBE_ATR      = 0.0;   // เลื่อน Breakeven เมื่อกำไร >= ATR x (0 = ปิด)
input double InpTrail_ATR   = 0.0;   // Trailing ห่าง ATR x (0 = ปิด)
input double InpTrailStart_ATR = -1; // เริ่ม Trailing เมื่อกำไร >= ATR x (-1 = เท่ากับระยะ Trailing)

input group "=== ตัวกรอง ==="
input int    InpStartHour       = 0;    // เริ่มเทรด (ชั่วโมง เวลาเซิร์ฟเวอร์)
input int    InpEndHour         = 18;   // หยุดเปิดไม้ใหม่ (ชั่วโมง เวลาเซิร์ฟเวอร์)
input double InpMaxSpread       = 1.00; // สเปรดสูงสุด (หน่วยราคา เช่น 0.40 = 40 cents)
input double InpMinATR          = 0.0;  // ATR ขั้นต่ำ (หน่วยราคา, 0 = ปิด) กันตลาดนิ่ง
input double InpMinDailyATRPct  = 1.6;  // ATR รายวันขั้นต่ำ เป็น % ของราคา (0 = ปิด) เทรดเฉพาะวันที่ผันผวนพอ
input double InpMaxRiskPct      = 5.0;  // ข้ามไม้ถ้า SL เสียเกิน % ของบาลานซ์ (0 = ปิด)
input int    InpMaxTradesPerDay = 1;    // จำนวนไม้สูงสุดต่อวัน
input double InpMaxDailyLossPct = 3.0;  // หยุดเทรดเมื่อขาดทุนวันนี้ >= % ของบาลานซ์ (0 = ปิด)
input int    InpDailyCloseHour  = 20;   // ปิดออเดอร์ทุกวันเมื่อถึงชั่วโมงนี้ (หลบ swap, -1 = ปิด)
input bool   InpCloseFriday     = true; // ปิดออเดอร์ก่อนตลาดปิดวันศุกร์
input int    InpFridayCloseHour = 21;   // ชั่วโมงที่ปิดวันศุกร์ (เวลาเซิร์ฟเวอร์)

input group "=== ตัวกรองข่าว (ปฏิทินเศรษฐกิจ MT5) ==="
input bool   InpNewsFilter       = true;   // เปิดใช้ตัวกรองข่าว
input string InpNewsCurrencies   = "USD";  // สกุลเงินที่กรอง (คั่นด้วย , เช่น USD,EUR)
input bool   InpNewsHighOnly     = true;   // true = เฉพาะข่าวแรง, false = ข่าวกลาง+แรง
input int    InpNewsMinsBefore   = 30;     // งดเปิดไม้ก่อนข่าว (นาที)
input int    InpNewsMinsAfter    = 30;     // งดเปิดไม้หลังข่าว (นาที)
input bool   InpNewsClosePos     = false;  // ปิดออเดอร์ที่เปิดอยู่เมื่อเข้าช่วงข่าว

input group "=== แจ้งเตือน ==="
input bool   InpNotifyPush   = true;   // ส่ง Push เข้าแอป MT5 บนมือถือ
input bool   InpNotifyPopup  = false;  // แสดงหน้าต่าง Alert บนคอม
input bool   InpNotifyTrades = true;   // แจ้งเตือน เปิด/ปิดไม้ และเลื่อน Breakeven
input bool   InpNotifyNews   = true;   // แจ้งเตือน เข้า/ออกช่วงข่าว

input group "=== แผงควบคุมบนกราฟ ==="
input bool   InpShowPanel = true;  // แสดงแผงควบคุม
input int    InpPanelX    = 10;    // ตำแหน่งแผง X (พิกเซล)
input int    InpPanelY    = 30;    // ตำแหน่งแผง Y (พิกเซล)

//--- globals
#define PFX "GS15_"

CTrade   trade;
int      hFast, hSlow, hTrend, hRSI, hRSI2, hATR, hATRD1;
datetime lastBarTime     = 0;
datetime newsLastCheck   = 0;
bool     newsBlocked     = false;
string   newsBlockInfo   = "";
string   newsNextInfo    = "";
bool     paused          = false;
string   gvPaused        = "";
int      lossNotifiedDay = -1;
bool     showPanel       = false;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpFastEMA >= InpSlowEMA)
   {
      Print("InpFastEMA ต้องน้อยกว่า InpSlowEMA");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLotMode == LOT_RISK && (InpRiskPct <= 0 || (InpMaxRiskPct > 0 && InpRiskPct > InpMaxRiskPct)))
   {
      Print("InpRiskPct ต้องมากกว่า 0 และไม่เกิน InpMaxRiskPct (", InpMaxRiskPct, "%) - ไม่อย่างนั้นทุกไม้จะถูกข้าม");
      return INIT_PARAMETERS_INCORRECT;
   }

   hFast  = iMA(_Symbol, InpTF, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, InpTF, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   ENUM_TIMEFRAMES trendTF = (InpTrendTF == PERIOD_CURRENT) ? InpTF : InpTrendTF;
   hTrend = iMA(_Symbol, trendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, InpTF, InpRSIPeriod, PRICE_CLOSE);
   hRSI2  = iRSI(_Symbol, InpTF, InpRSI2Period, PRICE_CLOSE);
   hATR   = iATR(_Symbol, InpTF, InpATRPeriod);
   hATRD1 = iATR(_Symbol, PERIOD_D1, 14);

   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hTrend == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hRSI2 == INVALID_HANDLE || hATR == INVALID_HANDLE ||
      hATRD1 == INVALID_HANDLE)
   {
      Print("สร้าง indicator ไม่สำเร็จ: ", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);

   // Pause state survives timeframe changes and terminal restarts.
   gvPaused = PFX + "paused_" + _Symbol + "_" + (string)InpMagic;
   paused   = GlobalVariableCheck(gvPaused) && GlobalVariableGet(gvPaused) > 0;

   showPanel = InpShowPanel && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));
   if(showPanel)
      CreatePanel();

   EventSetTimer(1);
   RefreshStatus();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
   IndicatorRelease(hFast);
   IndicatorRelease(hSlow);
   IndicatorRelease(hTrend);
   IndicatorRelease(hRSI);
   IndicatorRelease(hRSI2);
   IndicatorRelease(hATR);
   IndicatorRelease(hATRD1);
}

//+------------------------------------------------------------------+
//| Optimizer score (Strategy Tester only): recovery factor, but     |
//| zero for unprofitable or statistically thin results.             |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   double profit = TesterStatistics(STAT_PROFIT);
   double pf     = TesterStatistics(STAT_PROFIT_FACTOR);
   if(trades < 150 || profit <= 0 || pf < 1.1)
      return 0;
   return TesterStatistics(STAT_RECOVERY_FACTOR);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   RefreshStatus();
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions();

   if(InpCloseFriday && IsFridayClose())
   {
      if(CountPositions() > 0)
      {
         CloseAll();
         Notify("ปิดออเดอร์ทั้งหมดก่อนตลาดปิดวันศุกร์");
      }
      return;
   }

   if(InpDailyCloseHour >= 0 && CountPositions() > 0)
   {
      MqlDateTime now;
      TimeToStruct(TimeCurrent(), now);
      if(now.hour >= InpDailyCloseHour)
         CloseAll();
   }

   bool newsNow = NewsBlackout();
   if(newsNow && InpNewsClosePos && CountPositions() > 0)
   {
      CloseAll();
      Notify("ปิดออเดอร์เพราะเข้าช่วงข่าว: " + newsBlockInfo);
   }

   if(!IsNewBar())
      return;

   ExitOnSignal();

   if(CountPositions() > 0)
      return;

   int    tradesToday;
   double profitToday;
   GetTodayStats(tradesToday, profitToday);
   if(BlockReason(tradesToday, profitToday) != "")
      return;

   double atr[];
   if(!GetBuf(hATR, atr))
      return;
   double a = atr[0];
   if(InpMinATR > 0 && a < InpMinATR) return;

   int signal = GetSignal();
   if(signal > 0 && InpAllowBuy)       OpenTrade(ORDER_TYPE_BUY,  a);
   else if(signal < 0 && InpAllowSell) OpenTrade(ORDER_TYPE_SELL, a);
}

//+------------------------------------------------------------------+
//| Entry signals, evaluated on the last closed bar of InpTF.        |
//| Returns +1 buy, -1 sell, 0 none.                                 |
//+------------------------------------------------------------------+
int GetSignal()
{
   double trend[];
   if(!GetBuf(hTrend, trend))
      return 0;

   double o = iOpen(_Symbol, InpTF, 1);
   double h = iHigh(_Symbol, InpTF, 1);
   double l = iLow(_Symbol, InpTF, 1);
   double c = iClose(_Symbol, InpTF, 1);

   switch(InpStrategy)
   {
      case STRAT_PULLBACK:
      {
         double fast[], slow[], rsi[];
         if(!GetBuf(hFast, fast) || !GetBuf(hSlow, slow) || !GetBuf(hRSI, rsi))
            return 0;
         if(c > trend[0] && fast[0] > slow[0]       // uptrend
            && l <= fast[0] && c > fast[0]           // dipped into EMA9 and closed back above
            && c > o                                 // bullish candle
            && rsi[0] >= InpRSIBuyMin && rsi[0] <= InpRSIBuyMax)
            return 1;
         if(c < trend[0] && fast[0] < slow[0]       // downtrend
            && h >= fast[0] && c < fast[0]           // spiked into EMA9 and closed back below
            && c < o                                 // bearish candle
            && rsi[0] >= InpRSISellMin && rsi[0] <= InpRSISellMax)
            return -1;
         return 0;
      }

      case STRAT_BREAKOUT:
      {
         // close beyond the highest high / lowest low of the N bars before the signal bar
         int hi = iHighest(_Symbol, InpTF, MODE_HIGH, InpBreakoutBars, 2);
         int lo = iLowest(_Symbol, InpTF, MODE_LOW, InpBreakoutBars, 2);
         if(hi < 0 || lo < 0)
            return 0;
         if(c > iHigh(_Symbol, InpTF, hi) && TrendOK(1, c, trend[0]))  return 1;
         if(c < iLow(_Symbol, InpTF, lo)  && TrendOK(-1, c, trend[0])) return -1;
         return 0;
      }

      case STRAT_ORB:
      {
         // Today's range between InpRangeStartHour and InpRangeEndHour (server time);
         // signal on the first close beyond it after the range has formed.
         datetime barTime = iTime(_Symbol, InpTF, 1);
         MqlDateTime bt;
         TimeToStruct(barTime, bt);
         if(bt.hour < InpRangeEndHour)
            return 0;
         datetime day0 = barTime - (barTime % 86400);
         datetime rs = day0 + InpRangeStartHour * 3600;
         datetime re = day0 + InpRangeEndHour * 3600 - 1;
         double hs[], ls[];
         if(CopyHigh(_Symbol, InpTF, rs, re, hs) < 2 || CopyLow(_Symbol, InpTF, rs, re, ls) < 2)
            return 0;
         double rHigh = hs[ArrayMaximum(hs)];
         double rLow  = ls[ArrayMinimum(ls)];
         double prev  = iClose(_Symbol, InpTF, 2);
         if(c > rHigh && prev <= rHigh && TrendOK(1, c, trend[0]))  return 1;
         if(c < rLow  && prev >= rLow  && TrendOK(-1, c, trend[0])) return -1;
         return 0;
      }

      case STRAT_RSI2:
      {
         double r[];
         if(!GetBuf(hRSI2, r))
            return 0;
         if(r[0] < InpRSI2Entry && TrendOK(1, c, trend[0]))          return 1;
         if(r[0] > 100.0 - InpRSI2Entry && TrendOK(-1, c, trend[0])) return -1;
         return 0;
      }
   }
   return 0;
}

// Trend filter shared by the non-pullback strategies (can be switched off).
bool TrendOK(int dir, double close, double trendEma)
{
   if(!InpUseTrend)
      return true;
   return dir > 0 ? close > trendEma : close < trendEma;
}

// Strategy-specific exits checked once per new bar.
void ExitOnSignal()
{
   if(InpStrategy != STRAT_RSI2 || InpRSI2Exit <= 0)
      return;

   double r[];
   if(!GetBuf(hRSI2, r))
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsMine())
         continue;
      bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      if((isBuy && r[0] > InpRSI2Exit) || (!isBuy && r[0] < 100.0 - InpRSI2Exit))
         trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Close notifications (SL / TP / manual / EA close)                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(!InpNotifyTrades || trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic ||
      HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   // The closing deal goes the opposite way of the position.
   string side = HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_SELL ? "BUY" : "SELL";
   double pl   = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
               + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
               + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   long   why  = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string how  = why == DEAL_REASON_TP ? "ถึง TP" : why == DEAL_REASON_SL ? "โดน SL" : "ปิดไม้";

   Notify(StringFormat("%s %s @ %s | P/L %.2f %s", how, side,
                       DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits),
                       pl, AccountInfoString(ACCOUNT_CURRENCY)));
}

//+------------------------------------------------------------------+
//| Panel buttons                                                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == PFX + "btnPause")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      paused = !paused;
      GlobalVariableSet(gvPaused, paused ? 1 : 0);
      Print(paused ? "หยุดเปิดไม้ใหม่ชั่วคราว (ออเดอร์ที่ถืออยู่ยังดูแล SL/TP ต่อ)" : "กลับมาเทรดตามปกติ");
   }
   else if(sparam == PFX + "btnClose")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      int n = CountPositions();
      if(n == 0)
         Print("ไม่มีออเดอร์ของ EA นี้ให้ปิด");
      else if(MQLInfoInteger(MQL_TESTER) ||
              MessageBox(StringFormat("ปิดออเดอร์ของ EA นี้ทั้งหมด %d ไม้?", n),
                         "GoldScalperM15", MB_YESNO | MB_ICONQUESTION) == IDYES)
      {
         CloseAll();
         Notify(StringFormat("ปิดออเดอร์ทั้งหมด %d ไม้ (กดปุ่มบนแผง)", n));
      }
   }
   else
      return;

   RefreshStatus();
}

//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double atr)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist = MinStopDistance();

   double slDist = MathMax(atr * InpSL_ATR, minDist);
   double tpDist = MathMax(atr * InpTP_ATR, minDist);
   double lots   = CalcLots(slDist);

   bool   isBuy = type == ORDER_TYPE_BUY;
   double price = isBuy ? ask : bid;
   double sl    = NormPrice(isBuy ? ask - slDist : bid + slDist);
   double tp    = InpTP_ATR > 0 ? NormPrice(isBuy ? ask + tpDist : bid - tpDist) : 0;   // 0 = no TP
   string side  = isBuy ? "BUY" : "SELL";

   // Skip when the stop is so far away that one loss would exceed InpMaxRiskPct of balance.
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = LossPerLot(slDist) * lots;          // money lost if SL is hit (0 = unknown)
   if(InpMaxRiskPct > 0 && riskMoney > balance * InpMaxRiskPct / 100.0)
   {
      NotifyFailure(StringFormat("ข้าม %s: SL เสี่ยง %.2f (%.1f%% ของบาลานซ์) เกินกำหนด %.1f%%", side,
                                 riskMoney, riskMoney / balance * 100.0, InpMaxRiskPct));
      return;
   }
   // Skip (and warn at most once a day) when free margin can't cover the order.
   double margin;
   if(OrderCalcMargin(type, _Symbol, lots, price, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      NotifyFailure(StringFormat("มาร์จิ้นไม่พอเปิด %s %.2f lot (ต้องใช้ %.2f, มี %.2f)", side, lots,
                                 margin, AccountInfoDouble(ACCOUNT_MARGIN_FREE)));
      return;
   }

   bool ok = isBuy ? trade.Buy(lots, _Symbol, ask, sl, tp, "GoldScalper BUY")
                   : trade.Sell(lots, _Symbol, bid, sl, tp, "GoldScalper SELL");
   if(ok)
   {
      if(InpNotifyTrades)
         Notify(StringFormat("เปิด %s %.2f lot @ %s | SL %s | TP %s | เสี่ยง %.2f %s (%.1f%%)", side, lots,
                             DoubleToString(trade.ResultPrice() > 0 ? trade.ResultPrice() : price, _Digits),
                             DoubleToString(sl, _Digits), DoubleToString(tp, _Digits),
                             riskMoney, AccountInfoString(ACCOUNT_CURRENCY),
                             balance > 0 ? riskMoney / balance * 100.0 : 0));
   }
   else
      NotifyFailure(StringFormat("เปิด %s ไม่สำเร็จ: %d %s", side, trade.ResultRetcode(),
                                 trade.ResultRetcodeDescription()));
}

// Failures can repeat every bar; log each one but alert the phone at most once a day.
void NotifyFailure(string msg)
{
   static int lastDay = -1;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year == lastDay)
   {
      Print(msg);
      return;
   }
   lastDay = dt.day_of_year;
   Notify(msg + " (แจ้งครั้งเดียวต่อวัน)");
}

//+------------------------------------------------------------------+
//| Breakeven + trailing stop for this EA's positions                |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(InpBE_ATR <= 0 && InpTrail_ATR <= 0)
      return;

   double atr[];
   if(!GetBuf(hATR, atr))
      return;
   double a       = atr[0];
   double minDist = MinStopDistance();
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double trailStart = InpTrailStart_ATR < 0 ? InpTrail_ATR : InpTrailStart_ATR;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsMine())
         continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      long   type = PositionGetInteger(POSITION_TYPE);
      double target = 0;   // proposed SL; 0 = nothing to do
      bool   beNow  = false;

      if(type == POSITION_TYPE_BUY)
      {
         double gain = bid - open;
         if(InpBE_ATR > 0 && gain >= a * InpBE_ATR)
         {
            target = open + a * 0.1;                      // lock a small profit
            beNow  = sl < open;
         }
         if(InpTrail_ATR > 0 && gain >= a * trailStart)
            target = MathMax(target, bid - a * InpTrail_ATR);
         if(target <= 0)
            continue;
         target = NormPrice(MathMin(target, bid - minDist));
         if(target > sl + _Point && trade.PositionModify(ticket, target, tp) && beNow && InpNotifyTrades)
            Notify(StringFormat("เลื่อน SL ไม้ BUY มาที่ทุนแล้ว (SL %s)", DoubleToString(target, _Digits)));
      }
      else
      {
         double gain = open - ask;
         if(InpBE_ATR > 0 && gain >= a * InpBE_ATR)
         {
            target = open - a * 0.1;
            beNow  = sl == 0 || sl > open;
         }
         if(InpTrail_ATR > 0 && gain >= a * trailStart)
            target = (target > 0) ? MathMin(target, ask + a * InpTrail_ATR) : ask + a * InpTrail_ATR;
         if(target <= 0)
            continue;
         target = NormPrice(MathMax(target, ask + minDist));
         if((sl == 0 || target < sl - _Point) && trade.PositionModify(ticket, target, tp) && beNow && InpNotifyTrades)
            Notify(StringFormat("เลื่อน SL ไม้ SELL มาที่ทุนแล้ว (SL %s)", DoubleToString(target, _Digits)));
      }
   }
}

//+------------------------------------------------------------------+
//| Status / notifications                                           |
//+------------------------------------------------------------------+
// Why no new trade may be opened right now ("" = allowed).
string BlockReason(int tradesToday, double profitToday)
{
   if(paused)                             return "หยุดชั่วคราว (กดปุ่ม)";
   if(newsBlocked)                        return "งดเทรด ช่วงข่าว";
   if(DailyLossHit(profitToday))          return "ถึงเพดานขาดทุนวันนี้";
   if(tradesToday >= InpMaxTradesPerDay)  return "ครบจำนวนไม้วันนี้";
   if(!InSession())                       return "นอกเวลาเทรด";
   if(!SpreadOK())                        return "สเปรดกว้างเกิน";
   if(!VolatilityOK())                    return "ความผันผวนต่ำ - รอวันที่ตลาดวิ่ง";
   return "";
}

// Called every second by the timer and after button clicks.
void RefreshStatus()
{
   NewsBlackout();

   int    tradesToday;
   double profitToday;
   GetTodayStats(tradesToday, profitToday);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(DailyLossHit(profitToday) && lossNotifiedDay != dt.day_of_year)
   {
      lossNotifiedDay = dt.day_of_year;
      Notify(StringFormat("ขาดทุนวันนี้ %.2f %s ถึงเพดาน %.1f%% แล้ว - หยุดเปิดไม้ใหม่ถึงพรุ่งนี้",
                          profitToday, AccountInfoString(ACCOUNT_CURRENCY), InpMaxDailyLossPct));
   }

   if(showPanel)
      UpdatePanel(tradesToday, profitToday);
}

// Single place every alert goes through (Telegram can be added here later).
void Notify(string msg)
{
   string full = "GoldScalper " + _Symbol + ": " + msg;
   Print(full);
   if(MQLInfoInteger(MQL_TESTER))
      return;
   if(InpNotifyPush && !SendNotification(full))
      Print("ส่ง Push ไม่สำเร็จ - ตั้ง MetaQuotes ID ใน Tools > Options > Notifications แล้วหรือยัง? (error ",
            GetLastError(), ")");
   if(InpNotifyPopup)
      Alert(full);
}

//+------------------------------------------------------------------+
//| On-chart panel                                                   |
//+------------------------------------------------------------------+
#define PANEL_W     290
#define LINE_H      18
#define PANEL_LINES 6

void CreatePanel()
{
   int h = 10 + LINE_H * PANEL_LINES + 40;
   string bg = PFX + "bg";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, PANEL_W);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'24,26,34');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'70,74,90');
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);

   for(int i = 0; i < PANEL_LINES; i++)
   {
      string name = PFX + "L" + (string)i;
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX + 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + 8 + i * LINE_H);
      ObjectSetString(0, name, OBJPROP_FONT, "Tahoma");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhiteSmoke);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   int by = InpPanelY + 10 + LINE_H * PANEL_LINES + 4;
   MakeButton(PFX + "btnPause", InpPanelX + 10,  by, 130, 26);
   MakeButton(PFX + "btnClose", InpPanelX + 150, by, 130, 26);
   ObjectSetString(0, PFX + "btnClose", OBJPROP_TEXT, "ปิดทุกไม้");
   ObjectSetInteger(0, PFX + "btnClose", OBJPROP_BGCOLOR, C'150,45,45');
}

void MakeButton(string name, int x, int y, int w, int h)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_FONT, "Tahoma");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'70,74,90');
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
}

void SetLine(int i, string text, color clr = clrWhiteSmoke)
{
   string name = PFX + "L" + (string)i;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void UpdatePanel(int tradesToday, double profitToday)
{
   string ccy = AccountInfoString(ACCOUNT_CURRENCY);

   // open position summary
   string posText = "ไม่มี";
   int    posCount = 0;
   double posPL = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || !IsMine())
         continue;
      posCount++;
      posPL += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      posText = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY " : "SELL ")
              + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + " lot";
   }
   if(posCount > 0)
      posText += StringFormat(" | P/L %.2f %s", posPL, ccy);

   string reason = BlockReason(tradesToday, profitToday);
   string status;
   color  statusClr;
   if(reason != "")      { status = reason;               statusClr = clrOrange; }
   else if(posCount > 0) { status = "กำลังถือออเดอร์";      statusClr = clrDeepSkyBlue; }
   else                  { status = "พร้อมเทรด - รอสัญญาณ"; statusClr = clrLimeGreen; }

   double atr[];
   string atrText = GetBuf(hATR, atr) ? DoubleToString(atr[0], 2) : "-";
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);

   string news;
   if(!InpNewsFilter)                    news = "ปิดตัวกรองข่าว";
   else if(MQLInfoInteger(MQL_TESTER))   news = "ใช้ไม่ได้ใน Tester";
   else if(newsNextInfo == "")           news = "ไม่มีใน 24 ชม.";
   else                                  news = newsNextInfo;
   if(StringLen(news) > 42)
      news = StringSubstr(news, 0, 40) + "..";

   SetLine(0, "GoldScalper M15  v1.31", clrGold);
   SetLine(1, "สถานะ: " + status, statusClr);
   SetLine(2, "ออเดอร์: " + posText, posPL < 0 ? clrTomato : clrWhiteSmoke);
   SetLine(3, StringFormat("วันนี้: %d/%d ไม้ | P/L %.2f %s", tradesToday, InpMaxTradesPerDay, profitToday, ccy),
           profitToday < 0 ? clrTomato : clrWhiteSmoke);
   SetLine(4, StringFormat("สเปรด: %.2f / %.2f | ATR: %s", spread, InpMaxSpread, atrText),
           spread > InpMaxSpread ? clrOrange : clrWhiteSmoke);
   SetLine(5, "ข่าวถัดไป: " + news, newsBlocked ? clrOrange : clrSilver);

   string bp = PFX + "btnPause";
   ObjectSetString(0, bp, OBJPROP_TEXT, paused ? "เทรดต่อ" : "หยุดชั่วคราว");
   ObjectSetInteger(0, bp, OBJPROP_BGCOLOR, paused ? C'40,130,70' : C'180,120,30');

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| News filter: true while inside a window around a matching event. |
//| Uses the built-in MQL5 economic calendar (server time).          |
//| Re-checked at most once a minute.                                |
//+------------------------------------------------------------------+
bool NewsBlackout()
{
   if(!InpNewsFilter)
      return false;

   // The calendar is not available in the Strategy Tester.
   if(MQLInfoInteger(MQL_TESTER))
   {
      static bool warned = false;
      if(!warned)
      {
         Print("ตัวกรองข่าวใช้ไม่ได้ใน Strategy Tester (MT5 ไม่ให้เข้าถึงปฏิทินข่าว) - ข้ามการกรองข่าว");
         warned = true;
      }
      return false;
   }

   datetime now = TimeTradeServer();
   if(now - newsLastCheck < 60)
      return newsBlocked;
   newsLastCheck = now;

   bool     wasBlocked = newsBlocked;
   datetime nextTime   = 0;
   newsBlocked   = false;
   newsBlockInfo = "";
   newsNextInfo  = "";

   ENUM_CALENDAR_EVENT_IMPORTANCE minImp = InpNewsHighOnly ? CALENDAR_IMPORTANCE_HIGH
                                                           : CALENDAR_IMPORTANCE_MODERATE;
   datetime from = now - InpNewsMinsAfter * 60;
   datetime to   = now + 24 * 3600;            // look a day ahead for the panel

   string cur[];
   int n = StringSplit(InpNewsCurrencies, ',', cur);
   for(int c = 0; c < n; c++)
   {
      StringTrimLeft(cur[c]);
      StringTrimRight(cur[c]);
      StringToUpper(cur[c]);
      if(cur[c] == "")
         continue;

      MqlCalendarValue vals[];
      if(!CalendarValueHistory(vals, from, to, NULL, cur[c]))
         continue;

      for(int i = 0; i < ArraySize(vals); i++)
      {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id, ev) || ev.importance < minImp)
            continue;

         datetime t = vals[i].time;
         string   label = TimeToString(t, TIME_MINUTES) + " " + cur[c] + " " + ev.name;

         if(now >= t - InpNewsMinsBefore * 60 && now <= t + InpNewsMinsAfter * 60)
         {
            newsBlocked   = true;
            newsBlockInfo = label;
         }
         if(t >= now && (nextTime == 0 || t < nextTime))
         {
            nextTime     = t;
            newsNextInfo = label;
         }
      }
   }

   if(newsBlocked && !wasBlocked)
   {
      Print("เข้าช่วงข่าว - งดเปิดไม้ใหม่: ", newsBlockInfo);
      if(InpNotifyNews)
         Notify("เข้าช่วงข่าว งดเปิดไม้ใหม่: " + newsBlockInfo);
   }
   if(!newsBlocked && wasBlocked)
   {
      Print("พ้นช่วงข่าว - กลับมาเทรดได้");
      if(InpNotifyNews)
         Notify("พ้นช่วงข่าวแล้ว กลับมาเทรดได้");
   }
   return newsBlocked;
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsMine()
{
   return PositionGetString(POSITION_SYMBOL) == _Symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic;
}

int CountPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && IsMine())
         n++;
   return n;
}

void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && IsMine())
         trade.PositionClose(ticket);
   }
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, InpTF, 0);
   if(t == 0 || t == lastBarTime)
      return false;
   lastBarTime = t;
   return true;
}

bool InSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpStartHour <= InpEndHour)
      return dt.hour >= InpStartHour && dt.hour < InpEndHour;
   return dt.hour >= InpStartHour || dt.hour < InpEndHour;   // window crosses midnight
}

bool IsFridayClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour;
}

// Daily ATR (last closed D1 bar) as % of price must reach InpMinDailyATRPct.
bool VolatilityOK()
{
   if(InpMinDailyATRPct <= 0)
      return true;
   double d1[];
   double price = iClose(_Symbol, InpTF, 1);
   return GetBuf(hATRD1, d1) && price > 0 && d1[0] / price * 100.0 >= InpMinDailyATRPct;
}

bool SpreadOK()
{
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return spread <= InpMaxSpread;
}

// Trades opened today and P/L today (closed deals + floating) for this EA.
void GetTodayStats(int &trades, double &profit)
{
   trades = 0;
   profit = 0;
   datetime dayStart = TimeCurrent() - (TimeCurrent() % 86400);

   if(HistorySelect(dayStart, TimeCurrent() + 60))
   {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;

         if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
            trades++;
         profit += HistoryDealGetDouble(deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(deal, DEAL_SWAP)
                 + HistoryDealGetDouble(deal, DEAL_COMMISSION);
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && IsMine())
         profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
}

bool DailyLossHit(double profitToday)
{
   if(InpMaxDailyLossPct <= 0 || profitToday >= 0)
      return false;
   double startBalance = AccountInfoDouble(ACCOUNT_BALANCE) - profitToday;
   return -profitToday >= startBalance * InpMaxDailyLossPct / 100.0;
}

// Copy the value of the last closed bar (shift 1) into buf[0].
bool GetBuf(int handle, double &buf[])
{
   ArraySetAsSeries(buf, true);
   return CopyBuffer(handle, 0, 1, 1, buf) == 1;
}

double MinStopDistance()
{
   long   level  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return level * _Point + spread;
}

double NormPrice(double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0) tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

// Money lost per 1.0 lot if price moves slDist against the position
// (XM GOLD: 1 point = 0.01 = $1 per lot, same as the lot-size sheet). 0 if unknown.
double LossPerLot(double slDist)
{
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0)
      return 0;
   return slDist / tickSize * tickVal;
}

// Lot size: fixed, or Balance × Risk% ÷ (loss per lot at the SL), rounded DOWN to the volume step.
double CalcLots(double slDist)
{
   if(InpLotMode == LOT_FIXED)
      return NormalizeLots(InpLots);
   double perLot = LossPerLot(slDist);
   if(perLot <= 0)
      return NormalizeLots(InpLots);
   return NormalizeLots(AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0 / perLot);
}

double NormalizeLots(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step + 1e-9) * step;           // epsilon: 0.1/0.01 must not floor to 9
   return MathMax(minL, MathMin(maxL, lots));
}
//+------------------------------------------------------------------+
