//+------------------------------------------------------------------+
//|                                              GoldScalperM15.mq5  |
//|  XAUUSD M15 intraday EA. Default (v1.30): Asian-range breakout    |
//|  on volatile days, wide ATR stop, flat by 20:00 (no swap).         |
//|  Other selectable strategies: EMA pullback, Donchian, RSI(2).     |
//|  Fixed lot, ATR-based SL/TP, breakeven, trailing stop,            |
//|  session / spread / daily-trade / daily-loss / news filters,      |
//|  on-chart control panel and phone push notifications.             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 Kla1524 - MIT License"
#property link      "https://github.com/Kla1524/GoldScalperM15"
#property version   "1.43"
#define   VERSION_TEXT "1.43"
#property description "XAUUSD M15 intraday - Asian-range breakout, volatility & news filters, panel"
#property description "For education and research only - not investment advice."

#include <Trade\Trade.mqh>
#include "GS15_SMC.mqh"

enum ENUM_STRATEGY
{
   STRAT_PULLBACK = 0,  // EMA pullback (v1.x)
   STRAT_BREAKOUT = 1,  // Donchian breakout with the trend
   STRAT_RSI2     = 2,  // RSI(2) pullback in the trend
   STRAT_ORB      = 3   // Opening Range Breakout (Asian session range)
};

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

enum ENUM_TRADE_STYLE
{
   STYLE_ONE   = 1,  // Mode 1: one bigger trade a day
   STYLE_MULTI = 2,  // Mode 2: several smaller trades (no daily limit)
   STYLE_SMC   = 3   // Mode 3: SMC - FVG + CHoCH + OB (experimental)
};

//--- inputs
input group "=== General ==="
input ENUM_TRADE_STYLE InpTradeStyle     = STYLE_ONE; // Trade mode (can be switched with the panel buttons)
input double          InpMultiRiskPct    = 0.5;       // Risk % per trade in mode 2
input ENUM_LOT_MODE   InpLotMode         = LOT_RISK;  // Lot sizing (risk % follows the account size)
input double          InpLots            = 0.01;      // Fixed lot (when lot sizing = fixed)
input double          InpRiskPct         = 1.0;       // Risk % per trade in mode 1 (when lot sizing = risk %)
input ulong           InpMagic           = 20261013;  // Magic number
input ENUM_TIMEFRAMES InpTF              = PERIOD_M15;// Signal timeframe
input ENUM_STRATEGY   InpStrategy        = STRAT_ORB; // Strategy
input bool            InpAllowBuy        = true;      // Allow buys
input bool            InpAllowSell       = true;      // Allow sells

input group "=== Mode 3: SMC (FVG + CHoCH + OB) - experimental ==="
input ENUM_TIMEFRAMES InpSmcTfBias      = PERIOD_H1;  // [SMC] bias and support/resistance timeframe
input ENUM_TIMEFRAMES InpSmcTfStructure = PERIOD_M15; // [SMC] CHoCH / order block / FVG timeframe
input ENUM_TIMEFRAMES InpSmcTfEntry     = PERIOD_M5;  // [SMC] confirmation candle timeframe
input int    InpSmcAtrPeriod      = 14;    // [SMC] ATR period (all SMC timeframes)
input int    InpSmcPivotLeft      = 2;     // [SMC] swing pivot: bars to the left
input int    InpSmcPivotRight     = 2;     // [SMC] swing pivot: bars to the right (confirmation delay)
input bool   InpSmcBiasFilter     = true;  // [SMC] trade only in the H1 bias direction (skip neutral)
input int    InpSmcSRLookback     = 100;   // [SMC] H1 bars used for support/resistance swings
input double InpSmcSRTolAtr       = 0.2;   // [SMC] merge S/R levels within x H1 ATR
input double InpSmcBreakBufAtr    = 0.1;   // [SMC] CHoCH close must clear the swing by x M15 ATR
input int    InpSmcObMaxBack      = 10;    // [SMC] order block: max bars back from the CHoCH bar
input double InpSmcDispAtr        = 1.0;   // [SMC] displacement: impulse candle body >= x M15 ATR
input double InpSmcFvgMinAtr      = 0.1;   // [SMC] minimum FVG width, x M15 ATR
input int    InpSmcFvgWindow      = 3;     // [SMC] FVG must form within x bars after the CHoCH bar
input bool   InpSmcRequireOverlap = false; // [SMC] entry zone = OB/FVG overlap only (skip if none)
input double InpSmcRiskPct        = 0.5;   // [SMC] risk % of equity per trade
input double InpSmcMinRR          = 1.5;   // [SMC] minimum reward:risk after costs
input double InpSmcSlBufAtr       = 0.2;   // [SMC] SL buffer beyond OB / setup swing, x M15 ATR
input double InpSmcTpBufAtr       = 0.1;   // [SMC] TP placed x M15 ATR before the H1 zone
input int    InpSmcExpiryBars     = 16;    // [SMC] setup expires after x M15 bars
input int    InpSmcRolloverHour   = 0;     // [SMC] broker rollover (swap) hour, server time (XM: 00:00)
input int    InpSmcNoEntryBeforeMin = 60;  // [SMC] no entries x minutes before the rollover
input int    InpSmcNoEntryAfterMin  = 60;  // [SMC] no entries x minutes after the rollover
input int    InpSmcCloseBeforeMin = 15;    // [SMC] close mode-3 trades x minutes before the rollover
input bool   InpSmcAllowReal      = false; // [SMC] allow mode 3 on a real account (demo-only until verified)
input int    InpSmcLookbackBars   = 300;   // [SMC] M15 bars loaded for structure
input bool   InpSmcDraw           = true;  // [SMC] draw zones, OB, FVG and CHoCH on the chart

input group "=== Entry signal ==="
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_CURRENT; // Trend EMA timeframe (CURRENT = signal timeframe)
input int    InpTrendEMA    = 200;   // Trend EMA period
input int    InpFastEMA     = 9;     // [Pullback] fast EMA
input int    InpSlowEMA     = 21;    // [Pullback] slow EMA
input int    InpBreakoutBars = 20;   // [Breakout] Donchian bars
input int    InpRSI2Period  = 2;     // [RSI2] RSI period
input double InpRSI2Entry   = 10.0;  // [RSI2] buy when RSI < x (sell when > 100-x)
input double InpRSI2Exit    = 70.0;  // [RSI2] close buy when RSI > x (sell when < 100-x, 0 = off)
input bool   InpUseTrend    = false; // Use the trend EMA filter (always on for Pullback)
input int    InpRangeStartHour = 0;  // [ORB] range start (hour, server time)
input int    InpRangeEndHour   = 8;  // [ORB] range end / breakouts from (hour, server time)
input int    InpRSIPeriod   = 14;    // [Pullback] RSI period
input double InpRSIBuyMin   = 50.0;  // [Pullback] min RSI for buys
input double InpRSIBuyMax   = 70.0;  // [Pullback] max RSI for buys (no chasing)
input double InpRSISellMin  = 30.0;  // [Pullback] min RSI for sells (no chasing)
input double InpRSISellMax  = 50.0;  // [Pullback] max RSI for sells

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
input bool   InpStrictRisk      = true; // Skip a trade if its real risk (vs equity) exceeds the current mode's % (risk-% sizing)
input int    InpSlippagePts     = 30;   // Slippage allowance at the SL (points), counted in the real risk
input double InpCommissionLot   = 0.0;  // Round-turn commission per 1 lot (account currency; XM Standard = 0)
input double InpMaxRiskPct      = 5.0;  // Hard cap: skip if the SL would lose more than % of equity (0 = off)
input int    InpMaxTradesPerDay = 1;    // Max trades per day in mode 1 (0 = unlimited)
input double InpMaxDailyLossPct = 3.0;  // Daily loss limit, % of start-of-day balance (0 = off)
input double InpMaxDDPct        = 20.0; // Halt: pause when equity falls this % below its peak (0 = off)
input int    InpMaxLossStreak   = 5;    // Halt: pause after this many losing trades in a row (0 = off)
input double InpMaxLot          = 0.0;  // Max lot per trade (0 = off)
input double InpMaxExposure     = 10.0; // Max position value as a multiple of equity, caps the lot (0 = off)
input int    InpDailyCloseHour  = 20;   // Close all trades daily at this hour (avoids swap, -1 = off)
input bool   InpCloseFriday     = true; // Close trades before the Friday market close
input int    InpFridayCloseHour = 21;   // Friday close hour (server time)

input group "=== News filter (MT5 economic calendar) ==="
input bool   InpNewsFilter       = true;   // Enable the news filter
input string InpNewsCurrencies   = "USD";  // Currencies to watch (comma separated, e.g. USD,EUR)
input bool   InpNewsHighOnly     = true;   // true = high impact only, false = medium + high
input int    InpNewsMinsBefore   = 30;     // No new trades before the event (minutes)
input int    InpNewsMinsAfter    = 30;     // No new trades after the event (minutes)
input bool   InpNewsClosePos     = false;  // Close open trades when a news window starts
input bool   InpNewsInTester     = true;   // Strategy Tester: apply the filter from the exported news file
input string InpNewsFile         = "";     // News history file in Common\Files ("" = GS15_news_<currencies>.csv)
input bool   InpNewsServerUSDST  = true;   // Tester: server time = GMT+2, GMT+3 during US daylight saving (XM and most brokers)

input group "=== Notifications ==="
input bool   InpNotifyPush   = true;   // Push notifications to the MT5 mobile app
input bool   InpNotifyPopup  = false;  // Alert window on the PC
input bool   InpNotifyTrades = true;   // Notify trade open / close / breakeven
input bool   InpNotifyNews   = true;   // Notify news windows

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
int       hFast, hSlow, hTrend, hRSI, hRSI2, hATR, hATRD1, hEmaH1, hEmaD1, hAdxH1;
int       hSmcAtrBias = INVALID_HANDLE, hSmcAtrStruct = INVALID_HANDLE;
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
int      testerHalts[3]  = {0, 0, 0};   // tester: how often each halt would have fired
ENUM_TRADE_STYLE styleRt = STYLE_ONE;   // mode in effect (input, or chosen with the panel buttons)
string   gvStyle         = "";
string   gvStyleIn       = "";          // the input value when the mode was chosen
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
   if(InpFastEMA >= InpSlowEMA)
   {
      Print("InpFastEMA must be smaller than InpSlowEMA");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLotMode == LOT_RISK && (InpRiskPct <= 0 || (InpMaxRiskPct > 0 && InpRiskPct > InpMaxRiskPct)))
   {
      Print("InpRiskPct must be > 0 and <= InpMaxRiskPct (", InpMaxRiskPct, "%) - otherwise every trade is skipped");
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
   hSmcAtrBias   = iATR(_Symbol, InpSmcTfBias, InpSmcAtrPeriod);
   hSmcAtrStruct = iATR(_Symbol, InpSmcTfStructure, InpSmcAtrPeriod);

   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hTrend == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hRSI2 == INVALID_HANDLE || hATR == INVALID_HANDLE ||
      hATRD1 == INVALID_HANDLE || hEmaH1 == INVALID_HANDLE || hEmaD1 == INVALID_HANDLE ||
      hAdxH1 == INVALID_HANDLE || hSmcAtrBias == INVALID_HANDLE || hSmcAtrStruct == INVALID_HANDLE)
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
   if(!MQLInfoInteger(MQL_TESTER))
   {
      equityPeak = GlobalVariableCheck(gvPeak) ? GlobalVariableGet(gvPeak) : 0;
      lossStreak = GlobalVariableCheck(gvStreak) ? (int)GlobalVariableGet(gvStreak) : 0;
      haltCode   = paused && GlobalVariableCheck(gvHalt) ? (int)GlobalVariableGet(gvHalt) : 0;
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

   // Trade mode chosen on the panel survives restarts, until the input itself is edited.
   styleRt   = InpTradeStyle;
   gvStyle   = PFX + "style_" + _Symbol + "_" + (string)InpMagic;
   gvStyleIn = PFX + "styleIn_" + _Symbol + "_" + (string)InpMagic;
   if(!MQLInfoInteger(MQL_TESTER))
   {
      if(GlobalVariableCheck(gvStyle) && GlobalVariableCheck(gvStyleIn) &&
         (int)GlobalVariableGet(gvStyleIn) == (int)InpTradeStyle)
         styleRt = (ENUM_TRADE_STYLE)(int)GlobalVariableGet(gvStyle);
      else
         SaveStyle();
   }
   if(InpSmcRiskPct <= 0 || (InpMaxRiskPct > 0 && InpSmcRiskPct > InpMaxRiskPct) || InpSmcPivotLeft < 1 || InpSmcPivotRight < 1)
   {
      Print("InpSmcRiskPct must be > 0 and <= InpMaxRiskPct, SMC pivots >= 1");
      return INIT_PARAMETERS_INCORRECT;
   }
   SmcRestore();
   if(InpJournal && MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
      FileDelete(SmcJournalName(), FILE_COMMON);
   if(InpMultiRiskPct <= 0 || (InpMaxRiskPct > 0 && InpMultiRiskPct > InpMaxRiskPct))
   {
      Print("InpMultiRiskPct must be > 0 and <= InpMaxRiskPct (", InpMaxRiskPct, "%)");
      return INIT_PARAMETERS_INCORRECT;
   }

   showPanel = InpShowPanel && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));
   if(InpConsole && InpConsoleButton && !MQLInfoInteger(MQL_TESTER))
      CreateConsoleButton();
   if(showPanel)
      CreatePanel();

   // Each single tester run starts a fresh journal (live trading appends).
   if(InpJournal && MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
      FileDelete(JournalName(), FILE_COMMON);

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
   if(MQLInfoInteger(MQL_TESTER) && (InpMaxDDPct > 0 || InpMaxLossStreak > 0))
      PrintFormat("Risk guards in this test: drawdown halt %d time(s), losing-streak halt %d time(s) "
                  "(live trading pauses until you resume; the tester carries on)", testerHalts[1], testerHalts[2]);
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
   IndicatorRelease(hSmcAtrBias);
   IndicatorRelease(hSmcAtrStruct);
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
   ManagePositions();
   UpdatePeak();

   if(InpCloseFriday && IsFridayClose())
   {
      if(CountPositions() > 0)
      {
         CloseAll();
         Notify(L("ปิดออเดอร์ทั้งหมดก่อนตลาดปิดวันศุกร์", "Closed all trades before the Friday market close"));
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
         if(ticket > 0 && IsMine() && !IsSmcPosition() &&   // mode-3 trades follow the rollover rule
            (now.hour >= InpDailyCloseHour || (datetime)PositionGetInteger(POSITION_TIME) < today))
            ClosePosition(ticket, L("ปิดประจำวัน", "daily close"));
      }
   }

   bool newsNow = NewsBlackout();
   if(newsNow && InpNewsClosePos && CountPositions() > 0)
   {
      CloseAll();
      Notify(L("ปิดออเดอร์เพราะเข้าช่วงข่าว: ", "Closed trades for a news window: ") + newsBlockInfo, "NEWS");
   }

   TrackOpenTrade();
   SmcManagePositions();

   if(styleRt == STYLE_SMC)
   {
      SmcOnTick();
      return;
   }

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
         string skipMsg = StringFormat(L("ข้ามสัญญาณ %s: ความมั่นใจต่ำ %d/4 (ต้อง >= %d)", "Skipped %s signal: low confidence %d/4 (needs >= %d)"), signal > 0 ? "BUY" : "SELL", score, InpMinConfidence);
         Print(skipMsg);
         ConsoleLog("SKIP", skipMsg);
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
         ClosePosition(ticket, "RSI2 exit");
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
   bool   smcTrade = IsSmcPositionId((ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
   if(smcTrade)
   {
      SmcJournal("CLOSE", exitCode, price, 0, 0, 0, 0, 0, pl);
      tiValid = false;
   }
   if(pl < 0)
   {
      if(smcTrade)
      {
         codes = "SMC_" + exitCode;
         thai  = L("โหมด 3 SMC: ", "mode 3 SMC: ") + (exitCode == "SL" ? L("โดน SL ใต้/เหนือ order block", "stopped beyond the order block")
                                                                     : L("ปิดก่อน rollover หรือปิดมือ", "closed before rollover or by hand"));
      }
      else
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
   else if(sparam == PFX + "btnStyle1" || sparam == PFX + "btnStyle2")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ChooseStyle(sparam == PFX + "btnStyle1" ? STYLE_ONE : STYLE_MULTI);
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
      Notify(StringFormat(L("ข้าม %s: Lot ขั้นต่ำ %.2f ถ้าโดน SL จะเสีย %.2f %s (%.2f%% ของ Equity %.2f) เกินเป้าโหมด %d ที่ %.1f%% "
                            "[SL %.2f + slippage %d จุด + คอมฯ] - ต้องมี Equity ~%.0f %s หรือใช้บัญชี Micro/Cent",
                            "Skipped %s: min lot %.2f would lose %.2f %s at the SL (%.2f%% of equity %.2f), above the mode %d target of %.1f%% "
                            "[SL %.2f + slippage %d pts + commission] - needs equity of ~%.0f %s or a Micro/Cent account"),
                          side, lots, riskMoney, ccy, riskMoney / equity * 100.0, equity, (int)styleRt, RiskPctEff(),
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
   if(!AcquireOrderLock() || CountPositions() > 0)
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

   bool ok = isBuy ? trade.Buy(lots, _Symbol, ask, sl, tp, "GoldScalper BUY")
                   : trade.Sell(lots, _Symbol, bid, sl, tp, "GoldScalper SELL");
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
         ok = isBuy ? trade.Buy(lots, _Symbol, ask, sl, tp, "GoldScalper BUY")
                    : trade.Sell(lots, _Symbol, bid, sl, tp, "GoldScalper SELL");
   }
   if(ok)
   {
      CaptureEntry(isBuy ? 1 : -1, trade.ResultPrice() > 0 ? trade.ResultPrice() : price, sl, atr, lots);
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
   FileWriteString(f, "mode="     + (string)(int)styleRt + "\r\n");
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
   FileWriteString(f, "servertime=" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\r\n");
   SmcWriteStatus(f);
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
   {
      ENUM_TRADE_STYLE target = cmd == "MODE1" ? STYLE_ONE : cmd == "MODE2" ? STYLE_MULTI : STYLE_SMC;
      if(target == styleRt)
         ConsoleLog("INFO", StringFormat(L("โหมด %d ใช้อยู่แล้ว", "Mode %d is already active"), (int)target));
      else
      {
         styleRt = target;
         SaveStyle();
         Notify(StringFormat(L("เปลี่ยนเป็นโหมด %d แล้ว (จาก console): %s", "Switched to mode %d (from the console): %s"),
                             (int)target, StyleLine()));
      }
   }
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
string BlockReason(int tradesToday, double profitToday)
{
   if(TestActive())                       return StringFormat(L("ทดสอบระบบ %d/%d ไม้", "System test %d/%d trades"), testDone, InpTestTrades);
   if(paused && haltCode == 1)            return L("หยุด: พอร์ตลดลงเกินเพดาน - ตรวจแล้วกด Resume", "Halted: drawdown limit - review, then Resume");
   if(paused && haltCode == 2)            return L("หยุด: แพ้ติดกันครบเพดาน - ตรวจแล้วกด Resume", "Halted: losing streak - review, then Resume");
   if(paused)                             return L("หยุดชั่วคราว (กดปุ่ม)", "Paused (button)");
   if(TimeCurrent() < cooldownUntil)      return L("พักหลังแพ้ ถึง ", "Pause after loss until ") + TimeToString(cooldownUntil, TIME_MINUTES);
   if(newsBlocked)                        return L("งดเทรด ช่วงข่าว", "News window - no trades");
   if(DailyLossHit(profitToday))          return L("ถึงเพดานขาดทุนวันนี้", "Daily loss limit reached");
   if(MaxTradesEff() > 0 && tradesToday >= MaxTradesEff())  return L("ครบจำนวนไม้วันนี้", "Max trades for today");
   if(styleRt == STYLE_SMC)
   {
      string t = SmcTimeBlock();
      if(t != "")                         return t;
   }
   else if(!InSession())                  return L("นอกเวลาเทรด", "Outside trading hours");
   if(!SpreadOK())                        return L("สเปรดกว้างเกิน", "Spread too wide");
   if(styleRt != STYLE_SMC && !VolatilityOK()) return L("ความผันผวนต่ำ - รอวันที่ตลาดวิ่ง", "Low volatility - waiting for a moving day");
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
   int h = 10 + LINE_H * PANEL_LINES + 104;
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
   MakeButton(PFX + "btnStyle1", InpPanelX + 10,  by + 32, 130, 24);
   MakeButton(PFX + "btnStyle2", InpPanelX + 150, by + 32, 130, 24);
   ObjectSetString(0, PFX + "btnStyle1", OBJPROP_TEXT, L("โหมด 1: วันละ 1 ไม้", "Mode 1: one/day"));
   ObjectSetString(0, PFX + "btnStyle2", OBJPROP_TEXT, L("โหมด 2: หลายไม้", "Mode 2: multi"));
   MakeButton(PFX + "btnAcct", InpPanelX + 10, by + 64, 184, 24);
   ObjectSetString(0, PFX + "btnAcct", OBJPROP_TEXT, L("ตรวจบัญชี / คำแนะนำ", "Account check / advice"));
   ObjectSetInteger(0, PFX + "btnAcct", OBJPROP_BGCOLOR, C'50,80,140');
   MakeButton(PFX + "btnTest", InpPanelX + 200, by + 64, 80, 24);
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
   ObjectSetInteger(0, PFX + "btnStyle1", OBJPROP_BGCOLOR, styleRt == STYLE_ONE   ? C'40,130,70' : C'60,64,80');
   ObjectSetInteger(0, PFX + "btnStyle2", OBJPROP_BGCOLOR, styleRt == STYLE_MULTI ? C'40,130,70' : C'60,64,80');

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
         ArrayResize(newsFileT, n + 1, 4096);
         datetime t = StringToTime(parts[0]);
         newsFileT[n++] = gmt ? NewsGmtToServer(t) : t;
      }
      FileClose(f);
      ArraySort(newsFileT);
      PrintFormat("News filter in the tester: %d events from %s (%s to %s)", n, NewsFileName(),
                  n > 0 ? TimeToString(newsFileT[0], TIME_DATE) : "-", n > 0 ? TimeToString(newsFileT[n - 1], TIME_DATE) : "-");
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
//| Mode 3: SMC (FVG + CHoCH + OB) - state machine and execution      |
//| Signal rules live in GS15_SMC.mqh; docs/SMC_RULES.md lists them.  |
//+------------------------------------------------------------------+
enum ENUM_SMC_STATE
{
   SMC_NONE = 0, SMC_DETECTED, SMC_READY, SMC_RETESTED, SMC_CONFIRMED,
   SMC_SUBMITTED, SMC_TRADED, SMC_INVALIDATED, SMC_EXPIRED
};

SmcSetup       smc;
ENUM_SMC_STATE smcState      = SMC_NONE;
string         smcId         = "";
string         smcNote       = "";        // why the setup ended, or what it waits for
datetime       smcExpiry     = 0;
int            smcRetries    = 0;
ulong          smcPosId      = 0;
bool           smcInit       = false;
datetime       smcLastH1     = 0, smcLastM15 = 0, smcLastM5 = 0;
int            smcBias       = 0;
SmcZone        smcZones[];
double         smcAtrH1      = 0, smcAtrM15 = 0;
datetime       smcLastSwingUsed[2] = {0, 0};   // [0] bull, [1] bear: one CHoCH per swing
datetime       smcLastTraded = 0;              // CHoCH time of the last traded setup (survives restarts)
string         gvSmcTraded   = "";
datetime       smcChochSeen  = 0;              // last CHoCH seen (any direction), for the console
int            smcChochSeenDir = 0;
double         smcPlanEntry = 0, smcPlanSl = 0, smcPlanTp = 0, smcPlanRR = 0, smcPlanRiskPct = 0;

string SmcStateName(ENUM_SMC_STATE s)
{
   switch(s)
   {
      case SMC_DETECTED:    return "DETECTED";
      case SMC_READY:       return "READY";
      case SMC_RETESTED:    return "RETESTED";
      case SMC_CONFIRMED:   return "CONFIRMED";
      case SMC_SUBMITTED:   return "SUBMITTED";
      case SMC_TRADED:      return "TRADED";
      case SMC_INVALIDATED: return "INVALIDATED";
      case SMC_EXPIRED:     return "EXPIRED";
   }
   return "NONE";
}

bool SmcActive()
{
   return smcState == SMC_DETECTED || smcState == SMC_READY || smcState == SMC_RETESTED || smcState == SMC_CONFIRMED;
}

string SmcDirText(int dir) { return dir > 0 ? "BUY" : "SELL"; }

//--- journal --------------------------------------------------------
string SmcJournalName()
{
   return StringFormat("GS15_smc_journal_%s_%I64u%s.csv", _Symbol, InpMagic, MQLInfoInteger(MQL_TESTER) ? "_tester" : "");
}

void SmcJournal(string evt, string reason, double entry = 0, double sl = 0, double tp = 0, double rr = 0,
                double lots = 0, double riskPct = 0, double pl = 0)
{
   int f = FileOpen(SmcJournalName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ, ',');
   if(f == INVALID_HANDLE)
      return;
   if(FileSize(f) == 0)
      FileWrite(f, "time", "event", "setup_id", "dir", "state", "reason", "ob_lo", "ob_hi", "fvg_lo", "fvg_hi",
                "entry", "sl", "tp", "rr", "lots", "risk_pct", "pl");
   FileSeek(f, 0, SEEK_END);
   FileWrite(f, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), evt, smcId, smc.dir > 0 ? "BUY" : smc.dir < 0 ? "SELL" : "",
             SmcStateName(smcState), reason, DoubleToString(smc.obLo, _Digits), DoubleToString(smc.obHi, _Digits),
             smc.hasFvg ? DoubleToString(smc.fvgLo, _Digits) : "", smc.hasFvg ? DoubleToString(smc.fvgHi, _Digits) : "",
             DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits),
             DoubleToString(rr, 2), DoubleToString(lots, 2), DoubleToString(riskPct, 3), DoubleToString(pl, 2));
   FileClose(f);
}

void SmcEnd(ENUM_SMC_STATE s, string why)
{
   smcState = s;
   smcNote  = why;
   SmcJournal(s == SMC_EXPIRED ? "EXPIRED" : "INVALIDATED", why);
   ConsoleLog("SKIP", StringFormat("SMC %s setup %s %s: %s", SmcDirText(smc.dir), smcId, s == SMC_EXPIRED ? "expired" : "cancelled", why));
}

//--- data -----------------------------------------------------------
// Closed bars only (shift 1), oldest first, with the ATR of each bar aligned.
bool SmcLoad(ENUM_TIMEFRAMES tf, int handle, int count, MqlRates &r[], double &atr[])
{
   ArraySetAsSeries(r, false);
   ArraySetAsSeries(atr, false);
   int n = CopyRates(_Symbol, tf, 1, count, r);
   if(n < 50)
      return false;
   if(CopyBuffer(handle, 0, 1, n, atr) != n)
      return false;
   return true;
}

int SmcIndexOf(const MqlRates &r[], datetime t)
{
   for(int i = ArraySize(r) - 1; i >= 0; i--)
      if(r[i].time == t) return i;
   return -1;
}

//--- time policy ----------------------------------------------------
// Minutes from now to the broker rollover (InpSmcRolloverHour, server time) and since the last one.
void SmcRolloverClock(int &toRoll, int &sinceRoll)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int now  = dt.hour * 60 + dt.min;
   int roll = InpSmcRolloverHour * 60;
   toRoll    = (roll - now + 1440) % 1440;
   sinceRoll = (now - roll + 1440) % 1440;
}

bool SmcSessionOpen()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime nowSec = (datetime)(dt.hour * 3600 + dt.min * 60 + dt.sec);
   datetime from, to;
   bool any = false;
   for(uint i = 0; SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, i, from, to); i++)
   {
      any = true;
      if(to == 0) to = 86400;
      if(nowSec >= from && nowSec < to) return true;
   }
   return !any;   // no schedule published: rely on quotes and spread checks
}

// Mode-3-only entry blocks ("" = allowed).
string SmcTimeBlock()
{
   if(!InpSmcAllowReal && AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL)
      return L("โหมด 3 ยังใช้ได้เฉพาะบัญชี Demo (InpSmcAllowReal)", "Mode 3 is demo-only until verified (InpSmcAllowReal)");
   int toRoll, sinceRoll;
   SmcRolloverClock(toRoll, sinceRoll);
   if(toRoll <= InpSmcNoEntryBeforeMin)  return L("โหมด 3: ใกล้เวลา rollover - งดเปิดไม้", "Mode 3: rollover soon - no entries");
   if(sinceRoll < InpSmcNoEntryAfterMin) return L("โหมด 3: เพิ่งผ่าน rollover - งดเปิดไม้", "Mode 3: just after rollover - no entries");
   if(!SmcSessionOpen())                 return L("โหมด 3: นอกเวลาซื้อขายของ symbol", "Mode 3: symbol session closed");
   if(!MQLInfoInteger(MQL_TESTER) && TimeCurrent() - (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME) > 120)
      return L("โหมด 3: ราคาไม่อัปเดต", "Mode 3: no fresh quotes");
   return "";
}

bool IsSmcPosition()
{
   return StringFind(PositionGetString(POSITION_COMMENT), "SMC") == 0;
}

bool IsSmcPositionId(ulong posId)
{
   if(posId == 0) return false;
   if(posId == smcPosId) return true;
   if(!HistorySelectByPosition(posId)) return false;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d > 0 && HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
         return StringFind(HistoryDealGetString(d, DEAL_COMMENT), "SMC") == 0;
   }
   return false;
}

// Every tick, in every mode: mode-3 trades never stay through the rollover.
void SmcManagePositions()
{
   int toRoll, sinceRoll;
   SmcRolloverClock(toRoll, sinceRoll);
   if(toRoll > InpSmcCloseBeforeMin)
      return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && IsMine() && IsSmcPosition())
         ClosePosition(t, L("โหมด 3 ปิดก่อน rollover", "mode 3 close before rollover"));
   }
}

//--- engine updates -------------------------------------------------
void SmcUpdateH1()
{
   MqlRates r[]; double a[];
   if(!SmcLoad(InpSmcTfBias, hSmcAtrBias, InpSmcSRLookback + InpSmcPivotLeft + InpSmcPivotRight + 5, r, a))
      return;
   int n = ArraySize(r);
   SmcSwing s[];
   SmcCollectSwings(r, n - 1, InpSmcPivotLeft, InpSmcPivotRight, PeriodSeconds(InpSmcTfBias), s);
   int prevBias = smcBias;
   smcBias  = SmcBias(s);
   smcAtrH1 = a[n - 1];
   SmcBuildZones(s, InpSmcSRTolAtr * smcAtrH1, smcZones);
   if(InpSmcBiasFilter && SmcActive() && smcBias != smc.dir && prevBias != smcBias)
      SmcEnd(SMC_INVALIDATED, smcBias == 0 ? "H1 bias became neutral" : "H1 bias flipped");
}

void SmcUpdateStructure()
{
   MqlRates r[]; double a[];
   if(!SmcLoad(InpSmcTfStructure, hSmcAtrStruct, InpSmcLookbackBars, r, a))
      return;
   int n = ArraySize(r), m = n - 1;
   int per = PeriodSeconds(InpSmcTfStructure);
   smcAtrM15 = a[m];

   // 1) Existing setup: re-locate it in the new arrays, then FVG / invalidation / expiry.
   if(SmcActive())
   {
      int k = SmcIndexOf(r, smc.chochTime), ob = SmcIndexOf(r, smc.obTime);
      if(k < 0 || ob < 0)
         SmcEnd(SMC_EXPIRED, "setup bars left the lookback");
      else
      {
         int shift = k - smc.breakIdx;
         smc.breakIdx = k; smc.obIdx = ob; smc.impulseStart += shift;
         if(smc.hasFvg) smc.fvgC += shift;
         if(smcState == SMC_DETECTED)
         {
            SmcRefreshFvg(r, a, m, InpSmcFvgWindow, InpSmcFvgMinAtr, per, smc);
            if(smc.hasFvg)
               SmcMakeReady();
            else if(m >= k + InpSmcFvgWindow)
               SmcEnd(SMC_INVALIDATED, StringFormat("no FVG within %d bars of the CHoCH", InpSmcFvgWindow));
         }
         if(SmcActive() && smcState != SMC_DETECTED)
         {
            if(smc.dir > 0 && r[m].close < smc.obLo)      SmcEnd(SMC_INVALIDATED, "M15 closed below the order block");
            else if(smc.dir < 0 && r[m].close > smc.obHi) SmcEnd(SMC_INVALIDATED, "M15 closed above the order block");
            else if(TimeCurrent() >= smcExpiry)           SmcEnd(SMC_EXPIRED, StringFormat("no entry within %d M15 bars", InpSmcExpiryBars));
         }
      }
   }

   // 2) New CHoCH on the bar that just closed.
   SmcSwing lvl;
   int dir = SmcChochAt(r, a, m, InpSmcPivotLeft, InpSmcPivotRight, per, InpSmcBreakBufAtr, lvl);
   if(dir == 0)
      return;
   smcChochSeen = r[m].time; smcChochSeenDir = dir;
   int slot = dir > 0 ? 0 : 1;
   if(lvl.time == smcLastSwingUsed[slot])
      return;
   smcLastSwingUsed[slot] = lvl.time;
   if(SmcActive() && smc.dir != dir)
      SmcEnd(SMC_INVALIDATED, "opposite CHoCH");
   string tag = StringFormat("%s %s CHoCH %s", _Symbol, dir > 0 ? "bullish" : "bearish", TimeToString(r[m].time, TIME_DATE | TIME_MINUTES));
   if(InpSmcBiasFilter && smcBias != dir)
   {
      ConsoleLog("SKIP", tag + StringFormat(" ignored: H1 bias is %s", smcBias > 0 ? "bullish" : smcBias < 0 ? "bearish" : "neutral"));
      return;
   }
   if(r[m].time <= smcLastTraded)
      return;   // already traded before a restart
   SmcSetup st;
   ZeroMemory(st);
   if(!SmcBuildSetup(r, a, m, dir, lvl, per, InpSmcObMaxBack, InpSmcDispAtr, InpSmcFvgWindow, m, InpSmcFvgMinAtr, st))
   {
      ConsoleLog("SKIP", tag + StringFormat(" ignored: no displacement (body >= %.1f ATR) or no order block within %d bars", InpSmcDispAtr, InpSmcObMaxBack));
      return;
   }
   if(SmcActive())
      SmcEnd(SMC_INVALIDATED, "replaced by a newer CHoCH");
   smc = st;
   smcId = StringFormat("%s-%s-%s-%s", _Symbol, StringSubstr(EnumToString(InpSmcTfStructure), 7), dir > 0 ? "B" : "S",
                        TimeToString(st.chochTime, TIME_DATE | TIME_MINUTES));
   StringReplace(smcId, ".", ""); StringReplace(smcId, ":", ""); StringReplace(smcId, " ", "T");
   smcState = SMC_DETECTED;
   smcRetries = 0;
   smcPlanEntry = smcPlanSl = smcPlanTp = smcPlanRR = smcPlanRiskPct = 0;
   SmcJournal("DETECTED", StringFormat("CHoCH through %s, OB %s", DoubleToString(st.chochLevel, _Digits), TimeToString(st.obTime, TIME_DATE | TIME_MINUTES)));
   ConsoleLog("INFO", StringFormat("SMC %s setup %s: CHoCH through %s, OB %s-%s", SmcDirText(dir), smcId,
                                   DoubleToString(st.chochLevel, _Digits), DoubleToString(st.obLo, _Digits), DoubleToString(st.obHi, _Digits)));
   if(smc.hasFvg)
      SmcMakeReady();
   else
      smcNote = "waiting for an FVG";
}

void SmcMakeReady()
{
   double zlo, zhi;
   if(!SmcEntryZone(smc, InpSmcRequireOverlap, zlo, zhi))
   {
      SmcEnd(SMC_INVALIDATED, "OB and FVG do not overlap (InpSmcRequireOverlap)");
      return;
   }
   smcState  = SMC_READY;
   smcExpiry = smc.readyTime + InpSmcExpiryBars * PeriodSeconds(InpSmcTfStructure);
   smcNote   = "waiting for price to return to the zone";
   SmcJournal("READY", StringFormat("FVG %s-%s, zone %s-%s", DoubleToString(smc.fvgLo, _Digits), DoubleToString(smc.fvgHi, _Digits),
                                    DoubleToString(zlo, _Digits), DoubleToString(zhi, _Digits)));
   ConsoleLog("INFO", StringFormat("SMC %s setup %s ready: zone %s-%s, FVG %s-%s, expires %s", SmcDirText(smc.dir), smcId,
                                   DoubleToString(zlo, _Digits), DoubleToString(zhi, _Digits), DoubleToString(smc.fvgLo, _Digits),
                                   DoubleToString(smc.fvgHi, _Digits), TimeToString(smcExpiry, TIME_DATE | TIME_MINUTES)));
}

void SmcUpdateEntryBar()
{
   if(smcState != SMC_READY && smcState != SMC_RETESTED)
      return;
   MqlRates b[];
   ArraySetAsSeries(b, true);
   if(CopyRates(_Symbol, InpSmcTfEntry, 1, 1, b) != 1)
      return;
   if(b[0].time < smc.readyTime)
      return;   // only price action after the setup was complete counts
   double zlo, zhi;
   SmcEntryZone(smc, InpSmcRequireOverlap, zlo, zhi);
   if(smcState == SMC_READY && SmcTouches(b[0], zlo, zhi))
   {
      smcState = SMC_RETESTED;
      smcNote  = "zone touched - waiting for a confirmation candle";
   }
   if(SmcConfirmCandle(b[0], smc.dir, zlo, zhi))
   {
      smcState = SMC_CONFIRMED;
      smcNote  = StringFormat("confirmed by the %s candle of %s", StringSubstr(EnumToString(InpSmcTfEntry), 7), TimeToString(b[0].time, TIME_MINUTES));
      SmcJournal("CONFIRMED", smcNote);
   }
}

// Called every tick in mode 3.
void SmcOnTick()
{
   datetime h1  = iTime(_Symbol, InpSmcTfBias, 0);
   datetime m15 = iTime(_Symbol, InpSmcTfStructure, 0);
   datetime m5  = iTime(_Symbol, InpSmcTfEntry, 0);
   if(h1 == 0 || m15 == 0 || m5 == 0)
      return;
   if(!smcInit)
   {
      smcInit = true;
      SmcUpdateH1();
      smcLastH1 = h1;
   }
   if(h1 != smcLastH1)   { smcLastH1 = h1;   SmcUpdateH1(); }
   if(m15 != smcLastM15) { smcLastM15 = m15; SmcUpdateStructure(); SmcDraw(); }
   if(m5 != smcLastM5)   { smcLastM5 = m5;   SmcUpdateEntryBar(); }
   if(smcState == SMC_CONFIRMED)
      SmcTryEnter();
}

//--- entry ----------------------------------------------------------
void SmcSkip(string why)
{
   SmcEnd(SMC_INVALIDATED, why);
   Notify(StringFormat(L("ข้าม SMC %s (%s): %s", "Skipped SMC %s (%s): %s"), SmcDirText(smc.dir), smcId, why), "SKIP");
}

void SmcTryEnter()
{
   if(CountPositions() > 0) { SmcSkip("a position of this EA is already open"); return; }
   int    tradesToday; double profitToday;
   GetTodayStats(tradesToday, profitToday);
   string block = BlockReason(tradesToday, profitToday);
   if(block != "") { SmcSkip("blocked: " + block); return; }

   bool   isBuy = smc.dir > 0;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) { SmcSkip("no quotes"); return; }
   double entry = isBuy ? ask : bid;
   double atr   = smcAtrM15;
   double sl    = isBuy ? MathMin(smc.obLo, smc.structLo) - InpSmcSlBufAtr * atr
                        : MathMax(smc.obHi, smc.structHi) + InpSmcSlBufAtr * atr;
   SmcZone z;
   bool haveTarget = isBuy ? SmcNearestResistance(smcZones, entry, z) : SmcNearestSupport(smcZones, entry, z);
   if(!haveTarget) { SmcSkip(isBuy ? "no confirmed H1 resistance above price for a target" : "no confirmed H1 support below price for a target"); return; }
   double tp = isBuy ? z.lo - InpSmcTpBufAtr * atr : z.hi + InpSmcTpBufAtr * atr;
   sl = NormPrice(sl); tp = NormPrice(tp);
   if(isBuy ? (sl >= entry || tp <= entry) : (sl <= entry || tp >= entry))
   { SmcSkip(StringFormat("target zone %s-%s is at or behind the entry - no room", DoubleToString(z.lo, _Digits), DoubleToString(z.hi, _Digits))); return; }

   // Money per 1 lot from the server's own calculation, plus slippage allowance and commission.
   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double lossLot = 0, gainLot = 0, slipLot = 0;
   if(!OrderCalcProfit(type, _Symbol, 1.0, entry, sl, lossLot) || !OrderCalcProfit(type, _Symbol, 1.0, entry, tp, gainLot))
   { SmcSkip("OrderCalcProfit failed"); return; }
   slipLot = LossPerLot(InpSlippagePts * _Point);
   double riskLot   = MathAbs(lossLot) + slipLot + InpCommissionLot;
   double rewardLot = gainLot - InpCommissionLot;
   double rr = riskLot > 0 ? rewardLot / riskLot : 0;
   smcPlanEntry = entry; smcPlanSl = sl; smcPlanTp = tp; smcPlanRR = rr;
   if(rr < InpSmcMinRR)
   { SmcSkip(StringFormat("RR %.2f < %.2f after costs (target %s, stop %s)", rr, InpSmcMinRR, DoubleToString(tp, _Digits), DoubleToString(sl, _Digits))); return; }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lots = NormalizeLots(equity * RiskPctEff() / 100.0 / riskLot);
   double cap = MaxLotCap(entry);
   if(cap > 0 && lots > cap) lots = NormalizeLots(cap);
   double riskMoney = riskLot * lots;
   smcPlanRiskPct = equity > 0 ? riskMoney / equity * 100.0 : 0;
   if(riskMoney > equity * RiskPctEff() / 100.0 * 1.0001)
   { SmcSkip(StringFormat("min lot %.2f would risk %.2f (%.2f%%) > %.2f%% target", lots, riskMoney, smcPlanRiskPct, RiskPctEff())); return; }
   if(InpMaxDailyLossPct > 0)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double budget  = (balance - profitToday) * InpMaxDailyLossPct / 100.0 - MathMax(0.0, -profitToday);
      if(riskMoney > budget)
      { SmcSkip(StringFormat("daily loss budget left %.2f < risk %.2f", MathMax(0.0, budget), riskMoney)); return; }
   }
   // Broker constraints.
   long   mode   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED || mode == SYMBOL_TRADE_MODE_CLOSEONLY ||
      (isBuy && mode == SYMBOL_TRADE_MODE_SHORTONLY) || (!isBuy && mode == SYMBOL_TRADE_MODE_LONGONLY))
   { SmcSkip("symbol trade mode does not allow this order"); return; }
   double minStop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double exitPx  = isBuy ? bid : ask;
   if(MathAbs(exitPx - sl) < minStop || MathAbs(tp - exitPx) < minStop)
   { SmcSkip("SL or TP closer than the broker stops level"); return; }

   MqlTradeRequest req; MqlTradeCheckResult chk;
   ZeroMemory(req); ZeroMemory(chk);
   req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol; req.volume = lots; req.type = type;
   req.price = entry; req.sl = sl; req.tp = tp; req.deviation = 30; req.magic = InpMagic;
   long fm = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   req.type_filling = (fm & SYMBOL_FILLING_FOK) != 0 ? ORDER_FILLING_FOK : (fm & SYMBOL_FILLING_IOC) != 0 ? ORDER_FILLING_IOC : ORDER_FILLING_RETURN;
   if(!OrderCheck(req, chk) || (chk.retcode != 0 && chk.retcode != TRADE_RETCODE_DONE))
   { SmcSkip(StringFormat("OrderCheck: %d %s", chk.retcode, chk.comment)); return; }
   if(!AcquireOrderLock()) return;   // another chart is sending right now: try again next tick

   smcState = SMC_SUBMITTED;
   string comment = "SMC " + StringSubstr(smcId, StringLen(_Symbol) + 1);
   bool ok = isBuy ? trade.Buy(lots, _Symbol, entry, sl, tp, comment) : trade.Sell(lots, _Symbol, entry, sl, tp, comment);
   uint rc = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED) && trade.ResultDeal() > 0)
   {
      smcState = SMC_TRADED;
      if(HistoryDealSelect(trade.ResultDeal()))
         smcPosId = (ulong)HistoryDealGetInteger(trade.ResultDeal(), DEAL_POSITION_ID);
      smcLastTraded = smc.chochTime;
      if(!MQLInfoInteger(MQL_TESTER))
         GlobalVariableSet(gvSmcTraded, (double)smcLastTraded);
      double fill = trade.ResultPrice() > 0 ? trade.ResultPrice() : entry;
      smcNote = "traded";
      SmcJournal("OPEN", smcNote, fill, sl, tp, rr, lots, smcPlanRiskPct);
      string msg = StringFormat(L("เปิด %s %.2f lot @ %s (โหมด 3 SMC %s) | SL %s | TP %s | RR %.2f | เสี่ยง %.2f %s (%.2f%%)",
                                  "Opened %s %.2f lot @ %s (mode 3 SMC %s) | SL %s | TP %s | RR %.2f | risk %.2f %s (%.2f%%)"),
                                SmcDirText(smc.dir), lots, DoubleToString(fill, _Digits), smcId, DoubleToString(sl, _Digits),
                                DoubleToString(tp, _Digits), rr, riskMoney, AccountInfoString(ACCOUNT_CURRENCY), smcPlanRiskPct);
      if(InpNotifyTrades) Notify(msg, "OPEN"); else ConsoleLog("OPEN", msg);
      return;
   }
   if((rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED || rc == TRADE_RETCODE_PRICE_OFF) && smcRetries < 2)
   {
      smcRetries++;
      smcState = SMC_CONFIRMED;   // re-evaluated (price, RR, risk) on the next tick
      Print(StringFormat("SMC order %s: %d %s - retry %d at the next tick", smcId, rc, trade.ResultRetcodeDescription(), smcRetries));
      return;
   }
   SmcSkip(StringFormat("order rejected: %d %s", rc, trade.ResultRetcodeDescription()));
}

//--- chart drawing (live, or visual tester) ------------------------
void SmcRect(string name, datetime t1, double p1, datetime t2, double p2, color c)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
}

void SmcDraw()
{
   if(!InpSmcDraw || (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)))
      return;
   datetime now = TimeCurrent(), end = now + 6 * PeriodSeconds(InpSmcTfStructure);
   ObjectsDeleteAll(0, PFX + "smc_");
   // Nearest H1 zones around price (these are rule-based levels, not guaranteed reactions).
   double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   SmcZone z;
   if(SmcNearestResistance(smcZones, px, z)) SmcRect(PFX + "smc_res", now - 48 * 3600, z.lo, end, z.hi + _Point, C'90,40,50');
   if(SmcNearestSupport(smcZones, px, z))    SmcRect(PFX + "smc_sup", now - 48 * 3600, z.lo - _Point, end, z.hi, C'30,70,60');
   if(smcState == SMC_NONE || smc.dir == 0 || (!SmcActive() && smcState != SMC_TRADED))
      return;
   SmcRect(PFX + "smc_ob", smc.obTime, smc.obLo, end, smc.obHi, smc.dir > 0 ? C'28,60,120' : C'110,40,60');
   if(smc.hasFvg)
      SmcRect(PFX + "smc_fvg", smc.fvgTime, smc.fvgLo, end, smc.fvgHi, C'40,60,90');
   string ln = PFX + "smc_choch";
   ObjectCreate(0, ln, OBJ_TREND, 0, smc.chochSwingTime, smc.chochLevel, smc.chochTime, smc.chochLevel);
   ObjectSetInteger(0, ln, OBJPROP_COLOR, C'121,173,255');
   ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);
   ObjectSetString(0, ln, OBJPROP_TEXT, "CHoCH " + SmcDirText(smc.dir));
}

//--- console status --------------------------------------------------
// What the current setup still needs, in plain words.
string SmcMissing()
{
   if(InpSmcBiasFilter && smcBias == 0) return "H1 bias is neutral - waiting for HH+HL or LH+LL";
   if(!SmcActive() && smcState != SMC_SUBMITTED) return StringFormat("waiting for a %s CHoCH on %s",
                                      smcBias > 0 ? "bullish" : smcBias < 0 ? "bearish" : "", StringSubstr(EnumToString(InpSmcTfStructure), 7));
   return smcNote;
}

void SmcWriteStatus(int f)
{
   SmcZone z;
   double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string sup = SmcNearestSupport(smcZones, px, z) ? DoubleToString(z.lo, _Digits) + "-" + DoubleToString(z.hi, _Digits) : "-";
   string res = SmcNearestResistance(smcZones, px, z) ? DoubleToString(z.lo, _Digits) + "-" + DoubleToString(z.hi, _Digits) : "-";
   FileWriteString(f, "smc_bias=" + (smcBias > 0 ? "BULLISH" : smcBias < 0 ? "BEARISH" : "NEUTRAL") + "\r\n");
   FileWriteString(f, "smc_support=" + sup + "\r\nsmc_resistance=" + res + "\r\n");
   FileWriteString(f, "smc_choch=" + (smcChochSeen > 0 ? (smcChochSeenDir > 0 ? "BULLISH " : "BEARISH ") + TimeToString(smcChochSeen, TIME_DATE | TIME_MINUTES) : "-") + "\r\n");
   FileWriteString(f, "smc_setup=" + (smcId != "" ? smcId : "-") + "\r\nsmc_state=" + SmcStateName(smcState) + "\r\n");
   FileWriteString(f, "smc_ob=" + (smcId != "" ? DoubleToString(smc.obLo, _Digits) + "-" + DoubleToString(smc.obHi, _Digits) : "-") + "\r\n");
   FileWriteString(f, "smc_fvg=" + (smc.hasFvg ? DoubleToString(smc.fvgLo, _Digits) + "-" + DoubleToString(smc.fvgHi, _Digits) : "-") + "\r\n");
   int left = SmcActive() && smcExpiry > 0 ? (int)MathMax(0, (smcExpiry - TimeCurrent()) / PeriodSeconds(InpSmcTfStructure)) : -1;
   FileWriteString(f, StringFormat("smc_expiry_bars=%d\r\n", left));
   FileWriteString(f, "smc_missing=" + SmcMissing() + "\r\n");
   FileWriteString(f, StringFormat("smc_plan=%s\r\n", smcPlanEntry > 0 ? StringFormat("entry %s | SL %s | TP %s | RR %.2f | risk %.2f%%",
                   DoubleToString(smcPlanEntry, _Digits), DoubleToString(smcPlanSl, _Digits), DoubleToString(smcPlanTp, _Digits), smcPlanRR, smcPlanRiskPct) : "-"));
}

// On start: last traded setup from the global variable and from the deal history (reconcile).
void SmcRestore()
{
   gvSmcTraded = PFX + "smcTraded_" + _Symbol + "_" + (string)InpMagic;
   if(MQLInfoInteger(MQL_TESTER))
      return;
   if(GlobalVariableCheck(gvSmcTraded))
      smcLastTraded = (datetime)(long)GlobalVariableGet(gvSmcTraded);
   if(HistorySelect(TimeCurrent() - 14 * 86400, TimeCurrent() + 60))
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN || (ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic)
            continue;
         if(StringFind(HistoryDealGetString(d, DEAL_COMMENT), "SMC") == 0)
         {
            datetime t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            // the setup's CHoCH happened before the entry: everything up to the entry is consumed
            if(t > smcLastTraded) smcLastTraded = t;
         }
      }
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
      // No one can press Resume in a backtest: count it, reset and carry on.
      testerHalts[code]++;
      Print("Risk guard would halt here: ", why);
      ResetGuards();
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
   haltCode   = 0;
   if(!MQLInfoInteger(MQL_TESTER))
   {
      GlobalVariableSet(gvPeak, equityPeak);
      GlobalVariableSet(gvStreak, 0);
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
//| Trade mode: 1 = one bigger trade a day, 2 = several smaller ones |
//+------------------------------------------------------------------+
int MaxTradesEff()
{
   return styleRt == STYLE_ONE ? InpMaxTradesPerDay : 0;   // modes 2 and 3: no daily count (one position at a time)
}

double RiskPctEff()
{
   if(styleRt == STYLE_SMC)   return InpSmcRiskPct;
   if(styleRt == STYLE_MULTI) return InpMultiRiskPct;
   return riskPctRt;
}

void SaveStyle()
{
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableSet(gvStyle, (double)styleRt);
   GlobalVariableSet(gvStyleIn, (double)InpTradeStyle);
}

string StyleLine()
{
   string size = lotModeRt == LOT_FIXED ? StringFormat("%.2f lot", InpLots)
                                        : StringFormat(L("เสี่ยง %.1f%%", "risk %.1f%%"), RiskPctEff());
   if(styleRt == STYLE_SMC)
      return StringFormat(L("โหมด 3: SMC (FVG+CHoCH+OB) | %s", "Mode 3: SMC (FVG+CHoCH+OB) | %s"), size);
   return styleRt == STYLE_MULTI ? StringFormat(L("โหมด 2: หลายไม้ ไม้เล็ก | %s", "Mode 2: several small | %s"), size)
                                 : StringFormat(L("โหมด 1: ไม้ใหญ่ วันละ 1 | %s", "Mode 1: one big a day | %s"), size);
}

// Lots each mode would trade right now (for the comparison in the popup).
double LotsForRisk(double pct, double slDist)
{
   if(lotModeRt == LOT_FIXED)
      return NormalizeLots(InpLots);
   double perLot = RiskPerLot(slDist);
   if(perLot <= 0)
      return 0;
   return NormalizeLots(AccountInfoDouble(ACCOUNT_EQUITY) * pct / 100.0 / perLot);
}

// Text describing both modes, with the tested results and today's lot size.
string StyleDetails()
{
   double one = riskPctRt, multi = InpMultiRiskPct;
   string m = L("โหมด 1: ไม้ใหญ่ วันละ 1 ไม้\n", "Mode 1: one bigger trade a day\n");
   m += StringFormat(L(" - เข้าเฉพาะการเบรกกรอบครั้งแรกของวัน เสี่ยง %.1f%% ต่อไม้\n",
                       " - Only the first range breakout of the day, %.1f%% risk per trade\n"), one);
   m += L(" - ผลทดสอบ 2018-2026 (ทุน $3,000 เสี่ยง 1%): กำไร +105%, PF 1.46, DD สูงสุด 16.3%\n",
          " - Tested 2018-2026 ($3,000, 1% risk): +105%, PF 1.46, max DD 16.3%\n");
   m += L(" - เหมาะกับ: คนที่อยากได้กำไรสูงสุด รับพอร์ตลดลงระหว่างทางได้ 15-20%\n\n",
          " - For: maximum profit, accepting 15-20% drawdowns\n\n");
   m += L("โหมด 2: ค่อยๆ ออกหลายไม้ (ไม้เล็ก)\n", "Mode 2: several smaller trades\n");
   m += StringFormat(L(" - เข้าทุกครั้งที่เข้าเงื่อนไข ไม่จำกัดไม้ต่อวัน เสี่ยง %.1f%% ต่อไม้ (พัก 20 นาทีหลังแพ้)\n",
                       " - Every breakout that meets the rules, no daily limit, %.1f%% risk per trade (20-min pause after a loss)\n"), multi);
   m += L(" - ผลทดสอบ 2018-2026 (ทุน $3,000 เสี่ยง 0.5%): กำไร +74%, PF 1.46, DD สูงสุด 10.5%\n",
          " - Tested 2018-2026 ($3,000, 0.5% risk): +74%, PF 1.46, max DD 10.5%\n");
   m += L(" - เหมาะกับ: คนที่อยากให้พอร์ตนิ่ง ยอมกำไรน้อยลง\n\n",
          " - For: a steadier account, with less profit\n\n");
   m += L("หมายเหตุ: ไม้ที่ 2-3 ของวันแพ้บ่อยกว่าไม้แรก ความนิ่งของโหมด 2 มาจากไม้ที่เล็กกว่า\n",
          "Note: the 2nd-3rd trades of a day lose more often; mode 2 is steadier because each trade is smaller\n");

   double atr[];
   if(GetBuf(hATR, atr) && atr[0] > 0)
   {
      double slDist = MathMax(atr[0] * InpSL_ATR, MinStopDistance());
      double l1 = LotsForRisk(one, slDist), l2 = LotsForRisk(multi, slDist);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      m += StringFormat(L("วันนี้ด้วยทุนนี้: โหมด 1 = %.2f lot, โหมด 2 = %.2f lot\n", "Today with this balance: mode 1 = %.2f lot, mode 2 = %.2f lot\n"), l1, l2);
      if(lotModeRt != LOT_FIXED && l1 <= minLot && l2 <= minLot)
         m += L("(ทุนยังน้อย ทั้งสองโหมดใช้ Lot ขั้นต่ำเท่ากัน - โหมด 2 จะไม่ได้ไม้เล็กลง)\n",
                "(Small balance: both modes use the minimum lot - mode 2 will not trade smaller)\n");
   }
   return m;
}

// Panel button: show both modes, then confirm the switch.
void ChooseStyle(ENUM_TRADE_STYLE target)
{
   string title = "GoldScalperM15 - " + L("เลือกโหมดเทรด", "Trade mode");
   string m = StyleDetails() + "\n";
   string cur = styleRt == STYLE_MULTI ? "2" : "1";
   if(target == styleRt)
   {
      m += StringFormat(L("ตอนนี้ใช้โหมด %s อยู่แล้ว", "Mode %s is already active"), cur);
      MessageBox(m, title, MB_OK | MB_ICONINFORMATION);
      return;
   }
   string tgt = target == STYLE_MULTI ? "2" : "1";
   m += StringFormat(L("ตอนนี้ใช้โหมด %s - เปลี่ยนเป็นโหมด %s ไหม?\n(ไม้ที่ถืออยู่ไม่ถูกปิด มีผลกับไม้ถัดไป)",
                       "Now using mode %s - switch to mode %s?\n(Open trades stay open; applies to the next trade)"), cur, tgt);
   if(MessageBox(m, title, MB_YESNO | MB_ICONQUESTION) != IDYES)
      return;
   styleRt = target;
   SaveStyle();
   Notify(StringFormat(L("เปลี่ยนเป็นโหมด %s แล้ว: %s", "Switched to mode %s: %s"), tgt, StyleLine()));
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
      Print("==== ", L("โหมดเทรดตอนนี้: ", "Current trade mode: "), StyleLine(), " ====");
      string sl[];
      int ns = StringSplit(StyleDetails(), '\n', sl);
      for(int i = 0; i < ns; i++)
         if(sl[i] != "")
            Print(sl[i]);
      Print(L("(เปลี่ยนโหมดได้ที่ปุ่ม \"โหมด 1\" / \"โหมด 2\" บนแผง)", "(Switch with the \"Mode 1\" / \"Mode 2\" panel buttons)"));
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
            FileWriteString(f, "\r\n" + L("โหมดเทรดตอนนี้: ", "Current trade mode: ") + StyleLine() + "\r\n");
            for(int i = 0; i < ns; i++)
               if(sl[i] != "")
                  FileWriteString(f, sl[i] + "\r\n");
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