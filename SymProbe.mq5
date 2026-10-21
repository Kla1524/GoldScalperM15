//+------------------------------------------------------------------+
//| SymProbe.mq5 - Strategy Tester only: prints the broker's symbols |
//| with contract size, digits and the typical spread, no orders.    |
//+------------------------------------------------------------------+
#property version "1.00"
int OnInit()
{
   int n = SymbolsTotal(false);
   for(int i = 0; i < n; i++)
   {
      string s = SymbolName(i, false);
      PrintFormat("SYM %s | %s | contract %.2f | digits %d | path %s", s, SymbolInfoString(s, SYMBOL_DESCRIPTION),
                  SymbolInfoDouble(s, SYMBOL_TRADE_CONTRACT_SIZE), (int)SymbolInfoInteger(s, SYMBOL_DIGITS), SymbolInfoString(s, SYMBOL_PATH));
   }
   return INIT_SUCCEEDED;
}
void OnTick() {}
