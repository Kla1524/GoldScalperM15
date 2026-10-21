//+------------------------------------------------------------------+
//|                                              GoldScalperM15.mq5  |
//|  XAUUSD M15 intraday EA - one strategy (v1.50): Asian-range       |
//|  breakout on volatile days, one trade a day, wide ATR stop, flat  |
//|  by 20:00 server time (no swap). Risk-% sizing, news / spread /   |
//|  daily-loss filters, risk-guard halts, panel, console, push.      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 Kla1524 - MIT License"
#property link      "https://github.com/Kla1524/GoldScalperM15"
#property version   "1.55"
#define   VERSION_TEXT "1.55"
#define   REVERSE_COMMENT "GoldScalper REVERSE"
#property description "XAUUSD M15 intraday - Asian-range breakout, volatility & news filters, panel"
#property description "For education and research only - not investment advice."

#include <Trade\Trade.mqh>

enum ENUM_LANG
{
   LANG_TH = 0,  // Thai / ไทย
   LANG_EN = 1   // English
};

enum ENUM_LOT_MODE
{
   LOT_FIXED = 0,  // Fixed lot
   LOT_RISK  = 1   // Risk % of equity (Equity x Risk% / SL)
};

//--- inputs
input group "=== General ==="
input ENUM_LOT_MODE   InpLotMode         = LOT_RISK;  // Lot sizing (risk % follows the account size)
input double          InpLots            = 0.01;      // Fixed lot (when lot sizing = fixed)
input double          InpRiskPct         = 0.5;       // Risk % of equity per trade (when lot sizing = risk %)
input ulong           InpMagic           = 20261013;  // Magic number
input ENUM_TIMEFRAMES InpTF              = PERIOD_M15;// Signal timeframe
input bool            InpAllowBuy        = true;      // Allow buys
input bool            InpAllowSell       = true;      // Allow sells

input group "=== Entry signal ==="
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_CURRENT; // Trend EMA timeframe (CURRENT = signal timeframe)
input int    InpTrendEMA    = 200;   // Trend EMA period
input bool   InpUseTrend    = false; // Also require the close beyond the trend EMA
input int    InpRangeStartHour = 0;  // Range start (hour, server time)
input int    InpRangeEndHour   = 8;  // Range end / breakouts from (hour, server time)
input bool   InpStopEntry      = false; // Enter with BUY STOP / SELL STOP orders at the range edges (the other side is cancelled on a fill) instead of waiting for an M15 close beyond the range
input int    InpStopEntryBufPts = 0;   // Stop-entry: extra distance beyond the range edge (points)
input bool   InpRetestEntry     = false; // Breakout + retest: after an M15 close beyond the range, wait for price to come back to the range edge (limit order) instead of entering at once
input int    InpRetestBufPts    = 0;     // Retest: limit order this many points beyond the edge (toward the breakout side)
input int    InpRetestMaxBars   = 8;     // Retest: cancel the limit order if not filled within this many M15 bars
input int    InpRSIPeriod   = 14;    // RSI period (confidence score, journal)

input group "=== SL / TP (multiples of ATR) ==="
input int    InpATRPeriod   = 14;    // ATR period
input double InpSL_ATR      = 4.0;   // SL = ATR x
input double InpTP_ATR      = 0.0;   // TP = ATR x (0 = no take-profit)
input double InpBE_ATR      = 0.0;   // Move SL to breakeven at profit >= ATR x (0 = off)
input double InpTrail_ATR   = 0.0;   // Trailing distance ATR x (0 = off)
input double InpTrailStart_ATR = -1; // Start trailing at profit >= ATR x (-1 = same as the trailing distance)

input group "=== Filters & risk ==="
input int    InpStartHour       = 0;    // Trading starts (hour, server time)
input int    InpEndHour         = 18;   // No new trades from (hour, server time)
input double InpMaxSpread       = 1.00; // Max spread (price units, e.g. 0.40 = 40 cents)
input double InpMinATR          = 0.0;  // Min ATR (price units, 0 = off)
input double InpMinDailyATRPct  = 1.6;  // Min daily ATR as % of price (0 = off): trade only volatile days
input bool   InpStrictRisk      = true; // Skip a trade if its real risk (vs equity) exceeds the risk % (risk-% sizing)
input int    InpSlippagePts     = 30;   // Slippage allowance at the SL (points), counted in the real risk
input double InpCommissionLot   = 0.0;  // Round-turn commission per 1 lot (account currency; XM Standard = 0)
input double InpMaxRiskPct      = 5.0;  // Hard cap: skip if the SL would lose more than % of equity (0 = off)
input int    InpMaxTradesPerDay = 1;    // Trades per day (the first breakout of the day; 0 = unlimited, not recommended)
input bool   InpStopDayAfterLoss = false; // No new trades for the rest of the day after a losing trade
input bool   InpSkipMonday      = false; // No new trades on Mondays
input bool   InpFilterJudas     = false; // Smart-money filter (AMD / Judas swing): a breakout counts only if price first took the OTHER side of the range after it formed
input bool   InpFilterFVG       = false; // Smart-money filter: the breakout bars must leave a fair value gap (bar 3 high < bar 1 low for buys)
input bool   InpFilterH1Bias    = false; // Smart-money filter: H1 bias must agree (close > EMA50 > EMA200 for buys, the reverse for sells)
input bool   InpPyramid         = false; // Add ONE more trade in the same direction when the first is InpPyramidATR x ATR in profit (same risk rules)
input double InpPyramidATR      = 2.0;   // Pyramid: profit (in M15 ATR) needed before the add
input bool   InpReverseOnOpposite = false; // Stop and reverse: a losing trade is closed and the opposite trade opened when price breaks out of the other side of the range (same lot rules, once per position)
input double InpMaxDailyLossPct = 3.0;  // Daily loss limit, % of start-of-day balance (0 = off)
input double InpMaxDDPct        = 20.0; // Halt: pause when equity falls this % below its peak (0 = off)
input int    InpMaxLossStreak   = 5;    // Halt: pause after this many losing trades in a row (0 = off)
input int    InpMaxLosingDays   = 0;    // Halt: pause after this many losing days in a row (0 = off; test before use)
input double InpMaxLot          = 0.0;  // Max lot per trade (0 = off)
input double InpMaxExposure     = 10.0; // Max position value as a multiple of equity, caps the lot (0 = off)
input int    InpDailyCloseHour  = 20;   // Close all trades daily at this hour (avoids swap, -1 = off)
input bool   InpCloseFriday     = true; // Close trades before the Friday market close
input int    InpFridayCloseHour = 21;   // Friday close hour (server time)
input bool   InpSessionGuard    = true; // Close before gold stops trading: weeks when US and EU summer time differ (trading ends ~23:00 server) and US holidays (early close)
input int    InpCloseBufferMin  = 10;   // Session guard: close this many minutes before the market stops
input int    InpHolidayCloseHour = 18;  // Session guard: on US holidays / early-close days, close and take no new trades from this hour (server time)

input group "=== News filter (MT5 economic calendar) ==="
input bool   InpNewsFilter       = true;   // Enable the news filter
input string InpNewsCurrencies   = "USD";  // Currencies to watch (comma separated, e.g. USD,EUR)
input bool   InpNewsHighOnly     = true;   // true = high impact only, false = medium + high
input int    InpNewsMinsBefore   = 15;     // No new trades before the event (minutes)
input int    InpNewsMinsAfter    = 15;     // No new trades after the event (minutes)
input string InpNewsOnlyEvents   = "";     // Only these events ("" = all of the chosen impact), comma separated parts of the name, e.g. Nonfarm Payrolls,CPI,FOMC,Fed Interest Rate Decision
input bool   InpNewsClosePos     = false;  // Close open trades when a news window starts
input bool   InpNewsInTester     = true;   // Strategy Tester: apply the filter from the exported news file
input string InpNewsFile         = "";     // News history file in Common\Files ("" = GS15_news_<currencies>.csv)
input bool   InpNewsServerUSDST  = true;   // Tester: server time = GMT+2, GMT+3 during US daylight saving (XM and most brokers)

input group "=== Notifications ==="
input bool   InpNotifyPush   = true;   // Push notifications to the MT5 mobile app
input bool   InpNotifyPopup  = false;  // Alert window on the PC
input bool   InpNotifyTrades = true;   // Notify trade open / close / breakeven
input bool   InpNotifyNews   = true;   // Notify news windows
input bool   InpDailySummary = true;   // Daily summary after the daily close: trades, P/L, balance, guards
input bool   InpNotifyStartStop = true; // Notify when the EA starts (and how long it was not running) and when it stops

input group "=== On-chart panel ==="
input bool   InpShowPanel = true;  // Show the panel
input int    InpPanelX    = 10;    // Panel X position (pixels)
input int    InpPanelY    = 30;    // Panel Y position (pixels)

input group "=== Language & account check ==="
input ENUM_LANG InpLanguage       = LANG_EN; // Language of panel, alerts and windows / ภาษา
input bool   InpAccountCheck    = true;  // Account check on start
input bool   InpAccountPopup    = false; // Start-up check as a popup (needs an answer); false = Experts tab

input group "=== PowerShell console ==="
input bool   InpConsole         = true;  // Write status/events for tools\GS15_Console.ps1 and accept its commands
input bool   InpConsoleButton   = true;  // "Console" button on the chart: opens / closes the console (needs the launcher)

input group "=== System test (demo accounts only) ==="
input bool   InpTestMode        = false; // System test: open/close real demo trades now, without a signal
input int    InpTestTrades      = 3;     // Number of test trades (alternating BUY / SELL)
input int    InpTestHoldMin     = 2;     // Minutes to hold each test trade
input int    InpQuickTestHoldMs = 100;   // Test button: milliseconds to hold the test trade before closing it
input bool   InpQuickTestReal   = false; // Allow the Test button on a REAL account (costs the spread)

input group "=== Loss diagnosis ==="
input int    InpLossCooldownMin = 20;   // Pause after a losing trade (minutes, 0 = off)
input bool   InpJournal         = true; // Log every trade + loss reasons to CSV (Common\Files)
input int    InpTesterHaltDays  = 0;     // Tester only: after a risk-guard halt, 0 = count and carry on, N = stay paused N days then resume (simulated review), -1 = stay paused to the end
input double InpTesterSpreadMult = 1.0;  // Tester only: spread stress - the spread filter sees spread x this, and (x - 1) x spread is charged per entry
input int    InpMinConfidence   = 1;    // Min confidence score 0-4 (D1 trend, H1 trend, ADX 20-30, strong RSI; 0 = off)

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
int       hTrend, hRSI, hATR, hATRD1, hEmaH1, hEmaD1, hAdxH1, hEma50H1;
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
double    orbHigh       = 0, orbLow = 0;   // last ORB range seen by GetSignal() / TodayRange()
double    seAtr         = 0;               // stop-entry: M15 ATR when the orders were placed
datetime  cooldownUntil = 0;
datetime lastBarTime     = 0;
datetime newsLastCheck   = 0;
datetime newsFileT[];                    // tester: event times (server time) from the exported file
bool     newsFileLoaded  = false;
bool     newsExportPending = false;
bool     newsBlocked     = false;
string   newsBlockInfo   = "";
string   newsNextInfo    = "";
bool     paused          = false;
string   gvPaused        = "";
string   gvPeak          = "";          // equity peak, for the drawdown halt
string   gvStreak        = "";          // losing trades in a row
string   gvHalt          = "";          // why the EA paused itself: 0 none, 1 drawdown, 2 losing streak
double   equityPeak      = 0;
int      lossStreak      = 0;
int      haltCode        = 0;
int      testerHalts[4]  = {0, 0, 0, 0}; // tester: how often each halt would have fired
string   gvLosingDays    = "";          // losing days in a row
string   gvDayEval       = "";          // last server day counted for the losing-days guard
string   gvSummaryDay    = "";          // last day the daily summary went out
int      losingDays      = 0;
long     dayEvaluated    = 0;           // server day number (time / 86400) last counted
long     lastLossDay     = 0;           // server day number of the last losing trade (InpStopDayAfterLoss)
string   gvLossDay       = "";
double   rtAtr           = 0;           // retest entry: M15 ATR at the signal
bool     pyramidNext     = false;       // the next market entry is a pyramid add (a position is already open)
bool     reverseNext     = false;       // the next market entry is a stop-and-reverse (comment marks it)
datetime testerResumeAt  = 0;           // tester (InpTesterHaltDays > 0): simulated Resume time
double   testerHaltDays  = 0;           // tester: days spent halted
double   testerExtraCost = 0;           // tester (InpTesterSpreadMult > 1): extra spread charged
string   gvCooldown      = "";          // end of the loss cooldown, kept across restarts
int      testDone        = 0;           // system-test trades opened so far
CTrade   qtTrade;                       // Test button: own magic, so it never counts as a trade of the day
ulong    qtTicket        = 0;
ulong    qtOpenedMs      = 0;
ulong    qtSendMs        = 0;
string   qtSource        = "";
double   qtOpenPx        = 0;
bool     testFinished    = false;
int      lossNotifiedDay = -1;
bool     showPanel       = false;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpLotMode == LOT_RISK && (InpRiskPct <= 0 || (InpMaxRiskPct > 0 && InpRiskPct > InpMaxRiskPct)))
   {
      Print("InpRiskPct must be > 0 and <= InpMaxRiskPct (", InpMaxRiskPct, "%) - otherwise every trade is skipped");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Two copies of this EA on the same symbol would trade twice (seen in the clip): refuse to start.
   if(!MQLInfoInteger(MQL_TESTER) && AnotherCopyRunning())
   {
      string msg = StringFormat(L("ไม่เริ่มทำงาน: มี GoldScalper บน %s อยู่แล้วในกราฟอื่น - เอาออกให้เหลือตัวเดียว", "Not started: GoldScalper already runs on another %s chart - keep only one"), _Symbol);
      Notify(msg, "WARN");
      Alert("GoldScalper " + _Symbol + ": " + msg);
      return INIT_FAILED;
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

   ENUM_TIMEFRAMES trendTF = (InpTrendTF == PERIOD_CURRENT) ? InpTF : InpTrendTF;
   hTrend = iMA(_Symbol, trendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, InpTF, InpRSIPeriod, PRICE_CLOSE);
   hATR   = iATR(_Symbol, InpTF, InpATRPeriod);
   hATRD1 = iATR(_Symbol, PERIOD_D1, 14);
   hEmaH1 = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);   // journal / diagnosis only
   hEmaD1 = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_EMA, PRICE_CLOSE);
   hAdxH1 = iADX(_Symbol, PERIOD_H1, 14);
   hEma50H1 = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(hTrend == INVALID_HANDLE || hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE ||
      hATRD1 == INVALID_HANDLE || hEmaH1 == INVALID_HANDLE || hEmaD1 == INVALID_HANDLE ||
      hAdxH1 == INVALID_HANDLE)
   {
      Print("Indicator creation failed: ", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);
   qtTrade.SetExpertMagicNumber(QuickTestMagic());
   qtTrade.SetDeviationInPoints(50);
   qtTrade.SetTypeFillingBySymbol(_Symbol);

   // Pause state survives timeframe changes and terminal restarts.
   gvPaused = PFX + "paused_" + _Symbol + "_" + (string)InpMagic;
   paused   = GlobalVariableCheck(gvPaused) && GlobalVariableGet(gvPaused) > 0;

   // Risk-guard state survives restarts as well.
   gvPeak   = PFX + "peak_" + _Symbol + "_" + (string)InpMagic;
   gvStreak = PFX + "streak_" + _Symbol + "_" + (string)InpMagic;
   gvHalt   = PFX + "halt_" + _Symbol + "_" + (string)InpMagic;
   gvLosingDays = PFX + "losingdays_" + _Symbol + "_" + (string)InpMagic;
   gvDayEval    = PFX + "dayeval_" + _Symbol + "_" + (string)InpMagic;
   gvSummaryDay = PFX + "summary_" + _Symbol + "_" + (string)InpMagic;
   gvLossDay    = PFX + "lossday_" + _Symbol + "_" + (string)InpMagic;
   if(!MQLInfoInteger(MQL_TESTER) && GlobalVariableCheck(gvLossDay))
      lastLossDay = (long)GlobalVariableGet(gvLossDay);
   if(!MQLInfoInteger(MQL_TESTER))
   {
      equityPeak = GlobalVariableCheck(gvPeak) ? GlobalVariableGet(gvPeak) : 0;
      lossStreak = GlobalVariableCheck(gvStreak) ? (int)GlobalVariableGet(gvStreak) : 0;
      haltCode   = paused && GlobalVariableCheck(gvHalt) ? (int)GlobalVariableGet(gvHalt) : 0;
      losingDays = GlobalVariableCheck(gvLosingDays) ? (int)GlobalVariableGet(gvLosingDays) : 0;
      dayEvaluated = GlobalVariableCheck(gvDayEval) ? (long)GlobalVariableGet(gvDayEval) : 0;
   }
   UpdatePeak();

   // Loss cooldown survives restarts too.
   gvCooldown = PFX + "cooldown_" + _Symbol + "_" + (string)InpMagic;
   if(!MQLInfoInteger(MQL_TESTER) && GlobalVariableCheck(gvCooldown))
      cooldownUntil = (datetime)(long)GlobalVariableGet(gvCooldown);

   // Positions left from a time the EA was not running (PC off, disconnect): say so; the
   // daily-close rule closes them on the next tick.
   if(!MQLInfoInteger(MQL_TESTER) && UninitializeReason() != REASON_CHARTCHANGE &&
      UninitializeReason() != REASON_PARAMETERS)
   {
      datetime today = TimeCurrent() - (TimeCurrent() % 86400);
      MqlDateTime nowDt;
      TimeToStruct(TimeCurrent(), nowDt);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) == 0 || !IsMine())
            continue;
         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         if(opened < today || (InpDailyCloseHour >= 0 && nowDt.hour >= InpDailyCloseHour))
            Notify(StringFormat(L("พบไม้ค้าง #%I64u (เปิด %s) จากช่วงที่ EA ไม่ได้ทำงาน - กำลังปิดตามกฎปิดประจำวัน", "Found position #%I64u (opened %s) left from while the EA was not running - closing it by the daily-close rule"),
                                PositionGetInteger(POSITION_TICKET), TimeToString(opened, TIME_DATE | TIME_MINUTES)));
         else
            Notify(StringFormat(L("EA กลับมาทำงาน: ดูแลไม้ #%I64u ที่เปิดอยู่ต่อ (SL ยังอยู่ที่เซิร์ฟเวอร์)", "EA running again: managing open position #%I64u (its SL stayed on the server)"),
                                PositionGetInteger(POSITION_TICKET)));
      }
   }

   showPanel = InpShowPanel && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));
   if(InpConsole && InpConsoleButton && !MQLInfoInteger(MQL_TESTER))
      CreateConsoleButton();
   if(showPanel)
      CreatePanel();

   // Each single tester run starts a fresh journal (live trading appends).
   if(InpJournal && MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
      FileDelete(JournalName(), FILE_COMMON);
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
      FileDelete(StringFormat("GS15_stress_%s_%I64u_tester.csv", _Symbol, InpMagic), FILE_COMMON);

   if(InpNotifyStartStop && !MQLInfoInteger(MQL_TESTER) && UninitializeReason() != REASON_CHARTCHANGE &&
      UninitializeReason() != REASON_PARAMETERS && UninitializeReason() != REASON_RECOMPILE)
      NotifyStarted();

   newsExportPending = true;   // refresh the news history file shortly after start (live only)
   EventSetTimer(1);
   ConsoleLog("INFO", StringFormat("GoldScalperM15 v%s started on %s %s | account %s | %s", VERSION_TEXT, _Symbol,
                                   EnumToString(InpTF), MaskedLogin(), StyleLine()));
   RefreshStatus();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(InpNotifyStartStop && !MQLInfoInteger(MQL_TESTER) &&
      (reason == REASON_CLOSE || reason == REASON_REMOVE || reason == REASON_ACCOUNT || reason == REASON_PROGRAM))
      Notify((reason == REASON_CLOSE ? L("EA หยุด: MT5 กำลังปิด", "EA stopped: MT5 is closing")
            : reason == REASON_ACCOUNT ? L("EA หยุด: เปลี่ยนบัญชี", "EA stopped: account changed")
            : L("EA หยุด: ถูกเอาออกจากกราฟ", "EA stopped: removed from the chart")) +
             (CountPositions() > 0 ? L(" | ไม้ที่เปิดอยู่ยังมี SL ที่เซิร์ฟเวอร์", " | the open trade keeps its SL on the server") : ""), "WARN");
   if(MQLInfoInteger(MQL_TESTER) && (InpMaxDDPct > 0 || InpMaxLossStreak > 0 || InpMaxLosingDays > 0))
   {
      if(InpTesterHaltDays == 0)
         PrintFormat("Risk guards in this test: drawdown halt %d time(s), losing-streak halt %d time(s), losing-days halt %d time(s) "
                     "(live trading pauses until you resume; the tester carries on)", testerHalts[1], testerHalts[2], testerHalts[3]);
      else
         PrintFormat("Risk guards in this test: drawdown halt %d time(s), losing-streak halt %d time(s), losing-days halt %d time(s), paused like live "
                     "(resume after %d days; -1 = never), %s at the end", testerHalts[1], testerHalts[2], testerHalts[3], InpTesterHaltDays,
                     paused ? "still paused" : "trading");
   }
   if(MQLInfoInteger(MQL_TESTER) && InpTesterSpreadMult != 1.0)
      PrintFormat("Risk guards in this test: spread stress x%.2f, extra spread charged %.2f %s", InpTesterSpreadMult,
                  testerExtraCost, AccountInfoString(ACCOUNT_CURRENCY));
   ObjectsDeleteAll(0, PFX);
   IndicatorRelease(hTrend);
   IndicatorRelease(hRSI);
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
   UpdateConsoleButton();
   if(accountCheckPending)
   {
      accountCheckPending = false;
      accountCheckDone    = true;
      AccountCheck(InpAccountPopup);
   }
   ReadConsoleCommand();
   NewsExportIfStale();
   TestStep();
   QuickTestStep();
   UpdatePeak();
   CheckLosingDays();
   DailySummaryStep();
   RefreshStatus();
}

//+------------------------------------------------------------------+
//| System test (demo only): opens InpTestTrades real trades one at a |
//| time through the normal OpenTrade path (lot sizing, SL, journal,  |
//| notifications, loss diagnosis, cooldown), holds each for          |
//| InpTestHoldMin minutes, then closes it. Ignores signal and hours. |
//+------------------------------------------------------------------+
bool TestActive()
{
   return InpTestMode && !testFinished && !MQLInfoInteger(MQL_TESTER);
}

void TestStep()
{
   if(!TestActive())
      return;
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
   {
      testFinished = true;
      Notify(L("ไม่ทดสอบ: โหมดทดสอบระบบใช้ได้เฉพาะบัญชี Demo (บัญชีนี้เป็นบัญชีจริง)", "System test refused: demo accounts only (this is a real account)"));
      return;
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsMine())
         continue;
      if(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME) >= InpTestHoldMin * 60)
      {
         Print(StringFormat(L("ทดสอบ: ครบ %d นาที - ปิดไม้ #%I64u", "Test: %d minutes up - closing #%I64u"), InpTestHoldMin, ticket));
         ClosePosition(ticket, L("ทดสอบ", "test"));
      }
      return;
   }

   if(testDone >= InpTestTrades)
   {
      testFinished = true;
      Notify(StringFormat(L("ทดสอบระบบเสร็จ %d ไม้ - ปิด InpTestMode แล้ว EA จะกลับไปเทรดตามสัญญาณ", "System test finished (%d trades) - set InpTestMode = false to trade signals again"), testDone));
      return;
   }
   if(paused || TimeCurrent() < cooldownUntil)
      return;   // the loss cooldown is part of what is being tested

   double atr[];
   if(!GetBuf(hATR, atr) || atr[0] <= 0)
      return;
   testDone++;
   ENUM_ORDER_TYPE type = (testDone % 2 == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   Notify(StringFormat(L("ทดสอบระบบ ไม้ที่ %d/%d: เปิด %s (ถือ %d นาที)", "System test %d/%d: opening %s (hold %d min)"), testDone, InpTestTrades,
                       type == ORDER_TYPE_BUY ? "BUY" : "SELL", InpTestHoldMin));
   OpenTrade(type, atr[0]);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(testerResumeAt > 0 && TimeCurrent() >= testerResumeAt)
   {
      // Tester, InpTesterHaltDays > 0: the simulated person reviews and presses Resume.
      testerHaltDays += InpTesterHaltDays;
      testerResumeAt = 0;
      Print("Risk guard: simulated Resume");
      SetPaused(false);
   }
   ManagePositions();
   UpdatePeak();
   CheckLosingDays();

   if(InpCloseFriday && IsFridayClose())
   {
      if(CountPositions() > 0)
      {
         datetime fri = TimeCurrent() - (TimeCurrent() % 86400) + InpFridayCloseHour * 3600;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !IsMine())
               continue;
            PrintFormat("CLOSEAUDIT #%I64u kind=Friday close deadline=%s sent=%s", ticket,
                        TimeToString(fri, TIME_DATE | TIME_MINUTES), TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
            if(ClosePosition(ticket, L("ก่อนตลาดปิดวันศุกร์", "Friday close")))
               PrintFormat("CLOSEDONE #%I64u at %s", ticket, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
         }
         Notify(L("ปิดออเดอร์ทั้งหมดก่อนตลาดปิดวันศุกร์", "Closed all trades before the Friday market close"));
      }
      DeleteStopOrders(L("ก่อนตลาดปิดวันศุกร์", "before the Friday close"));
      return;
   }

   // Daily close. Also catches positions from a previous day: on early-close holidays
   // there may be no tick between the close hour and midnight.
   if((InpDailyCloseHour >= 0 || InpSessionGuard) && CountPositions() > 0)
   {
      datetime today = TimeCurrent() - (TimeCurrent() % 86400);
      datetime deadline = CloseDeadline();
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !IsMine())
            continue;
         bool late = (datetime)PositionGetInteger(POSITION_TIME) < today;
         if(!late && TimeCurrent() < deadline)
            continue;
         string kind = late ? "LATE (from an earlier day)" : CloseKind();
         PrintFormat("CLOSEAUDIT #%I64u kind=%s deadline=%s sent=%s", ticket, kind,
                     TimeToString(late ? today : deadline, TIME_DATE | TIME_MINUTES), TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
         if(ClosePosition(ticket, L("ปิดประจำวัน", "daily close")))
            PrintFormat("CLOSEDONE #%I64u at %s", ticket, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
      }
   }

   bool newsNow = NewsBlackout();
   if(newsNow && InpNewsClosePos && CountPositions() > 0)
   {
      CloseAll();
      Notify(L("ปิดออเดอร์เพราะเข้าช่วงข่าว: ", "Closed trades for a news window: ") + newsBlockInfo, "NEWS");
   }

   TrackOpenTrade();
   if(InpStopEntry)
      StopEntryOnTick();
   if(InpRetestEntry)
      RetestOnTick();

   if(!IsNewBar())
      return;

   // Post-mortem input: did price close back inside the ORB range after entry?
   if(tiValid && ti.rangeHigh > 0 && CountPositions() > 0)
   {
      double c1 = iClose(_Symbol, InpTF, 1);
      if((ti.dir > 0 && c1 < ti.rangeHigh) || (ti.dir < 0 && c1 > ti.rangeLow))
         ti.backInside = true;
   }

   if(InpStopEntry)
      return;   // entries come from the stop orders (StopEntryOnTick)

   if(CountPositions() > 0)
   {
      if(InpReverseOnOpposite)
         TryReverse();
      if(InpPyramid)
         TryPyramid();
      return;
   }

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
         string skipMsg = StringFormat(L("ข้ามสัญญาณ %s: ความมั่นใจต่ำ %d/4 (ต้อง >= %d)", "Skipped %s signal: low confidence %d/4 (needs >= %d)"), signal > 0 ? "BUY" : "SELL", score, InpMinConfidence);
         Print(skipMsg);
         ConsoleLog("SKIP", skipMsg);
         return;
      }
   }
   if(signal != 0 && !SmcFiltersOK(signal))
      return;
   if(InpRetestEntry && signal != 0 && ((signal > 0 && InpAllowBuy) || (signal < 0 && InpAllowSell)))
   {
      PlaceRetest(signal, a);
      return;
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

   // Today's range between InpRangeStartHour and InpRangeEndHour (server time);
   // signal on the first close beyond it after the range has formed.
   double c = iClose(_Symbol, InpTF, 1);
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
   static datetime rangeLogged = 0;   // console: report each day's range once
   if(rangeLogged != day0)
   {
      rangeLogged = day0;
      double atrD1[];
      double c0 = iClose(_Symbol, PERIOD_D1, 1);
      string vol = (GetBuf(hATRD1, atrD1) && c0 > 0) ? StringFormat(" | ATR D1 %.2f%%", atrD1[0] / c0 * 100.0) : "";
      ConsoleLog("INFO", StringFormat(L("กรอบวันนี้: %s - %s%s", "Today's range: %s - %s%s"),
                                      DoubleToString(rLow, _Digits), DoubleToString(rHigh, _Digits), vol));
   }
   double prev = iClose(_Symbol, InpTF, 2);
   if(c > rHigh && prev <= rHigh && TrendOK(1, c, trend[0]))  return 1;
   if(c < rLow  && prev >= rLow  && TrendOK(-1, c, trend[0])) return -1;
   return 0;
}

// Optional trend filter (InpUseTrend).
bool TrendOK(int dir, double close, double trendEma)
{
   if(!InpUseTrend)
      return true;
   return dir > 0 ? close > trendEma : close < trendEma;
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
   // Deposit / withdrawal: shift the equity peak by the same amount, otherwise a withdrawal
   // would look like a drawdown and halt the EA (and a deposit would hide a real one).
   if(HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BALANCE)
   {
      double amount = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      if(equityPeak > 0)
      {
         equityPeak = MathMax(0.0, equityPeak + amount);
         if(!MQLInfoInteger(MQL_TESTER))
            GlobalVariableSet(gvPeak, equityPeak);
      }
      ConsoleLog("INFO", StringFormat(L("ฝาก/ถอน %.2f - ปรับจุดสูงสุดของ Equity เป็น %.2f", "Deposit/withdrawal %.2f - equity peak adjusted to %.2f"), amount, equityPeak));
      return;
   }
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic ||
      HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
   {
      StopEntryFilled(trans.deal);
      return;
   }
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   // The closing deal goes the opposite way of the position.
   string side  = HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_SELL ? "BUY" : "SELL";
   double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double pl    = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   long   why   = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string how   = why == DEAL_REASON_TP ? L("ถึง TP", "TP hit") : why == DEAL_REASON_SL ? L("โดน SL", "SL hit") : L("ปิดไม้", "Closed");
   string exitCode = why == DEAL_REASON_TP ? "TP" : why == DEAL_REASON_SL ? "SL" : "CLOSE";

   // Codes for the CSV, Thai text for the phone.
   string codes = "", thai = "";
   if(pl < 0)
   {
      lastLossDay = (long)(TimeCurrent() / 86400);
      if(!MQLInfoInteger(MQL_TESTER))
         GlobalVariableSet(gvLossDay, (double)lastLossDay);
      LossReasons(exitCode, codes, thai);
      if(InpLossCooldownMin > 0)
      {
         cooldownUntil = TimeCurrent() + InpLossCooldownMin * 60;
         if(!MQLInfoInteger(MQL_TESTER))
            GlobalVariableSet(gvCooldown, (double)cooldownUntil);   // survives an MT5 restart
      }
   }
   if(InpJournal && tiValid)
      WriteJournal(price, pl, exitCode, codes);
   tiValid = false;

   if(pl < 0)       lossStreak++;
   else if(pl > 0)  lossStreak = 0;
   if(!MQLInfoInteger(MQL_TESTER))
      GlobalVariableSet(gvStreak, lossStreak);

   string closeMsg = StringFormat("%s %s @ %s | P/L %.2f %s%s", how, side, DoubleToString(price, _Digits),
                                  pl, AccountInfoString(ACCOUNT_CURRENCY),
                                  pl < 0 ? L(" | แพ้เพราะ: ", " | Lost because: ") + thai : "");
   if(InpNotifyTrades)
      Notify(closeMsg, pl < 0 ? "LOSS" : "WIN");
   else
      ConsoleLog(pl < 0 ? "LOSS" : "WIN", closeMsg);

   if(InpMaxLossStreak > 0 && lossStreak >= InpMaxLossStreak)
      Halt(2, StringFormat(L("แพ้ติดกัน %d ไม้ (เพดาน %d)", "%d losing trades in a row (limit %d)"), lossStreak, InpMaxLossStreak));
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

   if(orbHigh > orbLow && atr > 0)
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
      thai  = L("ไม่มีข้อมูลตอนเข้า (EA ถูกรีสตาร์ทระหว่างถือไม้)", "no entry data (the EA restarted while the trade was open)");
      return;
   }
   if(ti.backInside)                        AddReason(codes, thai, "FALSE_BREAK", L("เบรกหลอก ราคากลับเข้ากรอบ", "false breakout, price came back into the range"));
   if(ti.trendH1 < 0)                       AddReason(codes, thai, "AGAINST_H1",  L("สวนเทรนด์ H1 (EMA200)", "against the H1 trend (EMA200)"));
   if(ti.trendD1 < 0)                       AddReason(codes, thai, "AGAINST_D1",  L("สวนเทรนด์ D1 (EMA50)", "against the D1 trend (EMA50)"));
   if(ti.adx > 0 && ti.adx < 20)            AddReason(codes, thai, "LOW_ADX",     L("ไม่มีเทรนด์ (ADX H1 < 20)", "no trend (ADX H1 < 20)"));
   if(ti.bodyRatio < 0.5)                   AddReason(codes, thai, "WEAK_CANDLE", L("แท่งเบรกอ่อน ไส้ยาว", "weak breakout candle, long wick"));
   if(ti.breakAtr > 1.0)                    AddReason(codes, thai, "CHASED",      L("เข้าไล่ราคา ปิดไกลจากกรอบ", "chased: closed far beyond the range"));
   if((ti.dir > 0 && ti.rsi > 70) || (ti.dir < 0 && ti.rsi > 0 && ti.rsi < 30))
                                            AddReason(codes, thai, "RSI_EXTREME", L("RSI สุดทางตอนเข้า", "RSI extreme at entry"));
   if(ti.atr > 0 && ti.mfe >= ti.atr)       AddReason(codes, thai, "GAVE_BACK",   L("เคยกำไร >= 1 ATR แล้วกลับตัว", "was >= 1 ATR in profit, then reversed"));
   if(exitCode == "CLOSE")                  AddReason(codes, thai, "NO_FOLLOW",   L("ราคาไม่ไปต่อจนหมดเวลา", "no follow-through before the close"));
   if(ti.hour >= 15)                        AddReason(codes, thai, "LATE_ENTRY",  L("เข้าช่วงบ่าย/ข่าว US", "late entry (US session / news)"));
   if(codes == "")
   {
      codes = "NORMAL";
      thai  = L("ไม่พบจุดผิดปกติ (แพ้ตามสถิติ)", "nothing unusual (a normal statistical loss)");
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
      Print("Cannot write the journal: ", GetLastError());
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

   if(sparam == PFX + "btnConsole")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ConsoleButtonClick();
      return;
   }
   if(sparam == PFX + "btnPause")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      SetPaused(!paused);
      Print(paused ? L("หยุดเปิดไม้ใหม่ชั่วคราว (ออเดอร์ที่ถืออยู่ยังดูแล SL/TP ต่อ)", "Paused: no new trades (open trades keep their SL/TP)") : L("กลับมาเทรดตามปกติ", "Trading resumed"));
   }
   else if(sparam == PFX + "btnClose")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      int n = CountPositions();
      if(n == 0)
         Print(L("ไม่มีออเดอร์ของ EA นี้ให้ปิด", "No trades of this EA to close"));
      else if(MQLInfoInteger(MQL_TESTER) ||
              MessageBox(StringFormat(L("ปิดออเดอร์ของ EA นี้ทั้งหมด %d ไม้?", "Close all %d trades of this EA?"), n),
                         "GoldScalperM15", MB_YESNO | MB_ICONQUESTION) == IDYES)
      {
         CloseAll();
         Notify(StringFormat(L("ปิดออเดอร์ทั้งหมด %d ไม้ (กดปุ่มบนแผง)", "Closed all %d trades (panel button)"), n));
      }
   }
   else if(sparam == PFX + "btnTest")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      if(QuickTestAllowed(true) &&
         MessageBox(StringFormat(L("ทดสอบระบบ: เปิด BUY %.2f lot จริง แล้วปิดภายใน %d มิลลิวินาที\nเสียแค่ค่าสเปรด และไม่นับเป็นไม้ของวัน\n\nเริ่มทดสอบ?",
                                   "System test: open a real BUY of %.2f lot and close it after %d ms.\nCosts only the spread and does not count as a trade of the day.\n\nStart the test?"),
                                 SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), InpQuickTestHoldMs),
                    "GoldScalperM15", MB_YESNO | MB_ICONQUESTION) == IDYES)
         QuickTestStart(L("ปุ่มบนแผง", "panel button"));
   }
   else if(sparam == PFX + "btnAcct")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      AccountCheck(true);
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

   // Lot cap: guards against a bad ATR / tiny stop producing an oversized position.
   double cap = MaxLotCap(price);
   if(cap > 0 && lots > cap)
   {
      double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(cap < minL)
      {
         Notify(StringFormat(L("ข้าม %s: เพดาน lot %.3f ต่ำกว่า lot ขั้นต่ำ %.2f", "Skipped %s: lot cap %.3f is below the minimum lot %.2f"), side, cap, minL), "SKIP");
         return;
      }
      Notify(StringFormat(L("ลด lot %s จาก %.2f เหลือ %.2f ตามเพดาน lot (SL ใกล้ผิดปกติ? ATR %.2f)", "%s lot reduced from %.2f to %.2f by the lot cap (unusually close SL? ATR %.2f)"),
                          side, lots, NormalizeLots(cap), atr), "WARN");
      lots = NormalizeLots(cap);
   }

   // Real risk of this order: SL from the actual entry price + slippage allowance + commission,
   // measured against equity.
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = RiskPerLot(slDist) * lots;          // money lost if SL is hit (0 = unknown)
   string ccy       = AccountInfoString(ACCOUNT_CURRENCY);
   // Risk-% sizing needs the tick value. Right after a (re)connect it can still be 0: then the lot
   // would silently fall back to InpLots and every risk check below would pass. Skip instead.
   if(lotModeRt == LOT_RISK && riskMoney <= 0)
   {
      NotifyFailure(StringFormat(L("ข้าม %s: ยังคำนวณความเสี่ยงไม่ได้ (tick value = 0) - รอราคา/การเชื่อมต่อ", "Skipped %s: risk cannot be computed yet (tick value is 0) - waiting for prices / connection"), side));
      return;
   }
   if(InpMaxRiskPct > 0 && riskMoney > equity * InpMaxRiskPct / 100.0)
   {
      NotifyFailure(StringFormat(L("ข้าม %s: SL เสี่ยง %.2f (%.1f%% ของ Equity) เกินกำหนด %.1f%%", "Skipped %s: SL risk %.2f (%.1f%% of equity) is above the %.1f%% cap"), side,
                                 riskMoney, riskMoney / equity * 100.0, InpMaxRiskPct));
      return;
   }
   // Strict risk: never exceed the current mode's risk % - if even the minimum lot is too
   // big, skip the trade instead of forcing it, and say why.
   if(lotModeRt == LOT_RISK && InpStrictRisk && equity > 0 &&
      riskMoney > equity * RiskPctEff() / 100.0 * 1.0001)
   {
      Notify(StringFormat(L("ข้าม %s: Lot ขั้นต่ำ %.2f ถ้าโดน SL จะเสีย %.2f %s (%.2f%% ของ Equity %.2f) เกินเป้า %.1f%% "
                            "[SL %.2f + slippage %d จุด + คอมฯ] - ต้องมี Equity ~%.0f %s หรือใช้บัญชี Micro/Cent",
                            "Skipped %s: min lot %.2f would lose %.2f %s at the SL (%.2f%% of equity %.2f), above the target of %.1f%% "
                            "[SL %.2f + slippage %d pts + commission] - needs equity of ~%.0f %s or a Micro/Cent account"),
                          side, lots, riskMoney, ccy, riskMoney / equity * 100.0, equity, RiskPctEff(),
                          slDist, InpSlippagePts, riskMoney / (RiskPctEff() / 100.0), ccy), "SKIP");
      return;
   }
   // Daily loss budget: this trade's stop must fit in what is left of today's limit.
   if(InpMaxDailyLossPct > 0)
   {
      int    tToday;
      double pToday;
      GetTodayStats(tToday, pToday);
      double budget = (balance - pToday) * InpMaxDailyLossPct / 100.0 - MathMax(0.0, -pToday);
      if(riskMoney > budget)
      {
         Notify(StringFormat(L("ข้าม %s: งบขาดทุนวันนี้เหลือ %.2f %s แต่ไม้นี้ถ้าโดน SL จะเสีย %.2f (เพดาน %.1f%%/วัน)", "Skipped %s: %.2f %s left in today's loss budget, but this trade would lose %.2f at the SL (limit %.1f%%/day)"),
                             side, MathMax(0.0, budget), AccountInfoString(ACCOUNT_CURRENCY), riskMoney, InpMaxDailyLossPct), "SKIP");
         return;
      }
   }
   // One order at a time across charts: a second chart with the same magic, or a repeated
   // signal after a reconnect, must not open a duplicate.
   if(!AcquireOrderLock() || (CountPositions() > 0 && !pyramidNext))
   {
      Print("Duplicate order skipped: an order was just sent or a position of this EA is open");
      ConsoleLog("SKIP", "Duplicate order skipped: an order was just sent or a position of this EA is open");
      return;
   }
   // Skip (and warn at most once a day) when free margin can't cover the order.
   double margin;
   if(OrderCalcMargin(type, _Symbol, lots, price, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      NotifyFailure(StringFormat(L("มาร์จิ้นไม่พอเปิด %s %.2f lot (ต้องใช้ %.2f, มี %.2f)", "Not enough margin for %s %.2f lot (needs %.2f, free %.2f)"), side, lots,
                                 margin, AccountInfoDouble(ACCOUNT_MARGIN_FREE)));
      return;
   }

   bool ok = isBuy ? trade.Buy(lots, _Symbol, ask, sl, tp, (reverseNext ? REVERSE_COMMENT : "GoldScalper BUY"))
                   : trade.Sell(lots, _Symbol, bid, sl, tp, (reverseNext ? REVERSE_COMMENT : "GoldScalper SELL"));
   // Requote / price changed: retry once at the new price with the same stop distance and lot,
   // so the risk stays the same. The breakout signal is only evaluated once per bar.
   uint rc0 = trade.ResultRetcode();
   if(!ok && (rc0 == TRADE_RETCODE_REQUOTE || rc0 == TRADE_RETCODE_PRICE_CHANGED || rc0 == TRADE_RETCODE_PRICE_OFF))
   {
      Print(StringFormat("Order %s: %d %s - retrying once at the new price", side, rc0, trade.ResultRetcodeDescription()));
      ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      price = isBuy ? ask : bid;
      sl    = NormPrice(isBuy ? ask - slDist : bid + slDist);
      tp    = InpTP_ATR > 0 ? NormPrice(isBuy ? ask + tpDist : bid - tpDist) : 0;
      if(SpreadOK())
         ok = isBuy ? trade.Buy(lots, _Symbol, ask, sl, tp, (reverseNext ? REVERSE_COMMENT : "GoldScalper BUY"))
                    : trade.Sell(lots, _Symbol, bid, sl, tp, (reverseNext ? REVERSE_COMMENT : "GoldScalper SELL"));
   }
   if(ok)
   {
      CaptureEntry(isBuy ? 1 : -1, trade.ResultPrice() > 0 ? trade.ResultPrice() : price, sl, atr, lots);
      TesterSpreadCharge(lots);
      string openMsg = StringFormat(L("เปิด %s %.2f lot @ %s | SL %s | TP %s | เสี่ยง %.2f %s (%.2f%% ของ Equity)", "Opened %s %.2f lot @ %s | SL %s | TP %s | risk %.2f %s (%.2f%% of equity)"), side, lots,
                                    DoubleToString(trade.ResultPrice() > 0 ? trade.ResultPrice() : price, _Digits),
                                    DoubleToString(sl, _Digits), DoubleToString(tp, _Digits),
                                    riskMoney, AccountInfoString(ACCOUNT_CURRENCY),
                                    equity > 0 ? riskMoney / equity * 100.0 : 0);
      if(InpNotifyTrades)
         Notify(openMsg, "OPEN");
      else
         ConsoleLog("OPEN", openMsg);
   }
   else
      NotifyFailure(StringFormat(L("เปิด %s ไม่สำเร็จ: %d %s", "Open %s failed: %d %s"), side, trade.ResultRetcode(),
                                 trade.ResultRetcodeDescription()));
}

//+------------------------------------------------------------------+
//| Stop-entry (InpStopEntry): a BUY STOP above and a SELL STOP below |
//| today's range, placed once the range has formed. Whichever fills  |
//| first is the trade of the day; the other order is cancelled. The  |
//| orders and their SL wait on the broker's server.                  |
//+------------------------------------------------------------------+
#define STOP_COMMENT_BUY  "GoldScalper BUY STOP"
#define STOP_COMMENT_SELL "GoldScalper SELL STOP"

// Today's range (InpRangeStartHour - InpRangeEndHour, server time); false before it has formed.
bool TodayRange(double &hi, double &lo)
{
   datetime now = TimeCurrent();
   datetime day0 = now - (now % 86400);
   datetime rs = day0 + InpRangeStartHour * 3600;
   datetime re = day0 + InpRangeEndHour * 3600 - 1;
   if(now <= re)
      return false;
   double hs[], ls[];
   if(CopyHigh(_Symbol, InpTF, rs, re, hs) < 2 || CopyLow(_Symbol, InpTF, rs, re, ls) < 2)
      return false;
   hi = hs[ArrayMaximum(hs)];
   lo = ls[ArrayMinimum(ls)];
   orbHigh = hi;
   orbLow  = lo;
   return true;
}

// This EA's pending order of one type (0 = none).
ulong StopOrderTicket(ENUM_ORDER_TYPE type)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t > 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagic &&
         (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == type)
         return t;
   }
   return 0;
}

void DeleteStopOrders(string why)
{
   for(int k = 0; k < 2; k++)
   {
      ulong t = StopOrderTicket(k == 0 ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP);
      if(t > 0 && trade.OrderDelete(t))
         ConsoleLog("INFO", StringFormat(L("ยกเลิกคำสั่งรอ %s (%s)", "Cancelled the %s order (%s)"), k == 0 ? "BUY STOP" : "SELL STOP", why));
   }
}

// Lot for a stop order, with the same checks as a market entry; 0 = skip (reason sent once a day).
double StopEntryLots(string side, double price, double slDist)
{
   double lots = CalcLots(slDist);
   double cap  = MaxLotCap(price);
   if(cap > 0 && lots > cap)
   {
      if(cap < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         return 0;
      lots = NormalizeLots(cap);
   }
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = RiskPerLot(slDist) * lots;
   if(lotModeRt == LOT_RISK && riskMoney <= 0)
      return 0;
   if(InpMaxRiskPct > 0 && riskMoney > equity * InpMaxRiskPct / 100.0)
      return 0;
   if(lotModeRt == LOT_RISK && InpStrictRisk && equity > 0 && riskMoney > equity * RiskPctEff() / 100.0 * 1.0001)
   {
      NotifyFailure(StringFormat(L("ไม่วาง %s: lot ขั้นต่ำ %.2f เสี่ยง %.2f%% เกินเป้า %.1f%%", "Not placing %s: min lot %.2f would risk %.2f%%, above the %.1f%% target"),
                                 side, lots, riskMoney / equity * 100.0, RiskPctEff()));
      return 0;
   }
   if(InpMaxDailyLossPct > 0)
   {
      int t; double p;
      GetTodayStats(t, p);
      if(riskMoney > (balance - p) * InpMaxDailyLossPct / 100.0 - MathMax(0.0, -p))
         return 0;
   }
   return lots;
}

void StopEntryOnTick()
{
   // OCO: once a position of this EA exists, the other order goes.
   if(CountPositions() > 0)
   {
      DeleteStopOrders(L("อีกฝั่งเปิดไม้แล้ว", "the other side filled"));
      return;
   }
   int    tradesToday;
   double profitToday;
   GetTodayStats(tradesToday, profitToday);
   string block = BlockReason(tradesToday, profitToday, true);
   if(block != "")
   {
      DeleteStopOrders(block);
      return;
   }
   double hi, lo;
   if(!TodayRange(hi, lo))
      return;
   if(!SpreadOK())
      return;                 // a wide spread only delays new orders; placed ones stay
   double atr[];
   if(!GetBuf(hATR, atr) || atr[0] <= 0 || (InpMinATR > 0 && atr[0] < InpMinATR))
      return;
   double slDist  = MathMax(atr[0] * InpSL_ATR, MinStopDistance());
   double tpDist  = MathMax(atr[0] * InpTP_ATR, MinStopDistance());
   double buf     = InpStopEntryBufPts * _Point;
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist = MinStopDistance();
   datetime now   = TimeCurrent();
   datetime expiry = now - (now % 86400) + InpEndHour * 3600;

   for(int k = 0; k < 2; k++)
   {
      int dir = k == 0 ? 1 : -1;
      if((dir > 0 && !InpAllowBuy) || (dir < 0 && !InpAllowSell))
         continue;
      ENUM_ORDER_TYPE type = dir > 0 ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
      ulong have = StopOrderTicket(type);
      // Confidence is re-checked as bars close: an order whose side no longer qualifies is withdrawn.
      bool confident = InpMinConfidence <= 0 || ConfidenceScore(dir) >= InpMinConfidence;
      if(have > 0)
      {
         if(!confident && trade.OrderDelete(have))
            ConsoleLog("SKIP", StringFormat(L("ยกเลิก %s: ความมั่นใจต่ำ", "Cancelled %s: low confidence"), dir > 0 ? "BUY STOP" : "SELL STOP"));
         continue;
      }
      if(!confident)
         continue;
      double price = NormPrice(dir > 0 ? hi + buf : lo - buf);
      // Price already beyond the edge (e.g. the EA started late): no chasing.
      if(dir > 0 ? price <= ask + minDist : price >= bid - minDist)
         continue;
      string side = dir > 0 ? "BUY STOP" : "SELL STOP";
      double lots = StopEntryLots(side, price, slDist);
      if(lots <= 0 || !AcquireOrderLock())
         continue;
      double sl = NormPrice(dir > 0 ? price - slDist : price + slDist);
      double tp = InpTP_ATR > 0 ? NormPrice(dir > 0 ? price + tpDist : price - tpDist) : 0;
      ENUM_ORDER_TYPE_TIME tt = expiry > now + 60 ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
      bool ok = dir > 0 ? trade.BuyStop(lots, price, _Symbol, sl, tp, tt, expiry, STOP_COMMENT_BUY)
                        : trade.SellStop(lots, price, _Symbol, sl, tp, tt, expiry, STOP_COMMENT_SELL);
      if(ok)
      {
         seAtr = atr[0];
         ConsoleLog("INFO", StringFormat(L("วาง %s %.2f lot @ %s | SL %s | ถึง %s", "Placed %s %.2f lot @ %s | SL %s | until %s"), side, lots,
                                         DoubleToString(price, _Digits), DoubleToString(sl, _Digits), TimeToString(expiry, TIME_MINUTES)));
      }
      else
         NotifyFailure(StringFormat(L("วาง %s ไม่สำเร็จ: %d %s", "Placing %s failed: %d %s"), side, trade.ResultRetcode(), trade.ResultRetcodeDescription()));
   }
}

//+------------------------------------------------------------------+
//| Breakout + retest (InpRetestEntry, v1.54): the M15 close beyond   |
//| the range arms a limit order at the range edge (BUY LIMIT above,  |
//| SELL LIMIT below), valid InpRetestMaxBars bars and never past the |
//| close deadline. Same lot, SL, TP and risk checks as other entries.|
//+------------------------------------------------------------------+
#define RETEST_COMMENT "GoldScalper RETEST"

int DayOfWeekNow()
{
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   return d.day_of_week;
}

void DeleteRetestOrders(string why)
{
   for(int k = 0; k < 2; k++)
   {
      ulong t = StopOrderTicket(k == 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT);
      if(t > 0 && trade.OrderDelete(t))
         ConsoleLog("INFO", StringFormat(L("ยกเลิกคำสั่งรอ retest %s (%s)", "Cancelled the retest %s (%s)"), k == 0 ? "BUY LIMIT" : "SELL LIMIT", why));
   }
}

void PlaceRetest(int dir, double atr)
{
   DeleteRetestOrders(L("สัญญาณใหม่", "new signal"));
   double edge = dir > 0 ? orbHigh : orbLow;
   if(edge <= 0)
      return;
   double slDist  = MathMax(atr * InpSL_ATR, MinStopDistance());
   double tpDist  = MathMax(atr * InpTP_ATR, MinStopDistance());
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = NormPrice(dir > 0 ? edge + InpRetestBufPts * _Point : edge - InpRetestBufPts * _Point);
   // Price already back at the edge: enter now (the retest is happening).
   if(dir > 0 ? price >= ask - MinStopDistance() : price <= bid + MinStopDistance())
   {
      OpenTrade(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, atr);
      return;
   }
   string side = dir > 0 ? "BUY LIMIT" : "SELL LIMIT";
   double lots = StopEntryLots(side, price, slDist);
   if(lots <= 0 || !AcquireOrderLock())
      return;
   datetime now = TimeCurrent();
   datetime expiry = MathMin(now + InpRetestMaxBars * PeriodSeconds(InpTF), CloseDeadline());
   if(expiry <= now + 60)
      return;
   double sl = NormPrice(dir > 0 ? price - slDist : price + slDist);
   double tp = InpTP_ATR > 0 ? NormPrice(dir > 0 ? price + tpDist : price - tpDist) : 0;
   bool ok = dir > 0 ? trade.BuyLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, RETEST_COMMENT)
                     : trade.SellLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, RETEST_COMMENT);
   if(ok)
   {
      rtAtr = atr;
      ConsoleLog("INFO", StringFormat(L("วาง %s %.2f lot @ %s (รอราคากลับมาทดสอบกรอบ) | SL %s | ถึง %s", "Placed %s %.2f lot @ %s (waiting for the retest) | SL %s | until %s"),
                                      side, lots, DoubleToString(price, _Digits), DoubleToString(sl, _Digits), TimeToString(expiry, TIME_MINUTES)));
   }
   else
      NotifyFailure(StringFormat(L("วาง %s ไม่สำเร็จ: %d %s", "Placing %s failed: %d %s"), side, trade.ResultRetcode(), trade.ResultRetcodeDescription()));
}

void RetestOnTick()
{
   if(CountPositions() > 0)
   {
      DeleteRetestOrders(L("มีไม้เปิดแล้ว", "a position is open"));
      return;
   }
   if(StopOrderTicket(ORDER_TYPE_BUY_LIMIT) == 0 && StopOrderTicket(ORDER_TYPE_SELL_LIMIT) == 0)
      return;
   int    tradesToday;
   double profitToday;
   GetTodayStats(tradesToday, profitToday);
   string block = BlockReason(tradesToday, profitToday, true);
   if(block != "")
      DeleteRetestOrders(block);
}

//+------------------------------------------------------------------+
//| Stop and reverse (InpReverseOnOpposite, v1.54): while this EA's   |
//| trade is losing, a breakout through the OTHER side of the range   |
//| (M15 close, same crossing rule and filters as a new entry) closes |
//| it and opens the opposite trade. A reversed trade is not reversed |
//| again.                                                            |
//+------------------------------------------------------------------+

void TryReverse()
{
   int    pdir = 0;
   double ppl = 0;
   ulong  ticket = 0;
   bool   reversedAlready = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsMine())
         continue;
      ticket = t;
      pdir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      ppl  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      reversedAlready = StringFind(PositionGetString(POSITION_COMMENT), REVERSE_COMMENT) >= 0;
   }
   if(ticket == 0 || reversedAlready || ppl >= 0)
      return;
   int sig = GetSignal();
   if(sig == 0 || sig == pdir)
      return;
   if(!InSession() || TimeCurrent() >= CloseDeadline() || newsBlocked || !SpreadOK() || !VolatilityOK())
      return;
   if((sig > 0 && !InpAllowBuy) || (sig < 0 && !InpAllowSell))
      return;
   if(InpMinConfidence > 0 && ConfidenceScore(sig) < InpMinConfidence)
      return;
   double atr[];
   if(!GetBuf(hATR, atr) || atr[0] <= 0)
      return;
   PrintFormat("Reverse: closing #%I64u (%s, P/L %.2f) for a %s breakout", ticket, pdir > 0 ? "BUY" : "SELL", ppl, sig > 0 ? "BUY" : "SELL");
   if(!ClosePosition(ticket, L("กลับทาง", "reverse")))
      return;
   reverseNext = true;
   OpenTrade(sig > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, atr[0]);
   reverseNext = false;
}

//+------------------------------------------------------------------+
//| v1.55 research options: smart-money filters and one pyramid add   |
//+------------------------------------------------------------------+
bool SmcFiltersOK(int dir)
{
   if(InpFilterJudas)
   {
      datetime day0 = TimeCurrent() - TimeCurrent() % 86400;
      datetime from = day0 + InpRangeEndHour * 3600;
      datetime to   = iTime(_Symbol, InpTF, 2);
      if(to < from)
         return false;
      double hs[], ls[];
      if(CopyHigh(_Symbol, InpTF, from, to, hs) < 1 || CopyLow(_Symbol, InpTF, from, to, ls) < 1)
         return false;
      if(dir > 0 && ls[ArrayMinimum(ls)] >= orbLow)  return false;   // the low side was never taken
      if(dir < 0 && hs[ArrayMaximum(hs)] <= orbHigh) return false;
   }
   if(InpFilterFVG)
   {
      if(dir > 0 && !(iLow(_Symbol, InpTF, 1) > iHigh(_Symbol, InpTF, 3)))  return false;
      if(dir < 0 && !(iHigh(_Symbol, InpTF, 1) < iLow(_Symbol, InpTF, 3)))  return false;
   }
   if(InpFilterH1Bias)
   {
      double e50[], e200[];
      if(!GetBuf(hEma50H1, e50) || !GetBuf(hEmaH1, e200))
         return false;
      double c = iClose(_Symbol, PERIOD_H1, 1);
      if(dir > 0 && !(c > e50[0] && e50[0] > e200[0])) return false;
      if(dir < 0 && !(c < e50[0] && e50[0] < e200[0])) return false;
   }
   return true;
}

// One add in the direction of the open trade once it is InpPyramidATR x ATR in profit (checked on new bars).
void TryPyramid()
{
   if(CountPositions() != 1)
      return;
   int dir = 0;
   double open = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && IsMine())
      {
         dir  = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
         open = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   double atr[];
   if(dir == 0 || !GetBuf(hATR, atr) || atr[0] <= 0)
      return;
   double c1 = iClose(_Symbol, InpTF, 1);
   if((c1 - open) * dir < InpPyramidATR * atr[0])
      return;
   if(!InSession() || TimeCurrent() >= CloseDeadline() || newsBlocked || !SpreadOK())
      return;
   pyramidNext = true;
   OpenTrade(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, atr[0]);
   pyramidNext = false;
}

// A deal that opened a position: when it came from one of the stop orders, record the entry like a market entry.
void StopEntryFilled(ulong deal)
{
   ulong order = (ulong)HistoryDealGetInteger(deal, DEAL_ORDER);
   if(order == 0 || !HistoryOrderSelect(order))
      return;
   ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(order, ORDER_TYPE);
   if(ot != ORDER_TYPE_BUY_STOP && ot != ORDER_TYPE_SELL_STOP && ot != ORDER_TYPE_BUY_LIMIT && ot != ORDER_TYPE_SELL_LIMIT)
      return;
   int    dir   = (ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_BUY_LIMIT) ? 1 : -1;
   if(ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_SELL_LIMIT)
      seAtr = rtAtr;
   double price = HistoryDealGetDouble(deal, DEAL_PRICE);
   double lots  = HistoryDealGetDouble(deal, DEAL_VOLUME);
   double sl    = HistoryOrderGetDouble(order, ORDER_SL);
   double atr   = seAtr;
   if(atr <= 0) { double a[]; if(GetBuf(hATR, a)) atr = a[0]; }
   CaptureEntry(dir, price, sl, atr, lots);
   TesterSpreadCharge(lots);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = RiskPerLot(MathAbs(price - sl)) * lots;
   string msg = StringFormat(L("เปิด %s %.2f lot @ %s (คำสั่งรอ) | SL %s | เสี่ยง %.2f %s (%.2f%% ของ Equity)", "Opened %s %.2f lot @ %s (stop order) | SL %s | risk %.2f %s (%.2f%% of equity)"),
                             dir > 0 ? "BUY" : "SELL", lots, DoubleToString(price, _Digits), DoubleToString(sl, _Digits),
                             riskMoney, AccountInfoString(ACCOUNT_CURRENCY), eq > 0 ? riskMoney / eq * 100.0 : 0);
   if(InpNotifyTrades) Notify(msg, "OPEN"); else ConsoleLog("OPEN", msg);
   DeleteStopOrders(L("อีกฝั่งเปิดไม้แล้ว", "the other side filled"));
}

// Terminal-wide lock: only one chart of this symbol + magic may send an order within 10 s.
bool AcquireOrderLock()
{
   if(MQLInfoInteger(MQL_TESTER))
      return true;
   string name = PFX + "lock_" + _Symbol + "_" + (string)InpMagic;
   if(!GlobalVariableCheck(name))
      GlobalVariableTemp(name);
   double prev = GlobalVariableGet(name);
   double now  = (double)TimeLocal();
   if(now - prev < 10)
      return false;
   return GlobalVariableSetOnCondition(name, now, prev);
}

// Close one position and confirm it is gone; retries a few times, then alerts.
// Callers run every tick, so a failed close is tried again on the next tick.
bool ClosePosition(ulong ticket, string why)
{
   for(int attempt = 0; attempt < 3; attempt++)
   {
      if(!PositionSelectByTicket(ticket))
         return true;   // already closed
      if(trade.PositionClose(ticket))
      {
         uint rc = trade.ResultRetcode();
         if(rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED)
         {
            if(!PositionSelectByTicket(ticket))
               return true;
         }
      }
      Print(StringFormat("Close #%I64u (%s) attempt %d failed: %d %s", ticket, why, attempt + 1,
                         trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      if(!MQLInfoInteger(MQL_TESTER))
         Sleep(300);
   }
   if(!PositionSelectByTicket(ticket))
      return true;
   static datetime lastAlert = 0;
   if(TimeCurrent() - lastAlert >= 600)
   {
      lastAlert = TimeCurrent();
      Notify(StringFormat(L("⚠ ปิดไม้ #%I64u (%s) ไม่สำเร็จ: %d %s - EA จะลองใหม่ทุก tick เช็กไม้ใน MT5 ด้วย", "⚠ Could not close #%I64u (%s): %d %s - the EA retries every tick; please check MT5"),
                          ticket, why, trade.ResultRetcode(), trade.ResultRetcodeDescription()), "WARN");
   }
   return false;
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
      ConsoleLog("WARN", msg);   // the console still shows every occurrence
      return;
   }
   lastDay = dt.day_of_year;
   Notify(msg + L(" (แจ้งครั้งเดียวต่อวัน)", " (alerted once a day)"), "WARN");
}

//+------------------------------------------------------------------+
//| PowerShell console (tools\GS15_Console.ps1) - live only.          |
//| The EA writes Common\Files\GS15_<sym>_<magic>_status.txt every    |
//| second and appends events to ..._log.txt; the console writes one |
//| command into ..._cmd.txt (MODE1, MODE2, PAUSE, RESUME, CLOSEALL,     |
//| TEST, ACCOUNT); ACCOUNT also writes ..._account.txt.             |
//+------------------------------------------------------------------+
// Only the last 4 digits, so console screenshots can be shared safely.
string MaskedLogin()
{
   string s = (string)AccountInfoInteger(ACCOUNT_LOGIN);
   return StringLen(s) > 4 ? "..." + StringSubstr(s, StringLen(s) - 4) : s;
}

string ConsoleBase()
{
   return "GS15_" + _Symbol + "_" + (string)InpMagic;
}

void ConsoleLog(string kind, string msg)
{
   if(!InpConsole || MQLInfoInteger(MQL_TESTER))
      return;
   string name = ConsoleBase() + "_log.txt";
   int f = FileOpen(name, FILE_READ | FILE_WRITE | FILE_TXT | FILE_UNICODE | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(f == INVALID_HANDLE)
      return;
   if(FileSize(f) > 2 * 1024 * 1024)   // keep it small: start over past 2 MB
   {
      FileClose(f);
      FileDelete(name, FILE_COMMON);
      f = FileOpen(name, FILE_WRITE | FILE_TXT | FILE_UNICODE | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(f == INVALID_HANDLE)
         return;
   }
   FileSeek(f, 0, SEEK_END);
   string line = msg;
   StringReplace(line, "\n", " | ");
   FileWriteString(f, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\t" + kind + "\t" + line + "\r\n");
   FileClose(f);
}

void WriteConsoleStatus(int tradesToday, double profitToday)
{
   if(!InpConsole || MQLInfoInteger(MQL_TESTER))
      return;
   string ccy = AccountInfoString(ACCOUNT_CURRENCY);
   string pos = L("ไม่มี", "none");
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || !IsMine())
         continue;
      pos = StringFormat("%s %.2f @ %s | SL %s | P/L %.2f %s",
                         PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL",
                         PositionGetDouble(POSITION_VOLUME),
                         DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), _Digits),
                         DoubleToString(PositionGetDouble(POSITION_SL), _Digits),
                         PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP), ccy);
   }
   string reason = BlockReason(tradesToday, profitToday);
   string status = reason != "" ? reason : (pos != L("ไม่มี", "none") ? L("กำลังถือออเดอร์", "In a trade")
                                                                    : L("พร้อมเทรด - รอสัญญาณ", "Ready - waiting for a signal"));
   double atr[];
   string atrText = GetBuf(hATR, atr) ? DoubleToString(atr[0], 2) : "-";
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool   demo    = AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO;

   int f = FileOpen(ConsoleBase() + "_status.txt", FILE_WRITE | FILE_TXT | FILE_UNICODE | FILE_COMMON | FILE_SHARE_READ);
   if(f == INVALID_HANDLE)
      return;
   FileWriteString(f, "updated="  + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\r\n");
   FileWriteString(f, "version="  + MQLInfoString(MQL_PROGRAM_NAME) + " " + (string)VERSION_TEXT + "\r\n");
   FileWriteString(f, "account="  + MaskedLogin() + (demo ? " (Demo)" : " (REAL)") + "\r\n");
   FileWriteString(f, "symbol="   + _Symbol + "\r\n");
   FileWriteString(f, StringFormat("equity=%.2f %s\r\n", AccountInfoDouble(ACCOUNT_EQUITY), ccy));
   FileWriteString(f, StringFormat("balance=%.2f %s\r\n", AccountInfoDouble(ACCOUNT_BALANCE), ccy));
   FileWriteString(f, "mode=1\r\n");                               // single strategy (older consoles read this)
   FileWriteString(f, "modetext=" + StyleLine() + "\r\n");
   FileWriteString(f, "paused="   + (paused ? "1" : "0") + "\r\n");
   FileWriteString(f, "status="   + status + "\r\n");
   FileWriteString(f, "position=" + pos + "\r\n");
   FileWriteString(f, StringFormat("today=%d/%s | P/L %.2f %s\r\n", tradesToday,
                                   MaxTradesEff() > 0 ? (string)MaxTradesEff() : "inf", profitToday, ccy));
   FileWriteString(f, StringFormat("market=Spread %.2f / %.2f | ATR %s\r\n", spread, InpMaxSpread, atrText));
   FileWriteString(f, "news="     + (newsNextInfo != "" ? newsNextInfo : "-") + "\r\n");
   FileWriteString(f, "lang="     + (InpLanguage == LANG_TH ? "TH" : "EN") + "\r\n");

   // Plain values for the console layout (v1.41).
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskNow = -1;                    // % of equity the open trade loses at its SL (-1 = no trade / no SL)
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || !IsMine() || PositionGetDouble(POSITION_SL) <= 0 || eq <= 0)
         continue;
      double dist = MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - PositionGetDouble(POSITION_SL));
      riskNow = RiskPerLot(dist) * PositionGetDouble(POSITION_VOLUME) / eq * 100.0;
   }
   string state = pos != L("ไม่มี", "none") ? "IN TRADE"
                : paused && haltCode != 0  ? "HALTED"
                : paused                   ? "PAUSED"
                : reason != ""             ? "ENTRY BLOCKED" : "READY";
   FileWriteString(f, "state="      + state + "\r\n");
   FileWriteString(f, "reason="     + (reason != "" ? reason : (state == "IN TRADE" ? L("ดูแล SL และปิดตอน ", "Managing SL; daily close at ") + (string)InpDailyCloseHour + ":00"
                                                                                      : L("รอแท่ง M15 ที่เข้าเงื่อนไข", "Waiting for a qualifying M15 close"))) + "\r\n");
   FileWriteString(f, "tf="         + StringSubstr(EnumToString(InpTF), 7) + "\r\n");
   FileWriteString(f, "accttype="   + (demo ? "Demo" : "REAL") + "\r\n");
   FileWriteString(f, "ccy="        + ccy + "\r\n");
   FileWriteString(f, StringFormat("eqv=%.2f\r\nplv=%.2f\r\n", eq, profitToday));
   FileWriteString(f, StringFormat("trades=%d\r\nmaxtrades=%d\r\n", tradesToday, MaxTradesEff()));
   FileWriteString(f, StringFormat("risktarget=%.2f\r\nriskactual=%.2f\r\n", lotModeRt == LOT_RISK ? RiskPctEff() : 0.0, riskNow));
   FileWriteString(f, StringFormat("spreadv=%.2f\r\nspreadmax=%.2f\r\natrv=%s\r\n", spread, InpMaxSpread, atrText));
   FileWriteString(f, StringFormat("ddv=%.2f\r\nddmax=%.1f\r\nstreak=%d\r\nstreakmax=%d\r\n",
                                   equityPeak > 0 ? MathMax(0.0, (1.0 - eq / equityPeak) * 100.0) : 0.0, InpMaxDDPct, lossStreak, InpMaxLossStreak));
   FileWriteString(f, StringFormat("losingdays=%d\r\nlosingdaysmax=%d\r\n", losingDays, InpMaxLosingDays));
   FileWriteString(f, StringFormat("sessionguard=%d\r\nclosedeadline=%s\r\n", InpSessionGuard ? 1 : 0, TimeToString(CloseDeadline(), TIME_DATE | TIME_MINUTES)));
   FileWriteString(f, "servertime=" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\r\n");
   FileClose(f);
}

// One command per file; the file is deleted once read.
void ReadConsoleCommand()
{
   if(!InpConsole || MQLInfoInteger(MQL_TESTER))
      return;
   string name = ConsoleBase() + "_cmd.txt";
   if(!FileIsExist(name, FILE_COMMON))
      return;
   int f = FileOpen(name, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(f == INVALID_HANDLE)
      return;
   string cmd = FileReadString(f);
   FileClose(f);
   FileDelete(name, FILE_COMMON);
   StringTrimLeft(cmd);
   StringTrimRight(cmd);
   StringToUpper(cmd);

   if(cmd == "MODE1" || cmd == "MODE2" || cmd == "MODE3")
      ConsoleLog("INFO", L("v1.50 มีระบบเดียว (วันละ 1 ไม้) - ไม่มีการเปลี่ยนโหมด", "v1.50 has one strategy (one trade a day) - there are no modes to switch"));
   else if(cmd == "PAUSE" || cmd == "RESUME")
   {
      SetPaused(cmd == "PAUSE");
      Notify(paused ? L("หยุดเปิดไม้ใหม่ชั่วคราว (จาก console)", "Paused: no new trades (from the console)")
                    : L("กลับมาเทรดตามปกติ (จาก console)", "Trading resumed (from the console)"));
   }
   else if(cmd == "ACCOUNT")
   {
      AccountCheck(false);
      ConsoleLog("INFO", L("ตรวจบัญชีแล้ว (ดูผลด้วยปุ่ม A)", "Account check done (press A to view)"));
   }
   else if(cmd == "NEWSEXPORT")
      NewsExportHistory();
   else if(cmd == "TEST")
   {
      if(QuickTestAllowed(true))
         QuickTestStart("console");
   }
   else if(cmd == "CLOSEALL")
   {
      int n = CountPositions();
      if(n == 0)
         ConsoleLog("INFO", L("ไม่มีออเดอร์ของ EA นี้ให้ปิด", "No trades of this EA to close"));
      else
      {
         CloseAll();
         Notify(StringFormat(L("ปิดออเดอร์ทั้งหมด %d ไม้ (จาก console)", "Closed all %d trades (from the console)"), n), "WARN");
      }
   }
   else if(cmd != "")
      ConsoleLog("WARN", "Unknown console command: " + cmd);
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
            Notify(StringFormat(L("เลื่อน SL ไม้ BUY มาที่ทุนแล้ว (SL %s)", "BUY stop moved to breakeven (SL %s)"), DoubleToString(target, _Digits)));
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
            Notify(StringFormat(L("เลื่อน SL ไม้ SELL มาที่ทุนแล้ว (SL %s)", "SELL stop moved to breakeven (SL %s)"), DoubleToString(target, _Digits)));
      }
   }
}

//+------------------------------------------------------------------+
//| Status / notifications                                           |
//+------------------------------------------------------------------+
// Why no new trade may be opened right now ("" = allowed).
string BlockReason(int tradesToday, double profitToday, bool ignoreSpread = false)
{
   if(TestActive())                       return StringFormat(L("ทดสอบระบบ %d/%d ไม้", "System test %d/%d trades"), testDone, InpTestTrades);
   if(paused && haltCode == 1)            return L("หยุด: พอร์ตลดลงเกินเพดาน - ตรวจแล้วกด Resume", "Halted: drawdown limit - review, then Resume");
   if(paused && haltCode == 2)            return L("หยุด: แพ้ติดกันครบเพดาน - ตรวจแล้วกด Resume", "Halted: losing streak - review, then Resume");
   if(paused && haltCode == 3)            return L("หยุด: ขาดทุนติดกันครบจำนวนวัน - ตรวจแล้วกด Resume", "Halted: losing days in a row - review, then Resume");
   if(paused)                             return L("หยุดชั่วคราว (กดปุ่ม)", "Paused (button)");
   if(TimeCurrent() < cooldownUntil)      return L("พักหลังแพ้ ถึง ", "Pause after loss until ") + TimeToString(cooldownUntil, TIME_MINUTES);
   if(InpStopDayAfterLoss && lastLossDay == (long)(TimeCurrent() / 86400)) return L("หยุดวันนี้หลังแพ้", "Stopped for today after a losing trade");
   if(InpSkipMonday && DayOfWeekNow() == 1) return L("ไม่เทรดวันจันทร์", "No trades on Mondays");
   if(newsBlocked)                        return L("งดเทรด ช่วงข่าว", "News window - no trades");
   if(DailyLossHit(profitToday))          return L("ถึงเพดานขาดทุนวันนี้", "Daily loss limit reached");
   if(MaxTradesEff() > 0 && tradesToday >= MaxTradesEff())  return L("ครบจำนวนไม้วันนี้", "Max trades for today");
   if(!InSession())                       return L("นอกเวลาเทรด", "Outside trading hours");
   if(TimeCurrent() >= CloseDeadline())  return L("ถึงเวลาปิดประจำวัน / ตลาดใกล้ปิด", "Daily close time / market closes soon - no new trades");
   if(!ignoreSpread && !SpreadOK())       return L("สเปรดกว้างเกิน", "Spread too wide");
   if(!VolatilityOK())                    return L("ความผันผวนต่ำ - รอวันที่ตลาดวิ่ง", "Low volatility - waiting for a moving day");
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
      Notify(StringFormat(L("ขาดทุนวันนี้ %.2f %s ถึงเพดาน %.1f%% แล้ว - หยุดเปิดไม้ใหม่ถึงพรุ่งนี้", "Today's loss %.2f %s reached the %.1f%% limit - no new trades until tomorrow"),
                          profitToday, AccountInfoString(ACCOUNT_CURRENCY), InpMaxDailyLossPct), "WARN");
   }

   if(showPanel)
      UpdatePanel(tradesToday, profitToday);
   WriteConsoleStatus(tradesToday, profitToday);
}

// Single place every alert goes through (Telegram can be added here later).
// kind tags the line for the PowerShell console: INFO, OPEN, WIN, LOSS, SKIP, WARN, NEWS.
void Notify(string msg, string kind = "INFO")
{
   string full = "GoldScalper " + _Symbol + ": " + msg;
   Print(full);
   if(MQLInfoInteger(MQL_TESTER))
      return;
   ConsoleLog(kind, msg);
   if(InpNotifyPush && !SendNotification(full))
      Print("Push notification failed - is your MetaQuotes ID set in Tools > Options > Notifications? (error ",
            GetLastError(), ")");
   if(InpNotifyPopup)
      Alert(full);
}

//+------------------------------------------------------------------+
//| On-chart panel                                                   |
//+------------------------------------------------------------------+
#define PANEL_W     290
#define LINE_H      18
#define PANEL_LINES 7

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
   ObjectSetString(0, PFX + "btnClose", OBJPROP_TEXT, L("ปิดทุกไม้", "Close all"));
   MakeButton(PFX + "btnAcct", InpPanelX + 10, by + 32, 184, 24);
   ObjectSetString(0, PFX + "btnAcct", OBJPROP_TEXT, L("ตรวจบัญชี / คำแนะนำ", "Account check / advice"));
   ObjectSetInteger(0, PFX + "btnAcct", OBJPROP_BGCOLOR, C'50,80,140');
   MakeButton(PFX + "btnTest", InpPanelX + 200, by + 32, 80, 24);
   ObjectSetString(0, PFX + "btnTest", OBJPROP_TEXT, L("ทดสอบ", "Test"));
   ObjectSetInteger(0, PFX + "btnTest", OBJPROP_BGCOLOR, C'120,90,30');
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
   string posText = L("ไม่มี", "none");
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
      posText += StringFormat(L(" | มั่นใจ %d/4", " | conf. %d/4"), ti.score);

   string reason = BlockReason(tradesToday, profitToday);
   string status;
   color  statusClr;
   if(reason != "")      { status = reason;               statusClr = clrOrange; }
   else if(posCount > 0) { status = L("กำลังถือออเดอร์", "In a trade");      statusClr = clrDeepSkyBlue; }
   else                  { status = L("พร้อมเทรด - รอสัญญาณ", "Ready - waiting for a signal"); statusClr = clrLimeGreen; }

   double atr[];
   string atrText = GetBuf(hATR, atr) ? DoubleToString(atr[0], 2) : "-";
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);

   string news;
   if(!InpNewsFilter)                    news = L("ปิดตัวกรองข่าว", "news filter off");
   else if(MQLInfoInteger(MQL_TESTER))   news = L("ใช้ไม่ได้ใน Tester", "n/a in the tester");
   else if(newsNextInfo == "")           news = L("ไม่มีใน 24 ชม.", "none in 24 h");
   else                                  news = newsNextInfo;
   if(StringLen(news) > 42)
      news = StringSubstr(news, 0, 40) + "..";

   SetLine(0, "GoldScalper M15  v" + VERSION_TEXT, clrGold);
   SetLine(1, L("สถานะ: ", "Status: ") + status, statusClr);
   SetLine(2, L("ออเดอร์: ", "Trade: ") + posText, posPL < 0 ? clrTomato : clrWhiteSmoke);
   SetLine(3, StyleLine(), clrKhaki);
   SetLine(4, StringFormat(L("วันนี้: %d/%s ไม้ | P/L %.2f %s", "Today: %d/%s trades | P/L %.2f %s"), tradesToday, MaxTradesEff() > 0 ? (string)MaxTradesEff() : "∞", profitToday, ccy),
           profitToday < 0 ? clrTomato : clrWhiteSmoke);
   SetLine(5, StringFormat(L("สเปรด: %.2f / %.2f | ATR: %s", "Spread: %.2f / %.2f | ATR: %s"), spread, InpMaxSpread, atrText),
           spread > InpMaxSpread ? clrOrange : clrWhiteSmoke);
   SetLine(6, L("ข่าวถัดไป: ", "Next news: ") + news, newsBlocked ? clrOrange : clrSilver);

   string bp = PFX + "btnPause";
   ObjectSetString(0, bp, OBJPROP_TEXT, paused ? L("เทรดต่อ", "Resume") : L("หยุดชั่วคราว", "Pause"));
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

   // The calendar is not available in the Strategy Tester: use the history exported from the
   // live terminal (console command NEWSEXPORT), same events and times as live trading.
   if(MQLInfoInteger(MQL_TESTER))
      return NewsBlackoutFromFile();

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
         if(!CalendarEventById(vals[i].event_id, ev) || ev.importance < minImp || !NewsEventWanted(ev.name))
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
      Print(L("เข้าช่วงข่าว - งดเปิดไม้ใหม่: ", "News window - no new trades: "), newsBlockInfo);
      if(InpNotifyNews)
         Notify(L("เข้าช่วงข่าว งดเปิดไม้ใหม่: ", "News window started - no new trades: ") + newsBlockInfo, "NEWS");
   }
   if(!newsBlocked && wasBlocked)
   {
      Print(L("พ้นช่วงข่าว - กลับมาเทรดได้", "News window over - trading allowed"));
      if(InpNotifyNews)
         Notify(L("พ้นช่วงข่าวแล้ว กลับมาเทรดได้", "News window over - trading allowed again"), "NEWS");
   }
   return newsBlocked;
}


//+------------------------------------------------------------------+
//| News history file: export (live) and use in the Strategy Tester  |
//+------------------------------------------------------------------+
string NewsFileName()
{
   if(InpNewsFile != "")
      return InpNewsFile;
   string n = "GS15_news_" + InpNewsCurrencies + ".csv";
   StringReplace(n, ",", "_");
   StringReplace(n, " ", "");
   return n;
}

// InpNewsOnlyEvents: true when the list is empty or a part of it occurs in the event name (any case).
bool NewsEventWanted(string name)
{
   if(InpNewsOnlyEvents == "")
      return true;
   string parts[];
   int n = StringSplit(InpNewsOnlyEvents, ',', parts);
   StringToLower(name);
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      StringToLower(p);
      if(p != "" && StringFind(name, p) >= 0)
         return true;
   }
   return false;
}

// Writes every moderate/high event of InpNewsCurrencies from Dec 2017 to 3 weeks ahead, with
// times in this broker's server time (the calendar converts them), to Common\Files.
void NewsExportHistory()
{
   if(MQLInfoInteger(MQL_TESTER))
      return;
   datetime from = D'2017.12.01', to = TimeTradeServer() + 21 * 86400;
   string cur[];
   int nc = StringSplit(InpNewsCurrencies, ',', cur);
   string tmp = NewsFileName() + ".tmp";
   int f = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(f == INVALID_HANDLE)
   {
      ConsoleLog("WARN", "News export: cannot write " + tmp);
      return;
   }
   FileWriteString(f, "time_gmt,currency,importance,event\n");
   long offset = (long)(TimeTradeServer() - TimeGMT());   // the calendar applies today's offset to every date
   offset = (long)MathRound(offset / 1800.0) * 1800;
   int rows = 0, fails = 0;
   datetime last = 0;
   for(int c = 0; c < nc; c++)
   {
      StringTrimLeft(cur[c]); StringTrimRight(cur[c]); StringToUpper(cur[c]);
      if(cur[c] == "") continue;
      for(datetime a = from; a < to; a += 92 * 86400)          // quarter by quarter
      {
         datetime b = (datetime)MathMin((long)a + 92 * 86400, (long)to);
         MqlCalendarValue v[];
         if(!CalendarValueHistory(v, a, b, NULL, cur[c])) { fails++; continue; }
         for(int i = 0; i < ArraySize(v); i++)
         {
            MqlCalendarEvent ev;
            if(!CalendarEventById(v[i].event_id, ev) || ev.importance < CALENDAR_IMPORTANCE_MODERATE)
               continue;
            string nm = ev.name;
            StringReplace(nm, ",", " ");
            FileWriteString(f, StringFormat("%s,%s,%d,%s\n", TimeToString((datetime)((long)v[i].time - offset), TIME_DATE | TIME_MINUTES), cur[c], (int)ev.importance, nm));
            rows++;
            if(v[i].time > last) last = v[i].time;
         }
      }
   }
   FileClose(f);
   if(rows == 0)
   {
      FileDelete(tmp, FILE_COMMON);
      ConsoleLog("WARN", "News export: the calendar returned no events (not synchronised yet?) - try again later");
      return;
   }
   FileDelete(NewsFileName(), FILE_COMMON);
   FileMove(tmp, FILE_COMMON, NewsFileName(), FILE_COMMON | FILE_REWRITE);
   ConsoleLog("INFO", StringFormat("News history exported: %d events (%s) to Common\\Files\\%s in GMT, up to %s server time%s", rows, InpNewsCurrencies,
                                   NewsFileName(), TimeToString(last, TIME_DATE | TIME_MINUTES), fails > 0 ? StringFormat(" (%d requests failed)", fails) : ""));
}

// Live: refresh the file once a day in the background (first timer tick, then daily).
void NewsExportIfStale()
{
   if(MQLInfoInteger(MQL_TESTER) || !InpNewsFilter)
      return;
   static datetime lastTry = 0;
   if(!newsExportPending && TimeCurrent() - lastTry < 86400)
      return;
   lastTry = TimeCurrent();
   newsExportPending = false;
   if(FileIsExist(NewsFileName(), FILE_COMMON) &&
      TimeLocal() - (datetime)FileGetInteger(NewsFileName(), FILE_MODIFY_DATE, true) < 86400)
      return;
   NewsExportHistory();
}

// US daylight saving: from the second Sunday of March 07:00 GMT to the first Sunday of November 06:00 GMT.
bool UsDstAt(datetime gmt)
{
   MqlDateTime d;
   TimeToStruct(gmt, d);
   MqlDateTime m;
   ZeroMemory(m); m.year = d.year; m.mon = 3; m.day = 1;
   datetime mar1 = StructToTime(m);
   TimeToStruct(mar1, m);
   int firstSunMar = 1 + (7 - m.day_of_week) % 7;
   datetime start = mar1 + (firstSunMar + 7 - 1) * 86400 + 7 * 3600;
   ZeroMemory(m); m.year = d.year; m.mon = 11; m.day = 1;
   datetime nov1 = StructToTime(m);
   TimeToStruct(nov1, m);
   int firstSunNov = 1 + (7 - m.day_of_week) % 7;
   datetime end = nov1 + (firstSunNov - 1) * 86400 + 6 * 3600;
   return gmt >= start && gmt < end;
}

datetime NewsGmtToServer(datetime gmt)
{
   if(InpNewsServerUSDST)
      return gmt + (UsDstAt(gmt) ? 3 : 2) * 3600;
   return gmt + (TimeTradeServer() - TimeGMT());   // fixed offset
}

// Tester: load the file once and block entries inside the same windows as live trading.
bool NewsBlackoutFromFile()
{
   if(!InpNewsInTester)
   {
      static bool warned = false;
      if(!warned) { Print("News filter skipped in the tester (InpNewsInTester = false)"); warned = true; }
      return false;
   }
   if(!newsFileLoaded)
   {
      newsFileLoaded = true;
      ArrayResize(newsFileT, 0);
      int f = FileOpen(NewsFileName(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
      if(f == INVALID_HANDLE)
      {
         Print("News file Common\\Files\\", NewsFileName(), " not found - news filter skipped in this test (run the console command NEWSEXPORT on a live chart)");
         return false;
      }
      int minImp = InpNewsHighOnly ? 3 : 2, n = 0;
      bool gmt = StringFind(FileReadString(f), "time_gmt") == 0;   // header (older files: server time)
      while(!FileIsEnding(f))
      {
         string parts[];
         if(StringSplit(FileReadString(f), ',', parts) < 4) continue;
         if((int)StringToInteger(parts[2]) < minImp) continue;
         if(StringFind("," + InpNewsCurrencies + ",", "," + parts[1] + ",") < 0) continue;
         if(!NewsEventWanted(parts[3])) continue;
         ArrayResize(newsFileT, n + 1, 4096);
         datetime t = StringToTime(parts[0]);
         newsFileT[n++] = gmt ? NewsGmtToServer(t) : t;
      }
      FileClose(f);
      ArraySort(newsFileT);
      PrintFormat("News filter in the tester: %d events from %s (%s to %s)%s", n, NewsFileName(),
                  n > 0 ? TimeToString(newsFileT[0], TIME_DATE) : "-", n > 0 ? TimeToString(newsFileT[n - 1], TIME_DATE) : "-",
                  InpNewsOnlyEvents == "" ? "" : ", only: " + InpNewsOnlyEvents);
   }
   int n = ArraySize(newsFileT);
   if(n == 0)
      return false;
   datetime now = TimeCurrent();
   // first event at or after now - InpNewsMinsAfter (binary search)
   datetime lo = now - InpNewsMinsAfter * 60;
   int a = 0, b = n;
   while(a < b) { int mid = (a + b) / 2; if(newsFileT[mid] < lo) a = mid + 1; else b = mid; }
   newsBlocked = a < n && newsFileT[a] <= now + InpNewsMinsBefore * 60;
   newsBlockInfo = newsBlocked ? TimeToString(newsFileT[a], TIME_MINUTES) + " " + InpNewsCurrencies + " (file)" : "";
   return newsBlocked;
}


//+------------------------------------------------------------------+
//| "Console" chart button: asks tools\GS15_ConsoleLauncher.ps1 to    |
//| open / close the console through a file (no DLL imports).        |
//+------------------------------------------------------------------+
#define CONSOLE_REQUEST "GS15_console_request.txt"
#define CONSOLE_STATE   "GS15_console_state.txt"

void CreateConsoleButton()
{
   string b = PFX + "btnConsole";
   ObjectCreate(0, b, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, b, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, b, OBJPROP_XDISTANCE, 128);
   ObjectSetInteger(0, b, OBJPROP_YDISTANCE, 26);
   ObjectSetInteger(0, b, OBJPROP_XSIZE, 118);
   ObjectSetInteger(0, b, OBJPROP_YSIZE, 26);
   ObjectSetString(0, b, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, b, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, b, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, b, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, b, OBJPROP_ZORDER, 10);
   ObjectSetString(0, b, OBJPROP_TOOLTIP, L("เปิด/ปิดหน้าต่าง PowerShell console", "Open / close the PowerShell console"));
   UpdateConsoleButton();
}

// Launcher heartbeat and console state ("" when the launcher is not running).
string ConsoleState()
{
   int f = FileOpen(CONSOLE_STATE, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(f == INVALID_HANDLE)
      return "";
   string beat = "", con = "";
   while(!FileIsEnding(f))
   {
      string l = FileReadString(f);
      if(StringFind(l, "launcher=") == 0) beat = StringSubstr(l, 9);
      if(StringFind(l, "console=") == 0)  con  = StringSubstr(l, 8);
   }
   FileClose(f);
   if(beat == "" || beat == "stopped")
      return "";
   // The heartbeat is written in local PC time every second.
   if(MathAbs((double)(TimeLocal() - StringToTime(beat))) > 10)
      return "";
   return con;
}

void UpdateConsoleButton()
{
   string b = PFX + "btnConsole";
   if(ObjectFind(0, b) < 0)
      return;
   string st = ConsoleState();
   string text = st == "open" ? L("■  ปิด Console", "■  Close console") : st == "closed" ? L("▶  เปิด Console", "▶  Open console") : L("Console (ติดตั้ง)", "Console (set up)");
   if(ObjectGetString(0, b, OBJPROP_TEXT) == text)
      return;   // only redraw when something changed
   ObjectSetString(0, b, OBJPROP_TEXT, text);
   ObjectSetInteger(0, b, OBJPROP_BGCOLOR, st == "open" ? C'37,99,235' : C'19,33,58');
   ObjectSetInteger(0, b, OBJPROP_COLOR, st == "open" ? clrWhite : C'121,173,255');
   ObjectSetInteger(0, b, OBJPROP_BORDER_COLOR, C'38,55,80');
   ChartRedraw();
}

void ConsoleButtonClick()
{
   if(ConsoleState() == "")
   {
      string msg = L("ยังไม่ได้เปิดตัวช่วยเปิด console - รัน tools\\Install-ConsoleLauncher.ps1 หนึ่งครั้ง (หรือดับเบิลคลิกทางลัด GoldScalper Console บน Desktop)",
                     "The console launcher is not running - run tools\\Install-ConsoleLauncher.ps1 once (or use the GoldScalper Console shortcut on the Desktop)");
      Print(msg);
      ConsoleLog("WARN", msg);
      MessageBox(msg, "GoldScalperM15", MB_OK | MB_ICONINFORMATION);
      return;
   }
   int f = FileOpen(CONSOLE_REQUEST, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(f != INVALID_HANDLE)
   {
      FileWriteString(f, "TOGGLE");
      FileClose(f);
   }
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
         ClosePosition(ticket, L("ปิดทั้งหมด", "close all"));
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

int HourNow()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour;
}

//+------------------------------------------------------------------+
//| Close deadline (v1.53): the earliest of the strategy's daily close, |
//| the Friday close and - with InpSessionGuard - the end of today's    |
//| trading session minus a buffer. Only rules known in advance are     |
//| used: the broker's weekly session table, the US / EU summer-time    |
//| dates (in the weeks they differ XM gold stops at ~23:00 server) and |
//| US holidays with an early close. No knowledge of a day's last tick. |
//+------------------------------------------------------------------+
datetime MakeDate(int y, int m, int d)
{
   MqlDateTime t;
   ZeroMemory(t);
   t.year = y; t.mon = m; t.day = d;
   return StructToTime(t);
}

// Day of the month of the n-th weekday (dow 0 = Sunday) in a month; n = -1 = the last one.
int NthDow(int y, int m, int dow, int n)
{
   if(n > 0)
   {
      MqlDateTime t;
      TimeToStruct(MakeDate(y, m, 1), t);
      return 1 + (dow - t.day_of_week + 7) % 7 + (n - 1) * 7;
   }
   int last = 31;
   while(true)
   {
      MqlDateTime t;
      TimeToStruct(MakeDate(y, m, last), t);
      if(t.mon == m && t.day_of_week == dow)
         return last;
      last--;
   }
}

// Weeks when US summer time has started but EU summer time has not (March), or EU has ended but US not (Oct / Nov).
bool IsDstMismatch(datetime day)
{
   MqlDateTime t;
   TimeToStruct(day, t);
   int y = t.year;
   datetime usStart = MakeDate(y, 3, NthDow(y, 3, 0, 2)), euStart = MakeDate(y, 3, NthDow(y, 3, 0, -1));
   datetime euEnd   = MakeDate(y, 10, NthDow(y, 10, 0, -1)), usEnd = MakeDate(y, 11, NthDow(y, 11, 0, 1));
   return (day >= usStart && day < euStart) || (day >= euEnd && day < usEnd);
}

// US holidays on which gold trades with an early close (the full-closure days have no ticks anyway).
bool IsUSEarlyClose(datetime day)
{
   MqlDateTime t;
   TimeToStruct(day, t);
   int y = t.year, m = t.mon, d = t.day, w = t.day_of_week;
   if(m == 1 && d == NthDow(y, 1, 1, 3))  return true;                       // Martin Luther King Jr. Day
   if(m == 2 && d == NthDow(y, 2, 1, 3))  return true;                       // Presidents' Day
   if(m == 5 && d == NthDow(y, 5, 1, -1)) return true;                       // Memorial Day
   if(m == 9 && d == NthDow(y, 9, 1, 1))  return true;                       // Labor Day
   if(m == 11 && (d == NthDow(y, 11, 4, 4) || d == NthDow(y, 11, 4, 4) + 1)) return true;   // Thanksgiving + Friday after
   if(m == 12 && (d == 24 || d == 31) && w >= 1 && w <= 5) return true;      // Christmas Eve, New Year's Eve
   if(m == 7 && ((d == 4 && w >= 1 && w <= 5) || (d == 3 && w == 5) || (d == 5 && w == 1))) return true;   // Independence Day (observed)
   if(y >= 2022 && m == 6 && ((d == 19 && w >= 1 && w <= 5) || (d == 18 && w == 5) || (d == 20 && w == 1))) return true;   // Juneteenth (observed)
   return false;
}

// End of the last trading session of a weekday from the broker's table (seconds after midnight; 86400 = midnight).
long SessionEndSec(int dow)
{
   static long cache[7] = {-1, -1, -1, -1, -1, -1, -1};
   if(cache[dow] >= 0)
      return cache[dow];
   long end = 0;
   datetime from, to;
   for(uint i = 0; SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dow, i, from, to); i++)
      end = MathMax(end, (long)to == 0 ? 86400 : (long)to);
   cache[dow] = end > 0 ? MathMin(end, (long)86400) : 86400;
   return cache[dow];
}

datetime CloseDeadline()
{
   datetime now = TimeCurrent(), day = now - now % 86400;
   MqlDateTime d;
   TimeToStruct(now, d);
   long dl = 86400;
   if(InpDailyCloseHour >= 0)                dl = MathMin(dl, (long)InpDailyCloseHour * 3600);
   if(InpCloseFriday && d.day_of_week == 5)  dl = MathMin(dl, (long)InpFridayCloseHour * 3600);
   if(InpSessionGuard)
   {
      long sess = SessionEndSec(d.day_of_week);
      if(IsDstMismatch(day))
         sess = MathMin(sess, (long)23 * 3600);
      dl = MathMin(dl, sess - InpCloseBufferMin * 60);
      if(IsUSEarlyClose(day))
         dl = MathMin(dl, (long)InpHolidayCloseHour * 3600);
   }
   return day + (datetime)dl;
}

// Which rule set today's deadline (for the close audit).
string CloseKind()
{
   datetime now = TimeCurrent(), day = now - now % 86400;
   MqlDateTime d;
   TimeToStruct(now, d);
   if(InpSessionGuard && IsUSEarlyClose(day) && InpHolidayCloseHour * 3600 <= (InpDailyCloseHour >= 0 ? InpDailyCloseHour * 3600 : 86400))
      return "US holiday early close";
   if(InpSessionGuard && IsDstMismatch(day) && 23 * 3600 - InpCloseBufferMin * 60 < (InpDailyCloseHour >= 0 ? InpDailyCloseHour * 3600 : 86400))
      return "summer-time mismatch week";
   if(InpCloseFriday && d.day_of_week == 5 && InpFridayCloseHour < (InpDailyCloseHour >= 0 ? InpDailyCloseHour : 24))
      return "Friday close";
   return "daily close";
}

// Entries never open at or after the daily close hour (it would close them on the next tick).
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
   if(MQLInfoInteger(MQL_TESTER))
      spread *= InpTesterSpreadMult;   // spread stress (1.0 = real spread)
   return spread <= InpMaxSpread;
}

// Tester spread stress: charge the extra (mult - 1) x spread of this entry as a withdrawal, so the
// balance, the position sizes that follow and the final result include it. One row per entry in
// Common\Files\GS15_stress_<symbol>_<magic>_tester.csv for the per-trade analysis.
void TesterSpreadCharge(double lots)
{
   if(!MQLInfoInteger(MQL_TESTER) || InpTesterSpreadMult <= 1.0 || lots <= 0)
      return;
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double cost = LossPerLot((InpTesterSpreadMult - 1.0) * spread) * lots;
   if(cost <= 0)
      return;
   TesterWithdrawal(cost);
   testerExtraCost += cost;
   string name = StringFormat("GS15_stress_%s_%I64u_tester.csv", _Symbol, InpMagic);
   bool exists = FileIsExist(name, FILE_COMMON);
   int f = FileOpen(name, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(f == INVALID_HANDLE)
      return;
   if(!exists)
      FileWriteString(f, "time,lots,spread,extra_cost\r\n");
   FileSeek(f, 0, SEEK_END);
   FileWriteString(f, StringFormat("%s,%.2f,%s,%.2f\r\n", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES), lots,
                                   DoubleToString(spread, _Digits), cost));
   FileClose(f);
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
   // profitToday = realized + floating; the balance only contains the realized part.
   double floating = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && IsMine())
         floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   double startBalance = AccountInfoDouble(ACCOUNT_BALANCE) - (profitToday - floating);
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
   return NormalizeLots(AccountInfoDouble(ACCOUNT_EQUITY) * RiskPctEff() / 100.0 / RiskPerLot(slDist));
}

// Real money lost per 1 lot if the stop is hit: SL distance from the actual entry price
// (spread included, since a buy enters at the ask) + slippage allowance + commission.
double RiskPerLot(double slDist)
{
   double perLot = LossPerLot(slDist + InpSlippagePts * _Point);
   if(perLot <= 0)
      return 0;
   return perLot + InpCommissionLot;
}

//+------------------------------------------------------------------+
//| Test button: open a minimum-lot trade and close it seconds later, |
//| to prove orders really go through. Own magic number, so it never  |
//| counts as a trade of the day, a loss or a losing streak.          |
//+------------------------------------------------------------------+
ulong QuickTestMagic()
{
   return InpMagic + 1;
}

bool QuickTestAllowed(bool say)
{
   string why = "";
   bool   demo = AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO;
   if(MQLInfoInteger(MQL_TESTER))                     why = "not in the Strategy Tester";
   else if(qtTicket != 0)                             why = L("กำลังทดสอบอยู่", "a test is already running");
   else if(!demo && !InpQuickTestReal)                why = L("บัญชีจริง: ปิดไว้ (เปิดได้ที่ InpQuickTestReal)", "real account: off (InpQuickTestReal)");
   else if(CountPositions() > 0)                      why = L("มีไม้ของ EA เปิดอยู่ - ไม่ทดสอบซ้อน", "this EA has an open trade - test skipped");
   else if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
                                                      why = L("ยังไม่ได้เปิด Algo Trading", "Algo Trading is not enabled");
   if(why != "" && say)
      Notify(L("ทดสอบไม่ได้: ", "Test not started: ") + why, "WARN");
   return why == "";
}

void QuickTestStart(string source)
{
   double lots  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr[];
   double slDist = MathMax(GetBuf(hATR, atr) ? atr[0] * InpSL_ATR : ask * 0.01, MinStopDistance());
   double sl    = NormPrice(ask - slDist);   // protected even if the EA stops mid-test
   ulong  t0    = GetTickCount64();
   bool   ok    = qtTrade.Buy(lots, _Symbol, ask, sl, 0, "GS15 TEST");
   qtSendMs     = GetTickCount64() - t0;
   ulong  deal  = qtTrade.ResultDeal();
   if(!ok || deal == 0 || !HistoryDealSelect(deal))
   {
      Notify(StringFormat(L("ทดสอบล้มเหลว: เปิดไม้ไม่ได้ (%d %s) ใน %I64u ms", "TEST FAILED: could not open the trade (%d %s) after %I64u ms"),
                          qtTrade.ResultRetcode(), qtTrade.ResultRetcodeDescription(), qtSendMs), "LOSS");
      return;
   }
   qtTicket   = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   qtOpenedMs = GetTickCount64();
   qtSource   = source;
   qtOpenPx   = qtTrade.ResultPrice();
   // Hold briefly, then close at once - no alert in between, so nothing delays the close.
   if(InpQuickTestHoldMs > 0)
      Sleep(InpQuickTestHoldMs);
   QuickTestClose();
}

// Closes the test trade and reports. On failure the ticket is kept and QuickTestStep retries.
bool QuickTestClose()
{
   if(!PositionSelectByTicket(qtTicket))
   {
      Notify(L("ทดสอบ: ไม้ทดสอบถูกปิดไปก่อนแล้ว (SL หรือปิดมือ)", "TEST: the test trade was already closed (SL or by hand)"), "WARN");
      qtTicket = 0;
      return true;
   }
   double pl   = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   ulong  held = GetTickCount64() - qtOpenedMs;
   ulong  t0   = GetTickCount64();
   bool   ok   = qtTrade.PositionClose(qtTicket);
   ulong  closeMs = GetTickCount64() - t0;
   if(ok && !PositionSelectByTicket(qtTicket))
   {
      Notify(StringFormat(L("ทดสอบผ่าน (%s): BUY %.2f @ %s - เปิด %I64u ms, ถือ %I64u ms, ปิด %I64u ms, รวม %I64u ms, ค่าใช้จ่าย %.2f %s",
                            "TEST PASSED (%s): BUY %.2f @ %s - open %I64u ms, held %I64u ms, close %I64u ms, total %I64u ms, cost %.2f %s"),
                          qtSource, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), DoubleToString(qtOpenPx, _Digits),
                          qtSendMs, held, closeMs, qtSendMs + held + closeMs, pl, AccountInfoString(ACCOUNT_CURRENCY)), "WIN");
      qtTicket = 0;
      return true;
   }
   Print(StringFormat("Test close #%I64u failed: %d %s - retrying every second", qtTicket, qtTrade.ResultRetcode(), qtTrade.ResultRetcodeDescription()));
   return false;
}

// Called every second: retries a test trade that did not close, and closes any test trade
// left over from an MT5 restart.
void QuickTestStep()
{
   if(MQLInfoInteger(MQL_TESTER))
      return;
   if(qtTicket == 0)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == QuickTestMagic() && qtTrade.PositionClose(t))
            Notify(StringFormat(L("ปิดไม้ทดสอบที่ค้าง #%I64u", "Closed leftover test trade #%I64u"), t), "WARN");
      }
      return;
   }
   if(QuickTestClose())
      return;
   if(GetTickCount64() - qtOpenedMs > 30000)
   {
      Notify(StringFormat(L("ทดสอบล้มเหลว: ปิดไม้ทดสอบ #%I64u ไม่ได้ (%d %s) - ปิดเองใน MT5 (มี SL ป้องกันอยู่)",
                            "TEST FAILED: could not close test trade #%I64u (%d %s) - close it in MT5 (it has an SL)"),
                          qtTicket, qtTrade.ResultRetcode(), qtTrade.ResultRetcodeDescription()), "LOSS");
      qtTicket = 0;   // the leftover check above keeps trying every second
   }
}

//+------------------------------------------------------------------+
//| Risk guards: lot cap, drawdown halt, losing-streak halt           |
//+------------------------------------------------------------------+
// Largest lot allowed (0 = no cap): InpMaxLot, and position value <= InpMaxExposure x equity.
// Uses the tick value, so it works the same on Standard, Micro and Cent accounts.
double MaxLotCap(double price)
{
   double cap = InpMaxLot > 0 ? InpMaxLot : 0;
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(InpMaxExposure > 0 && tickVal > 0 && tickSize > 0 && price > 0)
   {
      double valuePerLot = price / tickSize * tickVal;
      double expCap = AccountInfoDouble(ACCOUNT_EQUITY) * InpMaxExposure / valuePerLot;
      cap = cap > 0 ? MathMin(cap, expCap) : expCap;
   }
   return cap;
}

// Equity peak for the drawdown halt; checked on every tick and every second.
void UpdatePeak()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0)
      return;
   if(eq > equityPeak)
   {
      equityPeak = eq;
      if(!MQLInfoInteger(MQL_TESTER))
         GlobalVariableSet(gvPeak, equityPeak);
   }
   if(InpMaxDDPct > 0 && !paused && eq < equityPeak * (1.0 - InpMaxDDPct / 100.0))
      Halt(1, StringFormat(L("Equity %.2f ลดลง %.1f%% จากจุดสูงสุด %.2f (เพดาน %.1f%%)", "equity %.2f is %.1f%% below its peak of %.2f (limit %.1f%%)"),
                           eq, (1.0 - eq / equityPeak) * 100.0, equityPeak, InpMaxDDPct));
}

// The EA pauses itself and waits for a person: open trades keep their SL and the daily close.
void Halt(int code, string why)
{
   if(MQLInfoInteger(MQL_TESTER))
   {
      if(InpTesterHaltDays == 0)
      {
         // No one can press Resume in a backtest: count it, reset and carry on.
         testerHalts[code]++;
         Print("Risk guard would halt here: ", why);
         ResetGuards();
         return;
      }
      // Like live: pause; a person resumes after InpTesterHaltDays (an assumption), or never (-1).
      if(paused)
         return;
      testerHalts[code]++;
      SetPaused(true);
      haltCode = code;
      testerResumeAt = InpTesterHaltDays > 0 ? TimeCurrent() + InpTesterHaltDays * 86400 : 0;
      Print("Risk guard halts here (tester, like live): ", why,
            InpTesterHaltDays > 0 ? StringFormat(" - simulated Resume after %d days", InpTesterHaltDays) : " - paused to the end of the test");
      return;
   }
   if(paused)
      return;
   SetPaused(true);
   haltCode = code;
   GlobalVariableSet(gvHalt, code);
   Notify(L("หยุดเปิดไม้ใหม่อัตโนมัติ: ", "Halted - no new trades: ") + why +
          L(" | ไม้ที่ถืออยู่ยังมี SL ตรวจดูแล้วกด Resume (แผงหรือ console)", " | Open trades keep their SL. Review, then press Resume (panel or console)"), "WARN");
}

// Resuming after a halt starts the counters afresh, so it does not halt again at once.
void ResetGuards()
{
   equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   lossStreak = 0;
   losingDays = 0;
   haltCode   = 0;
   if(!MQLInfoInteger(MQL_TESTER))
   {
      GlobalVariableSet(gvPeak, equityPeak);
      GlobalVariableSet(gvStreak, 0);
      GlobalVariableSet(gvLosingDays, 0);
      GlobalVariableSet(gvHalt, 0);
   }
}

void SetPaused(bool p)
{
   if(!p && paused && haltCode != 0)
      ResetGuards();
   paused = p;
   GlobalVariableSet(gvPaused, paused ? 1 : 0);
}

//+------------------------------------------------------------------+
//| Looking after the bot (v1.51): duplicate guard, start/stop        |
//| notices, losing-days halt, daily summary                          |
//+------------------------------------------------------------------+
bool AnotherCopyRunning()
{
   string me = MQLInfoString(MQL_PROGRAM_NAME);
   for(long c = ChartFirst(); c >= 0; c = ChartNext(c))
      if(c != ChartID() && ChartSymbol(c) == _Symbol && ChartGetString(c, CHART_EXPERT_NAME) == me)
         return true;
   return false;
}

string Duration(long secs)
{
   if(secs < 3600)  return StringFormat(L("%d นาที", "%d min"), (int)(secs / 60));
   if(secs < 86400) return StringFormat(L("%d ชม. %d นาที", "%d h %d min"), (int)(secs / 3600), (int)(secs % 3600 / 60));
   return StringFormat(L("%d วัน %d ชม.", "%d days %d h"), (int)(secs / 86400), (int)(secs % 86400 / 3600));
}

// The status file is rewritten every second while the EA runs, so its age is how long it was off
// (PC off, MT5 closed, power cut).
void NotifyStarted()
{
   string sf = ConsoleBase() + "_status.txt";
   string gap = "";
   if(InpConsole && FileIsExist(sf, FILE_COMMON))
   {
      datetime last = (datetime)FileGetInteger(sf, FILE_MODIFY_DATE, true);
      long secs = (long)(TimeLocal() - last);
      if(secs >= 120)
         gap = StringFormat(L(" | ไม่ได้ทำงาน %s (ตั้งแต่ %s เวลาคอม)", " | was not running for %s (since %s PC time)"), Duration(secs),
                            TimeToString(last, TIME_DATE | TIME_MINUTES));
   }
   Notify(StringFormat(L("EA เริ่มทำงาน v%s บัญชี %s", "EA started v%s, account %s"), VERSION_TEXT, MaskedLogin()) + gap, "INFO");
}

// Closed P/L of this EA on one server day (day number = time / 86400); trades = entries that day.
double DayPL(long day, int &trades)
{
   trades = 0;
   double pl = 0;
   datetime from = (datetime)(day * 86400), to = from + 86400;
   if(!HistorySelect(from, to - 1))
      return 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
         (ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         trades++;
      pl += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   }
   return pl;
}

// After each server day: a day with a loss adds one, a day with a profit resets; days without trades
// change nothing. Days the EA was not running are counted from the history when it starts again.
void CheckLosingDays()
{
   long today = (long)(TimeCurrent() / 86400);
   if(today <= 0)
      return;
   if(dayEvaluated == 0 || dayEvaluated < today - 10)
      dayEvaluated = today - 1;
   if(dayEvaluated >= today - 1)
      return;
   for(long d = dayEvaluated + 1; d < today; d++)
   {
      int trades;
      double pl = DayPL(d, trades);
      if(trades == 0 && pl == 0)
         continue;
      if(pl < 0)       losingDays++;
      else if(pl > 0)  losingDays = 0;
   }
   dayEvaluated = today - 1;
   if(!MQLInfoInteger(MQL_TESTER))
   {
      GlobalVariableSet(gvLosingDays, losingDays);
      GlobalVariableSet(gvDayEval, (double)dayEvaluated);
   }
   if(InpMaxLosingDays > 0 && losingDays >= InpMaxLosingDays)
      Halt(3, StringFormat(L("ขาดทุนติดกัน %d วัน (เพดาน %d)", "%d losing days in a row (limit %d)"), losingDays, InpMaxLosingDays));
}

// Once a weekday, a few minutes after the daily close (or 23:00 server when the daily close is off).
void DailySummaryStep()
{
   if(!InpDailySummary || MQLInfoInteger(MQL_TESTER))
      return;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int at = InpDailyCloseHour >= 0 ? InpDailyCloseHour : 23;
   if(t.day_of_week < 1 || t.day_of_week > 5 || t.hour < at || (t.hour == at && t.min < 5))
      return;
   long today = (long)(TimeCurrent() / 86400);
   if(GlobalVariableCheck(gvSummaryDay) && (long)GlobalVariableGet(gvSummaryDay) >= today)
      return;
   GlobalVariableSet(gvSummaryDay, (double)today);
   int trades;
   double pl = DayPL(today, trades);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   string ccy = AccountInfoString(ACCOUNT_CURRENCY);
   int tt;
   double pt;
   GetTodayStats(tt, pt);
   string reason = BlockReason(tt, pt, true);
   Notify(StringFormat(L("สรุปวันนี้: %d ไม้, กำไร/ขาดทุน %.2f %s | Balance %.2f | DD จากจุดสูงสุด %.1f%% | แพ้ติดกัน %d ไม้, ขาดทุนติดกัน %d วัน | สถานะ: %s",
                         "Today: %d trade(s), P/L %.2f %s | balance %.2f | drawdown from peak %.1f%% | losses in a row %d, losing days in a row %d | state: %s"),
                       trades, pl, ccy, AccountInfoDouble(ACCOUNT_BALANCE),
                       equityPeak > 0 ? MathMax(0.0, (1.0 - eq / equityPeak) * 100.0) : 0.0, lossStreak, losingDays,
                       paused ? reason : L("ทำงานปกติ", "running")), "INFO");
}

//+------------------------------------------------------------------+
//| One strategy: the first range breakout of the day                |
//+------------------------------------------------------------------+
int MaxTradesEff()
{
   return InpMaxTradesPerDay;
}

double RiskPctEff()
{
   return riskPctRt;
}

string StyleLine()
{
   string size = lotModeRt == LOT_FIXED ? StringFormat("%.2f lot", InpLots)
                                        : StringFormat(L("เสี่ยง %.1f%%", "risk %.1f%%"), RiskPctEff());
   return StringFormat(L("เบรกกรอบเอเชีย วันละ 1 ไม้ | %s", "Asian-range breakout, one trade a day | %s"), size);
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
// a recommendation, and lets the user pick an option (popup) or only prints it to the
// Experts tab (no answer needed, the EA keeps running). Live/demo only (never in the tester).
void AccountCheck(bool popup)
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
      perLot = RiskPerLot(slDist);   // SL + slippage allowance + commission
   }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0 || eq <= 0 || perLot <= 0)
   {
      if(!popup)
      {
         accountCheckPending = true;   // price data still loading: retry on the next timer tick
         return;
      }
      MessageBox(L("ยังวิเคราะห์ไม่ได้ ข้อมูลราคายังโหลดไม่ครบ\nลองกดปุ่ม \"ตรวจบัญชี\" บนแผงอีกครั้งภายหลัง",
                   "Cannot analyse yet - price data is still loading.\nPress \"Account check\" on the panel again later."),
                 title, MB_OK | MB_ICONINFORMATION);
      return;
   }

   double slMin      = perLot * minLot;                 // money lost at min lot if SL is hit
   double riskMinPct = slMin / eq * 100.0;
   double lots       = CalcLots(slDist);
   double riskNow    = perLot * lots;
   double riskNowPct = riskNow / eq * 100.0;
   double marginMin  = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, minLot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginMin))
      marginMin = 0;
   bool   strict     = lotModeRt == LOT_RISK && InpStrictRisk;
   double maxRisk    = strict ? RiskPctEff() : (InpMaxRiskPct > 0 ? InpMaxRiskPct : 5.0);
   double needMin    = slMin / (maxRisk / 100.0);       // smallest balance the risk guard accepts
   double need1      = slMin / 0.01;                    // balance for 1% risk at min lot
   bool   canRisk1   = eq * 0.01 / perLot >= minLot;   // 1%-risk sizing gives at least the min lot
   // Account kind: Cent = balance in US cents; Micro = contract 100x smaller than standard gold (100 oz).
   string ccyUp = ccy;
   StringToUpper(ccyUp);
   bool   cent  = StringFind(ccyUp, "USC") == 0;
   bool   micro = !cent && contract > 0 && contract <= 10;
   string kind  = cent ? "Cent" : micro ? "Micro" : "Standard";
   string usd   = cent ? StringFormat(" (~%.2f USD)", bal / 100.0) : "";

   string mode       = lotModeRt == LOT_FIXED ? L("Lot คงที่", "fixed lot")
                                              : StringFormat(L("คำนวณจาก %.1f%%", "%.1f%% risk"), RiskPctEff());

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
   if(marginMin > freeM || (InpMaxRiskPct > 0 && riskNowPct > InpMaxRiskPct) ||
      (strict && riskNowPct > RiskPctEff() * 1.0001))                         level = 0;
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

   if(!popup)
   {
      string lines[];
      int n = StringSplit(m, '\n', lines);
      Print("==== ", title, " ====");
      for(int i = 0; i < n; i++)
         if(lines[i] != "")
            Print(lines[i]);
      Print(L("(EA ทำงานต่อตามการตั้งค่าเดิม - กดปุ่ม \"ตรวจบัญชี\" บนแผงเพื่อดูทางเลือก)",
              "(The EA keeps running with your settings - press \"Account check\" on the panel for options)"));
      Print("==== ", L("การเทรดตอนนี้: ", "Trading now: "), StyleLine(), " ====");
      // The same text for the PowerShell console's Account view (key A).
      if(InpConsole && !MQLInfoInteger(MQL_TESTER))
      {
         int f = FileOpen(ConsoleBase() + "_account.txt", FILE_WRITE | FILE_TXT | FILE_UNICODE | FILE_COMMON | FILE_SHARE_READ);
         if(f != INVALID_HANDLE)
         {
            FileWriteString(f, "updated=" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\r\n");
            FileWriteString(f, "title=" + title + "\r\n");
            for(int i = 0; i < n; i++)
               if(lines[i] != "")
                  FileWriteString(f, lines[i] + "\r\n");
            FileWriteString(f, "\r\n" + L("การเทรดตอนนี้: ", "Trading now: ") + StyleLine() + "\r\n");
            FileClose(f);
         }
      }
      return;
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
      SetPaused(true);
   }
   if(level == 0 && answer == IDCANCEL)
      ExpertRemove();
}
