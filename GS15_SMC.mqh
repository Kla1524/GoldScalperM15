//+------------------------------------------------------------------+
//| GS15_SMC.mqh - Mode 3 "SMC: FVG + CHoCH + OB" signal engine.      |
//|                                                                  |
//| Pure functions over CLOSED bars only. Arrays are oldest-first    |
//| (index 0 = oldest). atr[i] is the ATR value at bar i (closed);   |
//| "ATR known before bar i" is atr[i-1].                            |
//| Nothing here sends orders or touches chart objects, so the same  |
//| code is used by the EA and by tools/SMC_Tests.mq5.               |
//| The rules are documented in docs/SMC_RULES.md.                   |
//+------------------------------------------------------------------+
#ifndef GS15_SMC_MQH
#define GS15_SMC_MQH

struct SmcSwing
{
   int      idx;          // bar index of the pivot
   int      type;         // +1 swing high, -1 swing low
   double   price;
   datetime time;         // open time of the pivot bar
   datetime confirmTime;  // close time of the R-th bar to the right (when it became known)
};

struct SmcZone
{
   double lo, hi;
   int    touches;        // number of swing levels merged into it
};

struct SmcSetup
{
   int      dir;            // +1 bullish, -1 bearish
   int      breakIdx;       // CHoCH bar
   datetime chochTime;      // open time of the CHoCH bar
   double   chochLevel;     // swing level that was closed through
   datetime chochSwingTime; // pivot time of that swing (one CHoCH per swing)
   int      impulseStart;
   int      obIdx;
   datetime obTime;
   double   obLo, obHi;
   bool     hasFvg;
   int      fvgC;           // index of bar C of the FVG
   datetime fvgTime;        // open time of bar A
   double   fvgLo, fvgHi;
   double   structLo, structHi;  // extreme of the setup leg (OB .. break) for the SL
   datetime readyTime;      // close time of the last bar needed (break bar or FVG bar C)
};

//--- pivots -----------------------------------------------------------
// Swing high at i: strictly higher than the L bars before it, and higher than OR EQUAL to the
// R bars after it (equal highs to the right do not cancel it, equal highs to the left do).
// So for a run of equal highs, only the earliest one is a pivot - deterministic.
bool SmcIsSwingHigh(const MqlRates &r[], int i, int L, int R)
{
   int n = ArraySize(r);
   if(i - L < 0 || i + R >= n) return false;
   for(int k = 1; k <= L; k++) if(r[i - k].high >= r[i].high) return false;
   for(int k = 1; k <= R; k++) if(r[i + k].high >  r[i].high) return false;
   return true;
}

bool SmcIsSwingLow(const MqlRates &r[], int i, int L, int R)
{
   int n = ArraySize(r);
   if(i - L < 0 || i + R >= n) return false;
   for(int k = 1; k <= L; k++) if(r[i - k].low <= r[i].low) return false;
   for(int k = 1; k <= R; k++) if(r[i + k].low <  r[i].low) return false;
   return true;
}

// All pivots that are CONFIRMED by bar lastIdx (i + R <= lastIdx), oldest first.
int SmcCollectSwings(const MqlRates &r[], int lastIdx, int L, int R, int periodSec, SmcSwing &out[])
{
   ArrayResize(out, 0);
   int n = 0;
   for(int i = L; i + R <= lastIdx; i++)
   {
      int t = 0;
      if(SmcIsSwingHigh(r, i, L, R)) t = 1;
      else if(SmcIsSwingLow(r, i, L, R)) t = -1;
      if(t == 0) continue;
      ArrayResize(out, n + 1);
      out[n].idx = i; out[n].type = t;
      out[n].price = t > 0 ? r[i].high : r[i].low;
      out[n].time = r[i].time;
      out[n].confirmTime = r[i + R].time + periodSec;
      n++;
   }
   return n;
}

// Last two swings of a type (latest in a, previous in b). false if fewer than two.
bool SmcLastTwo(const SmcSwing &s[], int type, SmcSwing &a, SmcSwing &b)
{
   int found = 0;
   for(int k = ArraySize(s) - 1; k >= 0; k--)
   {
      if(s[k].type != type) continue;
      if(found == 0) a = s[k]; else { b = s[k]; return true; }
      found++;
   }
   return false;
}

// +1 higher high AND higher low, -1 lower high AND lower low, 0 otherwise (incl. not enough swings).
int SmcBias(const SmcSwing &s[])
{
   SmcSwing h1, h0, l1, l0;
   if(!SmcLastTwo(s, 1, h1, h0) || !SmcLastTwo(s, -1, l1, l0)) return 0;
   if(h1.price > h0.price && l1.price > l0.price) return 1;
   if(h1.price < h0.price && l1.price < l0.price) return -1;
   return 0;
}

// May a trade in direction dir be taken? Strict: the bias must equal dir (HH and HL for a BUY).
// Loose: a BUY needs a higher high OR a higher low, a SELL a lower high OR a lower low.
bool SmcBiasAllows(const SmcSwing &s[], int dir, bool loose)
{
   if(!loose) return SmcBias(s) == dir;
   SmcSwing h1, h0, l1, l0;
   bool twoH = SmcLastTwo(s, 1, h1, h0), twoL = SmcLastTwo(s, -1, l1, l0);
   if(dir > 0) return (twoH && h1.price > h0.price) || (twoL && l1.price > l0.price);
   return (twoH && h1.price < h0.price) || (twoL && l1.price < l0.price);
}

//--- support / resistance ---------------------------------------------
// Merge swing levels (highs and lows) that lie within tol of each other into zones, sorted low->high.
int SmcBuildZones(const SmcSwing &s[], double tol, SmcZone &z[])
{
   int n = ArraySize(s);
   double lv[];
   ArrayResize(lv, n);
   for(int i = 0; i < n; i++) lv[i] = s[i].price;
   ArraySort(lv);
   ArrayResize(z, 0);
   int m = 0;
   for(int i = 0; i < n; i++)
   {
      if(m > 0 && lv[i] - z[m - 1].hi <= tol) { z[m - 1].hi = lv[i]; z[m - 1].touches++; continue; }
      ArrayResize(z, m + 1);
      z[m].lo = lv[i]; z[m].hi = lv[i]; z[m].touches = 1;
      m++;
   }
   return m;
}

// Nearest zone that is not entirely below price (its high is above price): the resistance a BUY
// runs into. If price is inside a zone, that zone is returned (distance 0 -> RR fails).
bool SmcNearestResistance(const SmcZone &z[], double price, SmcZone &out)
{
   for(int i = 0; i < ArraySize(z); i++)
      if(z[i].hi > price) { out = z[i]; return true; }
   return false;
}

bool SmcNearestSupport(const SmcZone &z[], double price, SmcZone &out)
{
   for(int i = ArraySize(z) - 1; i >= 0; i--)
      if(z[i].lo < price) { out = z[i]; return true; }
   return false;
}

// Like the above, but zones whose near edge is closer than minDist to price (or that contain price)
// are skipped: the target is the first zone that leaves at least minDist of room.
bool SmcResistanceBeyond(const SmcZone &z[], double price, double minDist, SmcZone &out)
{
   for(int i = 0; i < ArraySize(z); i++)
      if(z[i].lo - price >= minDist) { out = z[i]; return true; }
   return false;
}

bool SmcSupportBeyond(const SmcZone &z[], double price, double minDist, SmcZone &out)
{
   for(int i = ArraySize(z) - 1; i >= 0; i--)
      if(price - z[i].hi >= minDist) { out = z[i]; return true; }
   return false;
}

//--- CHoCH ------------------------------------------------------------
// Is bar k a change of character? Uses only swings confirmed before bar k closed (i + R <= k - 1).
// Bullish: the prior structure is bearish (latest swing high and low both lower than the previous
// ones), bar k closes above the latest swing high (a lower high) + buffer, and bar k-1 had not.
// Bearish mirrors it. A break in the SAME direction as the structure is a BOS, not a CHoCH.
int SmcChochAt(const MqlRates &r[], const double &atr[], int k, int L, int R, int periodSec,
               double bufMult, SmcSwing &level)
{
   if(k < 2) return 0;
   SmcSwing s[];
   if(SmcCollectSwings(r, k - 1, L, R, periodSec, s) < 4) return 0;
   SmcSwing h1, h0, l1, l0;
   if(!SmcLastTwo(s, 1, h1, h0) || !SmcLastTwo(s, -1, l1, l0)) return 0;
   double buf = bufMult * atr[k - 1];
   bool bearStruct = h1.price < h0.price && l1.price < l0.price;
   bool bullStruct = h1.price > h0.price && l1.price > l0.price;
   if(bearStruct && r[k].close > h1.price + buf && r[k - 1].close <= h1.price + buf) { level = h1; return 1; }
   if(bullStruct && r[k].close < l1.price - buf && r[k - 1].close >= l1.price - buf) { level = l1; return -1; }
   return 0;
}

//--- impulse, order block, FVG -----------------------------------------
// The impulse is the run of candles in the break direction ending at the break bar k.
// It needs at least one candle whose body is >= dispMult x ATR known before that candle.
// The OB is the last opposite candle before the impulse, at most maxBack bars before k.
bool SmcFindOrderBlock(const MqlRates &r[], const double &atr[], int k, int dir, int maxBack,
                       double dispMult, int &impulseStart, int &obIdx)
{
   bool kInDir = dir > 0 ? r[k].close > r[k].open : r[k].close < r[k].open;
   if(!kInDir) return false;
   int s = k;
   while(s - 1 >= 1 && s - 1 >= k - maxBack &&
         (dir > 0 ? r[s - 1].close > r[s - 1].open : r[s - 1].close < r[s - 1].open))
      s--;
   bool displaced = false;
   for(int j = s; j <= k; j++)
      if(MathAbs(r[j].close - r[j].open) >= dispMult * atr[j - 1]) { displaced = true; break; }
   if(!displaced) return false;
   for(int j = s - 1; j >= MathMax(0, k - maxBack); j--)
   {
      bool opposite = dir > 0 ? r[j].close < r[j].open : r[j].close > r[j].open;
      if(opposite) { impulseStart = s; obIdx = j; return true; }
   }
   return false;
}

// First 3-candle gap (A, B, C consecutive) of the impulse: A at or after the OB, B inside
// [impulseStart .. k + window], C at most lastIdx (only closed bars). Width >= minMult x ATR before the break.
bool SmcFindFvg(const MqlRates &r[], const double &atr[], int obIdx, int impulseStart, int k, int window,
                int lastIdx, int dir, double minMult, int &cIdx, double &lo, double &hi)
{
   double minW = minMult * atr[k - 1];
   for(int a = obIdx; a + 2 <= MathMin(lastIdx, k + window); a++)
   {
      int b = a + 1, c = a + 2;
      if(b < impulseStart || b > k + window) continue;
      if(dir > 0 && r[c].low > r[a].high && r[c].low - r[a].high >= minW)
      { cIdx = c; lo = r[a].high; hi = r[c].low; return true; }
      if(dir < 0 && r[c].high < r[a].low && r[a].low - r[c].high >= minW)
      { cIdx = c; lo = r[c].high; hi = r[a].low; return true; }
   }
   return false;
}

// Builds the setup skeleton for a CHoCH at bar k (FVG may still be missing: check hasFvg).
bool SmcBuildSetup(const MqlRates &r[], const double &atr[], int k, int dir, const SmcSwing &level,
                   int periodSec, int maxBack, double dispMult, int window, int lastIdx, double fvgMinMult,
                   SmcSetup &st)
{
   int imp, ob;
   if(!SmcFindOrderBlock(r, atr, k, dir, maxBack, dispMult, imp, ob)) return false;
   st.dir = dir; st.breakIdx = k; st.chochTime = r[k].time; st.chochLevel = level.price;
   st.chochSwingTime = level.time; st.impulseStart = imp; st.obIdx = ob; st.obTime = r[ob].time;
   st.obLo = r[ob].low; st.obHi = r[ob].high;
   st.structLo = r[ob].low; st.structHi = r[ob].high;
   for(int j = ob; j <= k; j++) { st.structLo = MathMin(st.structLo, r[j].low); st.structHi = MathMax(st.structHi, r[j].high); }
   st.hasFvg = false;
   SmcRefreshFvg(r, atr, lastIdx, window, fvgMinMult, periodSec, st);
   return true;
}

// Looks for the FVG again once more bars have closed (until k + window).
void SmcRefreshFvg(const MqlRates &r[], const double &atr[], int lastIdx, int window, double fvgMinMult,
                   int periodSec, SmcSetup &st)
{
   if(st.hasFvg) return;
   int c; double lo, hi;
   if(SmcFindFvg(r, atr, st.obIdx, st.impulseStart, st.breakIdx, window, lastIdx, st.dir, fvgMinMult, c, lo, hi))
   {
      st.hasFvg = true; st.fvgC = c; st.fvgTime = r[c - 2].time; st.fvgLo = lo; st.fvgHi = hi;
      st.readyTime = MathMax(r[st.breakIdx].time, r[c].time) + periodSec;
   }
}

// Entry zone: the OB, or the OB/FVG overlap when overlap is required (false if they do not overlap).
bool SmcEntryZone(const SmcSetup &st, bool requireOverlap, double &lo, double &hi)
{
   lo = st.obLo; hi = st.obHi;
   if(!requireOverlap) return true;
   lo = MathMax(st.obLo, st.fvgLo);
   hi = MathMin(st.obHi, st.fvgHi);
   return hi > lo;
}

// M5 confirmation candle: its range touches the zone and it closes beyond the zone in the trade
// direction with a candle of that direction.
bool SmcConfirmCandle(const MqlRates &b, int dir, double zlo, double zhi)
{
   bool touch = b.low <= zhi && b.high >= zlo;
   if(!touch) return false;
   if(dir > 0) return b.close > b.open && b.close > zhi;
   return b.close < b.open && b.close < zlo;
}

bool SmcTouches(const MqlRates &b, double zlo, double zhi)
{
   return b.low <= zhi && b.high >= zlo;
}

#endif
