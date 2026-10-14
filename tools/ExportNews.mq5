//+------------------------------------------------------------------+
//| ExportNews.mq5 - exports the MT5 economic calendar history to     |
//| Common\Files\GS15_news_<currencies>.csv so the EA can apply its   |
//| news filter in the Strategy Tester (where the calendar is not    |
//| available). Same source as live trading. No trading.             |
//+------------------------------------------------------------------+
#property script_show_inputs
input string   InpCurrencies = "USD";
input datetime InpFrom       = D'2017.12.01';
input int      InpDaysAhead  = 21;

void OnStart()
{
   datetime to = TimeCurrent() + InpDaysAhead * 86400;
   string cur[];
   int nc = StringSplit(InpCurrencies, ',', cur);
   string name = "GS15_news_" + InpCurrencies + ".csv";
   StringReplace(name, ",", "_");
   int f = FileOpen(name, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(f == INVALID_HANDLE) { Print("cannot write ", name); return; }
   FileWriteString(f, "time,currency,importance,event\n");
   int rows = 0;
   for(int c = 0; c < nc; c++)
   {
      StringTrimLeft(cur[c]); StringTrimRight(cur[c]);
      // Year by year keeps each request small.
      for(datetime a = InpFrom; a < to; a += 366 * 86400)
      {
         datetime b = (datetime)MathMin((long)(a + 366 * 86400), (long)to);
         MqlCalendarValue v[];
         if(!CalendarValueHistory(v, a, b, NULL, cur[c]))
         {
            PrintFormat("CalendarValueHistory %s %s: error %d", cur[c], TimeToString(a, TIME_DATE), GetLastError());
            continue;
         }
         for(int i = 0; i < ArraySize(v); i++)
         {
            MqlCalendarEvent ev;
            if(!CalendarEventById(v[i].event_id, ev) || ev.importance < CALENDAR_IMPORTANCE_MODERATE)
               continue;
            string nm = ev.name;
            StringReplace(nm, ",", " ");
            FileWriteString(f, StringFormat("%s,%s,%d,%s\n", TimeToString(v[i].time, TIME_DATE | TIME_MINUTES), cur[c], (int)ev.importance, nm));
            rows++;
         }
      }
   }
   FileClose(f);
   PrintFormat("ExportNews: %d events (moderate+high) written to Common\\Files\\%s (times as the calendar reports them; TimeTradeServer now %s, TimeGMT %s)",
               rows, name, TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS), TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS));
}
