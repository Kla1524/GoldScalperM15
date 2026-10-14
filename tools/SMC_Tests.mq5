//+------------------------------------------------------------------+
//| SMC_Tests.mq5 - unit tests for GS15_SMC.mqh on synthetic bars.    |
//| Run as a script (needs no account or market data). Results go to |
//| the Experts log and Common\Files\GS15_smc_tests.txt.             |
//| Copy GS15_SMC.mqh next to this file before compiling.            |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "GS15_SMC.mqh"

int pass = 0, fail = 0;
string report = "";

void Check(bool ok, string name)
{
   if(ok) pass++; else fail++;
   string line = (ok ? "PASS  " : "FAIL  ") + name;
   Print(line);
   report += line + "\r\n";
}

void Bar(MqlRates &r[], int i, double o, double h, double l, double c)
{
   r[i].time = D'2026.01.05 00:00' + i * 900;
   r[i].open = o; r[i].high = h; r[i].low = l; r[i].close = c;
}

// Bearish structure (SH 110 > SH 106, SL 100 > SL 96), then an impulse that closes above 106.
void BearToBullCase(MqlRates &r[])
{
   ArrayResize(r, 15);
   Bar(r, 0, 105, 106, 104, 105);
   Bar(r, 1, 105, 108, 104, 107);
   Bar(r, 2, 107, 110, 106, 108);    // swing high 110
   Bar(r, 3, 108, 109, 103, 104);
   Bar(r, 4, 104, 105, 101, 102);
   Bar(r, 5, 102, 103, 100, 101);    // swing low 100
   Bar(r, 6, 101, 104, 100.5, 103);
   Bar(r, 7, 103, 106, 102, 105);    // swing high 106 (lower high)
   Bar(r, 8, 105, 105.5, 98, 99);
   Bar(r, 9, 99, 100, 96, 97);       // swing low 96 (lower low)
   Bar(r, 10, 97, 99, 96.5, 98.5);
   Bar(r, 11, 98.5, 99, 97, 97.5);   // last bearish candle before the impulse = OB
   Bar(r, 12, 97.5, 103, 97.4, 102.8); // displacement
   Bar(r, 13, 102.8, 108.5, 102.5, 108); // closes above 106: bullish CHoCH
   Bar(r, 14, 108, 109.5, 107.5, 109);   // still above: must NOT be a second CHoCH
}

// Mirror image (price -> 200 - price): turns the bullish case into a bearish one.
void Mirror(const MqlRates &a[], MqlRates &b[])
{
   int n = ArraySize(a);
   ArrayResize(b, n);
   for(int i = 0; i < n; i++)
   {
      b[i].time = a[i].time;
      b[i].open = 200 - a[i].open; b[i].close = 200 - a[i].close;
      b[i].high = 200 - a[i].low;  b[i].low   = 200 - a[i].high;
   }
}

void Atr(double &atr[], int n, double v) { ArrayResize(atr, n); for(int i = 0; i < n; i++) atr[i] = v; }

void OnStart()
{
   MqlRates r[], m[];
   double atr[];
   BearToBullCase(r);
   Atr(atr, ArraySize(r), 1.0);
   int per = 900;

   //--- swings and confirmation delay
   SmcSwing s[];
   SmcCollectSwings(r, 10, 2, 2, per, s);
   bool has9 = false; for(int i = 0; i < ArraySize(s); i++) if(s[i].idx == 9) has9 = true;
   Check(!has9, "swing low at bar 9 is NOT known when bar 10 closes (needs 2 bars to the right)");
   SmcCollectSwings(r, 11, 2, 2, per, s);
   has9 = false; datetime ct = 0;
   for(int i = 0; i < ArraySize(s); i++) if(s[i].idx == 9) { has9 = true; ct = s[i].confirmTime; }
   Check(has9, "swing low at bar 9 is known once bar 11 has closed");
   Check(ct == r[11].time + per, "confirmation time = close of bar 11");
   Check(ArraySize(s) == 4, StringFormat("4 confirmed swings in the case (got %d)", ArraySize(s)));
   Check(SmcBias(s) == -1, "lower highs + lower lows -> bearish bias");

   //--- equal highs: only the earliest is a pivot
   MqlRates t[];
   ArrayResize(t, 6);
   Bar(t, 0, 1, 1, 0, 1); Bar(t, 1, 1, 2, 0, 1); Bar(t, 2, 1, 5, 0, 1);
   Bar(t, 3, 1, 5, 0, 1); Bar(t, 4, 1, 2, 0, 1); Bar(t, 5, 1, 1, 0, 1);
   Check(SmcIsSwingHigh(t, 2, 2, 2) && !SmcIsSwingHigh(t, 3, 2, 2), "equal highs: the earlier bar is the pivot, the later is not");

   //--- bias neutral when mixed
   SmcSwing mix[];
   ArrayResize(mix, 4);
   mix[0].type = 1; mix[0].price = 110; mix[1].type = -1; mix[1].price = 100;
   mix[2].type = 1; mix[2].price = 112; mix[3].type = -1; mix[3].price = 98;
   Check(SmcBias(mix) == 0, "higher high + lower low -> neutral");

   //--- zones
   SmcZone z[], zz;
   SmcCollectSwings(r, 12, 2, 2, per, s);
   Check(SmcBuildZones(s, 0.5, z) == 4, "tolerance 0.5: four separate levels");
   SmcBuildZones(s, 5.0, z);
   Check(ArraySize(z) == 2 && z[0].lo == 96 && z[0].hi == 100 && z[1].lo == 106 && z[1].hi == 110, "tolerance 5: zones 96-100 and 106-110");
   Check(SmcNearestResistance(z, 102, zz) && zz.lo == 106, "nearest resistance above 102 is 106-110");
   Check(SmcNearestSupport(z, 102, zz) && zz.hi == 100, "nearest support below 102 is 96-100");
   Check(SmcNearestResistance(z, 107, zz) && zz.lo == 106, "price inside a zone: that zone is the resistance (no room)");

   //--- CHoCH
   SmcSwing lvl;
   Check(SmcChochAt(r, atr, 12, 2, 2, per, 0.1, lvl) == 0, "bar 12 (close 102.8 below 106) is not a CHoCH");
   Check(SmcChochAt(r, atr, 13, 2, 2, per, 0.1, lvl) == 1 && lvl.price == 106, "bar 13 closes above lower high 106: bullish CHoCH");
   Check(SmcChochAt(r, atr, 14, 2, 2, per, 0.1, lvl) == 0, "bar 14 still above the level: no repeated CHoCH");
   Check(SmcChochAt(r, atr, 13, 2, 2, per, 2.5, lvl) == 0, "break buffer 2.5 ATR (needs > 108.5): no CHoCH");
   MqlRates bos[];
   ArrayCopy(bos, r);
   Bar(bos, 13, 97, 97.5, 94, 94.5);
   Check(SmcChochAt(bos, atr, 13, 2, 2, per, 0.1, lvl) == 0, "close below 96 in a bearish structure is a BOS, not a CHoCH");
   MqlRates wick[];
   ArrayCopy(wick, r);
   Bar(wick, 13, 102.8, 108.5, 102.5, 105.5);
   Check(SmcChochAt(wick, atr, 13, 2, 2, per, 0.1, lvl) == 0, "wick above 106 but close 105.5: no CHoCH");

   //--- order block, displacement, FVG
   int imp, ob;
   Check(SmcFindOrderBlock(r, atr, 13, 1, 10, 1.0, imp, ob) && ob == 11 && imp == 12, "OB = bar 11 (last bearish before the impulse 12-13)");
   double big[];
   Atr(big, ArraySize(r), 10.0);
   Check(!SmcFindOrderBlock(r, big, 13, 1, 10, 1.0, imp, ob), "no candle body >= 1 ATR (ATR 10): no displacement, no setup");
   Check(!SmcFindOrderBlock(r, atr, 13, 1, 1, 1.0, imp, ob), "OB further back than the limit (max 1 bar): no setup");
   int c; double lo, hi;
   Check(SmcFindFvg(r, atr, 11, 12, 13, 3, 13, 1, 0.1, c, lo, hi) && c == 13 && lo == 99 && hi == 102.5, "bullish FVG: High(A=11) 99 to Low(C=13) 102.5");
   Check(!SmcFindFvg(r, atr, 11, 12, 13, 3, 12, 1, 0.1, c, lo, hi), "no look-ahead: FVG needs bar 13, not found when only bar 12 has closed");
   Check(!SmcFindFvg(r, atr, 11, 12, 13, 3, 13, 1, 4.0, c, lo, hi), "FVG width 3.5 < 4 ATR minimum: rejected");

   SmcSetup st;
   SmcChochAt(r, atr, 13, 2, 2, per, 0.1, lvl);
   Check(SmcBuildSetup(r, atr, 13, 1, lvl, per, 10, 1.0, 3, 13, 0.1, st) && st.hasFvg && st.obLo == 97 && st.obHi == 99 && st.structLo == 97,
         "setup: OB 97-99, FVG found, setup low 97");
   Check(st.readyTime == r[13].time + per, "setup ready only when bar 13 has closed");
   double zlo, zhi;
   Check(SmcEntryZone(st, false, zlo, zhi) && zlo == 97 && zhi == 99, "entry zone = OB by default");
   Check(!SmcEntryZone(st, true, zlo, zhi), "overlap required: OB 97-99 and FVG 99-102.5 only touch -> no zone");

   MqlRates b;
   b.open = 98; b.high = 99.5; b.low = 97.5; b.close = 99.8;
   b.high = 100; Check(SmcConfirmCandle(b, 1, 97, 99), "M5 touches 97-99, bullish, closes 99.8 above the zone: confirmed");
   b.close = 98.6; Check(!SmcConfirmCandle(b, 1, 97, 99), "closes 98.6 inside the zone: not confirmed");
   b.low = 99.2; b.close = 100; Check(!SmcConfirmCandle(b, 1, 97, 99), "low 99.2 never touched the zone: not confirmed");

   //--- bearish mirror
   Mirror(r, m);
   SmcCollectSwings(m, 12, 2, 2, per, s);
   Check(SmcBias(s) == 1, "mirror: higher highs + higher lows -> bullish bias");
   Check(SmcChochAt(m, atr, 13, 2, 2, per, 0.1, lvl) == -1 && lvl.price == 94, "mirror: close below higher low 94 -> bearish CHoCH");
   Check(SmcChochAt(m, atr, 14, 2, 2, per, 0.1, lvl) == 0, "mirror: no repeated bearish CHoCH");
   Check(SmcFindOrderBlock(m, atr, 13, -1, 10, 1.0, imp, ob) && ob == 11, "mirror: OB = last bullish candle (bar 11)");
   Check(SmcFindFvg(m, atr, 11, 12, 13, 3, 13, -1, 0.1, c, lo, hi) && lo == 97.5 && hi == 101, "bearish FVG: High(C) 97.5 to Low(A) 101");
   b.open = 102; b.high = 103; b.low = 100; b.close = 100.2;
   Check(SmcConfirmCandle(b, -1, 101, 103), "mirror: touches 101-103, bearish, closes below 101: confirmed");

   string summary = StringFormat("SMC tests: %d passed, %d failed", pass, fail);
   Print(summary);
   int f = FileOpen("GS15_smc_tests.txt", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(f != INVALID_HANDLE) { FileWriteString(f, report + summary + "\r\n"); FileClose(f); }
}
