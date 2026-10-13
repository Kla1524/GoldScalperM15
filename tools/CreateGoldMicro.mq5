//+------------------------------------------------------------------+
//|                                              CreateGoldMicro.mq5 |
//|  Test helper: creates custom symbol GOLD_MICRO = a copy of GOLD  |
//|  with a 100x smaller contract (like an XM Micro account), and    |
//|  copies real M1 bars and ticks (incl. spreads) from GOLD.        |
//|  Writes a summary to Common\Files\GS15_micro_result.txt.         |
//|  InpDeleteOnly = true removes the custom symbol instead.         |
//+------------------------------------------------------------------+

input string   InpSource     = "GOLD";
input string   InpName       = "GOLD_MICRO";
input double   InpDivisor    = 100.0;              // contract size = source / divisor
input datetime InpRatesFrom  = D'2025.10.01';      // M1 bars from (indicator warm-up)
input datetime InpTicksFrom  = D'2026.08.01';      // real ticks from
input datetime InpTo         = D'2026.10.13';
input bool     InpDeleteOnly = false;

string out = "";

void Log(string s)
{
   Print(s);
   out += s + "\n";
}

void Save()
{
   int f = FileOpen("GS15_micro_result.txt", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(f != INVALID_HANDLE)
   {
      FileWriteString(f, out);
      FileClose(f);
   }
}

bool DeleteCustom()
{
   if(!SymbolInfoInteger(InpName, SYMBOL_CUSTOM))
      return true;
   SymbolSelect(InpName, false);
   if(!CustomSymbolDelete(InpName))
   {
      Log("delete failed: " + (string)GetLastError());
      return false;
   }
   Log("deleted " + InpName);
   return true;
}

void OnStart()
{
   bool exists = false;
   if(SymbolExist(InpName, exists) && exists && !DeleteCustom())
   {
      Save();
      return;
   }
   if(InpDeleteOnly)
   {
      Save();
      return;
   }

   SymbolSelect(InpSource, true);
   double contract = SymbolInfoDouble(InpSource, SYMBOL_TRADE_CONTRACT_SIZE);
   double tickSize = SymbolInfoDouble(InpSource, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(InpSource, SYMBOL_TRADE_TICK_VALUE);
   Log(StringFormat("source %s: contract=%.2f tickSize=%.5f tickValue=%.5f calcMode=%d digits=%d volMin=%.2f profitCcy=%s",
                    InpSource, contract, tickSize, tickVal,
                    (int)SymbolInfoInteger(InpSource, SYMBOL_TRADE_CALC_MODE),
                    (int)SymbolInfoInteger(InpSource, SYMBOL_DIGITS),
                    SymbolInfoDouble(InpSource, SYMBOL_VOLUME_MIN),
                    SymbolInfoString(InpSource, SYMBOL_CURRENCY_PROFIT)));

   if(!CustomSymbolCreate(InpName, "Custom\\Test", InpSource))
   {
      Log("create failed: " + (string)GetLastError());
      Save();
      return;
   }
   CustomSymbolSetDouble(InpName, SYMBOL_TRADE_CONTRACT_SIZE, contract / InpDivisor);
   CustomSymbolSetDouble(InpName, SYMBOL_TRADE_TICK_VALUE, tickVal / InpDivisor);
   CustomSymbolSetString(InpName, SYMBOL_DESCRIPTION, "TEST ONLY: " + InpSource + " with micro contract");

   // M1 bars, month by month (a single CopyRates is capped by "Max bars in chart")
   long nr = 0, wr = 0;
   for(datetime d = InpRatesFrom; d < InpTo; d += 30 * 86400)
   {
      datetime e = MathMin(d + 30 * 86400 - 60, InpTo);
      MqlRates rates[];
      int n = CopyRates(InpSource, PERIOD_M1, d, e, rates);
      if(n > 0)
      {
         nr += n;
         int w = CustomRatesReplace(InpName, d, e, rates);
         if(w > 0) wr += w;
      }
   }
   Log(StringFormat("M1 bars: copied=%I64d written=%I64d", nr, wr));

   // Ticks, one day at a time to limit memory
   long total = 0;
   for(datetime d = InpTicksFrom; d < InpTo; d += 86400)
   {
      MqlTick ticks[];
      ulong from = (ulong)d * 1000, to = (ulong)(d + 86400) * 1000 - 1;
      int n = -1;
      for(int attempt = 0; attempt < 5 && n < 0; attempt++)
      {
         n = CopyTicksRange(InpSource, ticks, COPY_TICKS_ALL, from, to);
         if(n < 0) Sleep(500);
      }
      if(n > 0)
      {
         int w = CustomTicksReplace(InpName, (long)from, (long)to, ticks);
         if(w < 0) Log(StringFormat("ticks %s: write failed %d", TimeToString(d, TIME_DATE), GetLastError()));
         else total += w;
      }
   }
   Log(StringFormat("ticks written: %I64d", total));
   Log(StringFormat("%s: contract=%.4f tickValue=%.5f", InpName,
                    SymbolInfoDouble(InpName, SYMBOL_TRADE_CONTRACT_SIZE),
                    SymbolInfoDouble(InpName, SYMBOL_TRADE_TICK_VALUE)));
   Log("DONE");
   Save();
}
