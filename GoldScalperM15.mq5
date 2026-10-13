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
#property version   "1.34"
#property description "XAUUSD M15 intraday - Asian-range breakout, volatility & news filters, panel"

#include <Trade\Trade.mqh>

enum ENUM_STRATEGY
{
   STRAT_PULLBACK = 0,  // EMA pullback (v1.x)
   STRAT_BREAKOUT = 1,  // Donchian breakout ตามเทรนด์
   STRAT_RSI2     = 2,  // RSI(2) ย่อตัวในเทรนด์
   STRAT_ORB      = 3   // Opening Range Breakout (กรอบราคาช่วงเช้า)
};

enum ENUM_LANG
{
   LANG_TH = 0,  // ไทย
   LANG_EN = 1   // English
};

enum ENUM_LOT_MODE
{
   LOT_FIXED = 0,  // Lot คงที่
   LOT_RISK  = 1   // คำนวณจาก % ความเสี่ยง (Balance × Risk% ÷ SL)
};

//--- inputs
input group "=== ทั่วไป ==="
input ENUM_LOT_MODE   InpLotMode         = LOT_RISK;  // วิธีกำหนด Lot (คำนวณจาก % = ปรับตามทุนอัตโนมัติ)
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

input group "=== ตรวจบัญชี / Account check ==="
input ENUM_LANG InpLanguage       = LANG_TH; // ภาษาหน้าต่างแนะนำ / Popup language
input bool   InpAccountCheck    = true;  // เด้งหน้าต่างวิเคราะห์บัญชีตอนเริ่ม / Show account check on start

input group "=== วิเคราะห์ไม้แพ้ ==="
input int    InpLossCooldownMin = 20;   // พักหลังไม้แพ้ (นาที, 0 = ปิด)
input bool   InpJournal         = true; // บันทึกทุกไม้ + สาเหตุที่แพ้ ลง CSV (Common\Files)
input int    InpMinConfidence   = 1;    // คะแนนความมั่นใจขั้นต่ำ 0-4 (เทรนด์ D1, เทรนด์ H1, ADX 20-30, RSI แรง; 0 = ปิด)

//--- globals
#define PFX "GS15_"

// Snapshot of the market at entry, plus excursion tracking, for the loss post-mortem.
struct TradeInfo
{
   datetime openTime;
   int      dir;                 // +1 buy, -1 sell
   double   entry, sl, atr, lots;
   double   rangeHigh, rangeLow; // ORB range (0 for other strategies)
   double   atrD1Pct, rangeAtr, breakAtr, bodyRatio, rsi, adx, spread;
   int      trendH1, trendD1;    // +1 = entry with the trend, -1 = against
   int      hour, dow;
   int      score;               // confidence score at entry (0-4)
   double   mfe, mae;            // max favourable / adverse excursion (price)
   bool     backInside;          // an M15 close came back inside the range
};

CTrade    trade;
int       hFast, hSlow, hTrend, hRSI, hRSI2, hATR, hATRD1, hEmaH1, hEmaD1, hAdxH1;
TradeInfo ti;
bool      tiValid       = false;
// Lot settings in effect (inputs, or the account-check recommendation chosen in the popup).
ENUM_LOT_MODE lotModeRt  = LOT_FIXED;
double    riskPctRt     = 1.0;
bool      rtInit        = false;
ENUM_LOT_MODE rtSeenMode = LOT_FIXED;
double    rtSeenRisk    = 0;
bool      accountCheckDone    = false;   // globals survive timeframe changes: popup once per attach
bool      accountCheckPending = false;
double    orbHigh       = 0, orbLow = 0;   // last ORB range seen by GetSignal()
datetime  cooldownUntil = 0;
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

   // Keep a popup-chosen lot setting across timeframe changes, but follow edited inputs.
   if(!rtInit || InpLotMode != rtSeenMode || InpRiskPct != rtSeenRisk)
   {
      lotModeRt  = InpLotMode;
      riskPctRt  = InpRiskPct;
      rtSeenMode = InpLotMode;
      rtSeenRisk = InpRiskPct;
      rtInit     = true;
   }
   if(InpAccountCheck && !MQLInfoInteger(MQL_TESTER) && !accountCheckDone)
      accountCheckPending = true;

   hFast  = iMA(_Symbol, InpTF, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, InpTF, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   ENUM_TIMEFRAMES trendTF = (InpTrendTF == PERIOD_CURRENT) ? InpTF : InpTrendTF;
   hTrend = iMA(_Symbol, trendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, InpTF, InpRSIPeriod, PRICE_CLOSE);
   hRSI2  = iRSI(_Symbol, InpTF, InpRSI2Period, PRICE_CLOSE);
   hATR   = iATR(_Symbol, InpTF, InpATRPeriod);
   hATRD1 = iATR(_Symbol, PERIOD_D1, 14);
   hEmaH1 = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);   // journal / diagnosis only
   hEmaD1 = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_EMA, PRICE_CLOSE);
   hAdxH1 = iADX(_Symbol, PERIOD_H1, 14);

   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hTrend == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hRSI2 == INVALID_HANDLE || hATR == INVALID_HANDLE ||
      hATRD1 == INVALID_HANDLE || hEmaH1 == INVALID_HANDLE || hEmaD1 == INVALID_HANDLE ||
      hAdxH1 == INVALID_HANDLE)
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

   // Each single tester run starts a fresh journal (live trading appends).
   if(InpJournal && MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
      FileDelete(JournalName(), FILE_COMMON);

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
   IndicatorRelease(hEmaH1);
   IndicatorRelease(hEmaD1);
   IndicatorRelease(hAdxH1);
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
   if(accountCheckPending)
   {
      accountCheckPending = false;
      accountCheckDone    = true;
      AccountCheck();
   }
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

   // Daily close. Also catches positions from a previous day: on early-close holidays
   // there may be no tick between the close hour and midnight.
   if(InpDailyCloseHour >= 0 && CountPositions() > 0)
   {
      MqlDateTime now;
      TimeToStruct(TimeCurrent(), now);
      datetime today = TimeCurrent() - (TimeCurrent() % 86400);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && IsMine() &&
            (now.hour >= InpDailyCloseHour || (datetime)PositionGetInteger(POSITION_TIME) < today))
            trade.PositionClose(ticket);
      }
   }

   bool newsNow = NewsBlackout();
   if(newsNow && InpNewsClosePos && CountPositions() > 0)
   {
      CloseAll();
      Notify("ปิดออเดอร์เพราะเข้าช่วงข่าว: " + newsBlockInfo);
   }

   TrackOpenTrade();

   if(!IsNewBar())
      return;

   // Post-mortem input: did price close back inside the ORB range after entry?
   if(tiValid && ti.rangeHigh > 0 && CountPositions() > 0)
   {
      double c1 = iClose(_Symbol, InpTF, 1);
      if((ti.dir > 0 && c1 < ti.rangeHigh) || (ti.dir < 0 && c1 > ti.rangeLow))
         ti.backInside = true;
   }

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
   if(signal != 0 && InpMinConfidence > 0)
   {
      int score = ConfidenceScore(signal);
      if(score < InpMinConfidence)
      {
         Print(StringFormat("ข้ามสัญญาณ %s: ความมั่นใจต่ำ %d/4 (ต้อง >= %d)", signal > 0 ? "BUY" : "SELL", score, InpMinConfidence));
         return;
      }
   }
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
         orbHigh = rHigh;
         orbLow  = rLow;
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
//| Position closed: loss post-mortem, journal, cooldown, alert       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
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
   string side  = HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_SELL ? "BUY" : "SELL";
   double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double pl    = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   long   why   = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string how   = why == DEAL_REASON_TP ? "ถึง TP" : why == DEAL_REASON_SL ? "โดน SL" : "ปิดไม้";
   string exitCode = why == DEAL_REASON_TP ? "TP" : why == DEAL_REASON_SL ? "SL" : "CLOSE";

   // Codes for the CSV, Thai text for the phone.
   string codes = "", thai = "";
   if(pl < 0)
   {
      LossReasons(exitCode, codes, thai);
      if(InpLossCooldownMin > 0)
         cooldownUntil = TimeCurrent() + InpLossCooldownMin * 60;
   }
   if(InpJournal && tiValid)
      WriteJournal(price, pl, exitCode, codes);
   tiValid = false;

   if(InpNotifyTrades)
      Notify(StringFormat("%s %s @ %s | P/L %.2f %s%s", how, side, DoubleToString(price, _Digits),
                          pl, AccountInfoString(ACCOUNT_CURRENCY),
                          pl < 0 ? " | แพ้เพราะ: " + thai : ""));
}

//+------------------------------------------------------------------+
//| Trade journal and loss diagnosis                                 |
//+------------------------------------------------------------------+
string JournalName()
{
   return StringFormat("GS15_journal_%s_%I64u%s.csv", _Symbol, InpMagic,
                       MQLInfoInteger(MQL_TESTER) ? "_tester" : "");
}

// Snapshot of the market on the signal bar, taken right after the order fills.
void CaptureEntry(int dir, double entryPrice, double sl, double atr, double lots)
{
   ZeroMemory(ti);
   ti.openTime = TimeCurrent();
   ti.dir      = dir;
   ti.entry    = entryPrice;
   ti.sl       = sl;
   ti.atr      = atr;
   ti.lots     = lots;
   ti.spread   = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);

   MqlDateTime dt;
   TimeToStruct(ti.openTime, dt);
   ti.hour = dt.hour;
   ti.dow  = dt.day_of_week;

   double o = iOpen(_Symbol, InpTF, 1), h = iHigh(_Symbol, InpTF, 1);
   double l = iLow(_Symbol, InpTF, 1),  c = iClose(_Symbol, InpTF, 1);
   ti.bodyRatio = h > l ? MathAbs(c - o) / (h - l) : 0;

   if(InpStrategy == STRAT_ORB && orbHigh > orbLow && atr > 0)
   {
      ti.rangeHigh = orbHigh;
      ti.rangeLow  = orbLow;
      ti.rangeAtr  = (orbHigh - orbLow) / atr;
      ti.breakAtr  = (dir > 0 ? c - orbHigh : orbLow - c) / atr;
   }

   double b[];
   if(GetBuf(hRSI, b))   ti.rsi = b[0];
   if(GetBuf(hAdxH1, b)) ti.adx = b[0];
   if(GetBuf(hEmaH1, b)) ti.trendH1 = ((c > b[0]) == (dir > 0)) ? 1 : -1;
   if(GetBuf(hEmaD1, b)) ti.trendD1 = ((c > b[0]) == (dir > 0)) ? 1 : -1;
   if(GetBuf(hATRD1, b) && c > 0) ti.atrD1Pct = b[0] / c * 100.0;

   ti.score = ConfidenceScore(dir);
   tiValid = true;
}

// Confidence score 0-4 for a signal, from the last closed bars. Each point is a condition that
// separated winners from losers in BOTH 2018-2023 and 2024-2026 (trade-journal analysis):
// with the D1 trend (EMA50), with the H1 trend (EMA200), ADX(14) H1 in 20-30, RSI(14) M15 >= 70 in trade direction.
int ConfidenceScore(int dir)
{
   double c = iClose(_Symbol, InpTF, 1);
   double b[];
   int score = 0;
   if(GetBuf(hEmaD1, b) && (c > b[0]) == (dir > 0)) score++;
   if(GetBuf(hEmaH1, b) && (c > b[0]) == (dir > 0)) score++;
   if(GetBuf(hAdxH1, b) && b[0] >= 20 && b[0] < 30) score++;
   if(GetBuf(hRSI, b) && (dir > 0 ? b[0] : 100.0 - b[0]) >= 70) score++;
   return score;
}

// Max favourable / adverse excursion of the open trade, every tick.
void TrackOpenTrade()
{
   if(!tiValid)
      return;
   double px = ti.dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double move = (px - ti.entry) * ti.dir;
   ti.mfe = MathMax(ti.mfe, move);
   ti.mae = MathMax(ti.mae, -move);
}

// Rule-based reasons a losing trade went wrong (several can apply).
void LossReasons(string exitCode, string &codes, string &thai)
{
   codes = "";
   thai  = "";
   if(!tiValid)
   {
      codes = "NO_SNAPSHOT";
      thai  = "ไม่มีข้อมูลตอนเข้า (EA ถูกรีสตาร์ทระหว่างถือไม้)";
      return;
   }
   if(ti.backInside)                        AddReason(codes, thai, "FALSE_BREAK", "เบรกหลอก ราคากลับเข้ากรอบ");
   if(ti.trendH1 < 0)                       AddReason(codes, thai, "AGAINST_H1",  "สวนเทรนด์ H1 (EMA200)");
   if(ti.trendD1 < 0)                       AddReason(codes, thai, "AGAINST_D1",  "สวนเทรนด์ D1 (EMA50)");
   if(ti.adx > 0 && ti.adx < 20)            AddReason(codes, thai, "LOW_ADX",     "ไม่มีเทรนด์ (ADX H1 < 20)");
   if(ti.bodyRatio < 0.5)                   AddReason(codes, thai, "WEAK_CANDLE", "แท่งเบรกอ่อน ไส้ยาว");
   if(ti.breakAtr > 1.0)                    AddReason(codes, thai, "CHASED",      "เข้าไล่ราคา ปิดไกลจากกรอบ");
   if((ti.dir > 0 && ti.rsi > 70) || (ti.dir < 0 && ti.rsi > 0 && ti.rsi < 30))
                                            AddReason(codes, thai, "RSI_EXTREME", "RSI สุดทางตอนเข้า");
   if(ti.atr > 0 && ti.mfe >= ti.atr)       AddReason(codes, thai, "GAVE_BACK",   "เคยกำไร >= 1 ATR แล้วกลับตัว");
   if(exitCode == "CLOSE")                  AddReason(codes, thai, "NO_FOLLOW",   "ราคาไม่ไปต่อจนหมดเวลา");
   if(ti.hour >= 15)                        AddReason(codes, thai, "LATE_ENTRY",  "เข้าช่วงบ่าย/ข่าว US");
   if(codes == "")
   {
      codes = "NORMAL";
      thai  = "ไม่พบจุดผิดปกติ (แพ้ตามสถิติ)";
   }
}

void AddReason(string &codes, string &thai, string code, string text)
{
   codes += (codes == "" ? "" : "|") + code;
   thai  += (thai == "" ? "" : ", ") + text;
}

void WriteJournal(double exitPrice, double pl, string exitCode, string codes)
{
   int f = FileOpen(JournalName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ, ',');
   if(f == INVALID_HANDLE)
   {
      Print("เขียน journal ไม่ได้: ", GetLastError());
      return;
   }
   if(FileSize(f) == 0)
      FileWrite(f, "open_time", "close_time", "dir", "lots", "entry", "exit", "pl", "result", "exit_reason",
                "hour", "dow", "atr_m15", "atr_d1_pct", "range_atr", "break_atr", "body_ratio", "rsi14",
                "adx_h1", "trend_h1", "trend_d1", "spread", "mfe_atr", "mae_atr", "back_inside", "confidence", "loss_reasons");
   FileSeek(f, 0, SEEK_END);
   double a = ti.atr > 0 ? ti.atr : 1;
   FileWrite(f, TimeToString(ti.openTime, TIME_DATE | TIME_MINUTES), TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
             ti.dir > 0 ? "BUY" : "SELL", DoubleToString(ti.lots, 2), DoubleToString(ti.entry, _Digits),
             DoubleToString(exitPrice, _Digits), DoubleToString(pl, 2), pl >= 0 ? "WIN" : "LOSS", exitCode,
             ti.hour, ti.dow, DoubleToString(ti.atr, 2), DoubleToString(ti.atrD1Pct, 2),
             DoubleToString(ti.rangeAtr, 2), DoubleToString(ti.breakAtr, 2), DoubleToString(ti.bodyRatio, 2),
             DoubleToString(ti.rsi, 1), DoubleToString(ti.adx, 1), ti.trendH1, ti.trendD1,
             DoubleToString(ti.spread, 2), DoubleToString(ti.mfe / a, 2), DoubleToString(ti.mae / a, 2),
             ti.backInside ? 1 : 0, ti.score, codes);
   FileClose(f);
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
   else if(sparam == PFX + "btnAcct")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      AccountCheck();
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
      CaptureEntry(isBuy ? 1 : -1, trade.ResultPrice() > 0 ? trade.ResultPrice() : price, sl, atr, lots);
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
   if(TimeCurrent() < cooldownUntil)      return "พักหลังแพ้ ถึง " + TimeToString(cooldownUntil, TIME_MINUTES);
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
   int h = 10 + LINE_H * PANEL_LINES + 72;
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
   MakeButton(PFX + "btnAcct", InpPanelX + 10, by + 32, 270, 24);
   ObjectSetString(0, PFX + "btnAcct", OBJPROP_TEXT, L("ตรวจบัญชี / คำแนะนำ", "Account check / advice"));
   ObjectSetInteger(0, PFX + "btnAcct", OBJPROP_BGCOLOR, C'50,80,140');
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
   if(posCount > 0 && tiValid)
      posText += StringFormat(" | มั่นใจ %d/4", ti.score);

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

   SetLine(0, "GoldScalper M15  v1.34", clrGold);
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
   if(lotModeRt == LOT_FIXED)
      return NormalizeLots(InpLots);
   double perLot = LossPerLot(slDist);
   if(perLot <= 0)
      return NormalizeLots(InpLots);
   return NormalizeLots(AccountInfoDouble(ACCOUNT_BALANCE) * riskPctRt / 100.0 / perLot);
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

//+------------------------------------------------------------------+
//| Account check popup (TH / EN)                                    |
//+------------------------------------------------------------------+
string L(string th, string en)
{
   return InpLanguage == LANG_EN ? en : th;
}

// Analyses balance vs. the money one stop-loss would cost right now, shows a verdict with
// a recommendation, and lets the user pick an option. Live/demo only (never in the tester).
void AccountCheck()
{
   if(MQLInfoInteger(MQL_TESTER))
      return;

   string title  = "GoldScalperM15 - " + L("วิเคราะห์บัญชี", "Account check");
   double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   double freeM  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   string ccy    = AccountInfoString(ACCOUNT_CURRENCY);
   long   lev    = AccountInfoInteger(ACCOUNT_LEVERAGE);
   bool   demo   = AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   double atr[];
   double slDist = 0, perLot = 0;
   if(GetBuf(hATR, atr) && atr[0] > 0)
   {
      slDist = MathMax(atr[0] * InpSL_ATR, MinStopDistance());
      perLot = LossPerLot(slDist);
   }
   if(bal <= 0 || perLot <= 0)
   {
      MessageBox(L("ยังวิเคราะห์ไม่ได้ ข้อมูลราคายังโหลดไม่ครบ\nลองกดปุ่ม \"ตรวจบัญชี\" บนแผงอีกครั้งภายหลัง",
                   "Cannot analyse yet - price data is still loading.\nPress \"Account check\" on the panel again later."),
                 title, MB_OK | MB_ICONINFORMATION);
      return;
   }

   double slMin      = perLot * minLot;                 // money lost at min lot if SL is hit
   double riskMinPct = slMin / bal * 100.0;
   double lots       = CalcLots(slDist);
   double riskNow    = perLot * lots;
   double riskNowPct = riskNow / bal * 100.0;
   double marginMin  = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, minLot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginMin))
      marginMin = 0;
   double maxRisk    = InpMaxRiskPct > 0 ? InpMaxRiskPct : 5.0;
   double needMin    = slMin / (maxRisk / 100.0);       // smallest balance the risk guard accepts
   double need1      = slMin / 0.01;                    // balance for 1% risk at min lot
   bool   canRisk1   = bal * 0.01 / perLot >= minLot;   // 1%-risk sizing gives at least the min lot
   // Account kind: Cent = balance in US cents; Micro = contract 100x smaller than standard gold (100 oz).
   string ccyUp = ccy;
   StringToUpper(ccyUp);
   bool   cent  = StringFind(ccyUp, "USC") == 0;
   bool   micro = !cent && contract > 0 && contract <= 10;
   string kind  = cent ? "Cent" : micro ? "Micro" : "Standard";
   string usd   = cent ? StringFormat(" (~%.2f USD)", bal / 100.0) : "";

   string mode       = lotModeRt == LOT_FIXED ? L("Lot คงที่", "fixed lot")
                                              : StringFormat(L("คำนวณจาก %.1f%%", "%.1f%% risk"), riskPctRt);

   string m = StringFormat(L("บัญชี: %s %s | บาลานซ์ %.2f %s%s | Leverage 1:%I64d\n",
                             "Account: %s %s | balance %.2f %s%s | leverage 1:%I64d\n"),
                           kind, demo ? "Demo" : L("เงินจริง", "Real"), bal, ccy, usd, lev);
   m += StringFormat(L("สัญลักษณ์: %s | ขนาดสัญญา %.2f | Lot ขั้นต่ำ %.2f\n\n", "Symbol: %s | contract %.2f | min lot %.2f\n\n"),
                     _Symbol, contract, minLot);
   m += StringFormat(L("SL ตอนนี้ประมาณ %.2f (%.0f จุด) ตาม ATR - เปลี่ยนทุกวัน\n", "Current SL is about %.2f (%.0f points) from ATR - changes daily\n"),
                     slDist, slDist / _Point);
   m += StringFormat(L("โดน SL ที่ Lot ขั้นต่ำ: เสีย %.2f %s = %.1f%% ของพอร์ต\n", "Loss at min lot if SL is hit: %.2f %s = %.1f%% of balance\n"),
                     slMin, ccy, riskMinPct);
   m += StringFormat(L("ตั้งค่าปัจจุบัน (%s): %.2f lot -> เสี่ยง %.2f %s = %.1f%% ต่อไม้\n", "Current setting (%s): %.2f lot -> risk %.2f %s = %.1f%% per trade\n"),
                     mode, lots, riskNow, ccy, riskNowPct);
   m += StringFormat(L("มาร์จิ้นที่ต้องใช้ต่อ Lot ขั้นต่ำ: %.2f %s (ว่าง %.2f)\n\n", "Margin for min lot: %.2f %s (free %.2f)\n\n"),
                     marginMin, ccy, freeM);

   int    buttons;
   string optYes = "", optNo = "", optCancel = "";
   int    level;   // 0 cannot trade, 1 high risk, 2 OK
   bool   offerSwitch = false;   // popup offers switching to 1% risk lots
   if(marginMin > freeM || (InpMaxRiskPct > 0 && riskNowPct > InpMaxRiskPct)) level = 0;
   else if(riskNowPct > 2.0)                           level = 1;
   else                                                level = 2;

   if(level == 0)
   {
      m += L("ผล: ทุนไม่พอสำหรับบัญชีนี้ - EA จะข้ามทุกไม้\n", "Verdict: balance too small for this account - the EA will skip every trade\n");
      if(micro || cent)
         m += StringFormat(L("แนะนำ: ทุนขั้นต่ำที่ระบบกันความเสี่ยงยอมรับ ~%.0f %s (แนะนำ ~%.0f %s ที่เสี่ยง 1%%)\n\n",
                             "Recommendation: minimum balance the risk guard accepts ~%.0f %s (recommended ~%.0f %s at 1%% risk)\n\n"),
                           needMin, ccy, need1, ccy);
      else
         m += StringFormat(L("แนะนำ:\n - ทุนขั้นต่ำที่ระบบกันความเสี่ยงยอมรับ ~%.0f %s (แนะนำ ~%.0f %s ที่เสี่ยง 1%%)\n - หรือใช้บัญชี Micro/Cent (lot เล็กกว่า 100 เท่า: ทุน ~%.0f %s ก็พอ)\n\n",
                             "Recommendation:\n - Minimum balance the risk guard accepts: ~%.0f %s (recommended ~%.0f %s at 1%% risk)\n - Or use a Micro/Cent account (100x smaller lots: ~%.0f %s is enough)\n\n"),
                           needMin, ccy, need1, ccy, MathCeil(needMin / 100.0), ccy);
      buttons = MB_YESNOCANCEL | MB_ICONWARNING;
      optYes = L("ให้ EA ทำงานต่อ (รอและข้ามไม้ที่เสี่ยงเกิน)", "keep the EA running (it waits and skips risky trades)");
      optNo  = L("หยุดเปิดไม้ใหม่ชั่วคราว", "pause new trades");
      optCancel = L("เอา EA ออกจากกราฟ", "remove the EA from the chart");
   }
   else if(level == 1)
   {
      m += StringFormat(L("ผล: เสี่ยงสูง %.1f%% ต่อไม้ (แนะนำไม่เกิน 2%%)\n", "Verdict: high risk, %.1f%% per trade (recommended max 2%%)\n"), riskNowPct);
      if(canRisk1 && lotModeRt == LOT_FIXED)
      {
         m += L("แนะนำ: เปลี่ยนเป็นคำนวณ Lot จากความเสี่ยง 1% ต่อไม้\n\n", "Recommendation: switch to 1% risk-based lot sizing\n\n");
         offerSwitch = true;
         buttons = MB_YESNOCANCEL | MB_ICONWARNING;
         optYes = L("ใช้คำแนะนำ (Lot จาก 1%)", "apply the recommendation (1% risk lots)");
         optNo  = L("ใช้ค่าเดิม", "keep my settings");
         optCancel = L("หยุดเปิดไม้ใหม่ชั่วคราว", "pause new trades");
      }
      else
      {
         m += StringFormat(L("แนะนำ: ลด Lot ไม่ได้แล้ว (ใช้ Lot ขั้นต่ำอยู่) - เพิ่มทุนเป็น ~%.0f %s หรือใช้บัญชี Micro/Cent\n\n",
                             "Recommendation: lot cannot go lower (already min lot) - increase balance to ~%.0f %s or use a Micro/Cent account\n\n"),
                           need1, ccy);
         buttons = MB_YESNO | MB_ICONWARNING;
         optYes = L("ให้ EA ทำงานต่อ", "keep the EA running");
         optNo  = L("หยุดเปิดไม้ใหม่ชั่วคราว", "pause new trades");
      }
   }
   else
   {
      m += StringFormat(L("ผล: ความเสี่ยงเหมาะสม %.1f%% ต่อไม้\n", "Verdict: risk is reasonable, %.1f%% per trade\n"), riskNowPct);
      if(lotModeRt == LOT_FIXED && canRisk1 && NormalizeLots(bal * 0.01 / perLot) > lots)
      {
         m += StringFormat(L("ทางเลือก: คำนวณ Lot จากความเสี่ยง 1%% จะได้ %.2f lot (โตตามพอร์ต)\n\n",
                             "Option: 1%% risk-based sizing would trade %.2f lot (grows with the account)\n\n"),
                           NormalizeLots(bal * 0.01 / perLot));
         buttons = MB_YESNO | MB_ICONINFORMATION;
         offerSwitch = true;
         optYes = L("ใช้ Lot จาก 1%", "use 1% risk lots");
         optNo  = L("ใช้ค่าเดิม", "keep my settings");
      }
      else
         buttons = MB_OK | MB_ICONINFORMATION;
   }

   if(optYes != "")
   {
      m += L("เลือก:\n", "Choose:\n");
      m += "[" + L("ใช่", "Yes") + "] " + optYes + "\n";
      m += "[" + L("ไม่", "No") + "] " + optNo + "\n";
      if(optCancel != "")
         m += "[" + L("ยกเลิก", "Cancel") + "] " + optCancel + "\n";
   }

   int answer = MessageBox(m, title, buttons);
   string logLine = m;
   StringReplace(logLine, "\n", " | ");
   Print(title, ": ", logLine, " -> answer ", answer);

   if(offerSwitch && answer == IDYES)
   {
      lotModeRt = LOT_RISK;
      riskPctRt = MathMin(1.0, maxRisk);
      Print(L("เปลี่ยนเป็นคำนวณ Lot จากความเสี่ยง 1% (เฉพาะรอบนี้ - ถ้าจะใช้ถาวรให้ตั้ง InpLotMode ใน Inputs)",
              "Switched to 1% risk-based lots (this session - set InpLotMode in Inputs to make it permanent)"));
   }
   bool pause = (level == 0 && answer == IDNO) ||
                (level == 1 && ((offerSwitch && answer == IDCANCEL) || (!offerSwitch && answer == IDNO)));
   if(pause)
   {
      paused = true;
      GlobalVariableSet(gvPaused, 1);
   }
   if(level == 0 && answer == IDCANCEL)
      ExpertRemove();
}