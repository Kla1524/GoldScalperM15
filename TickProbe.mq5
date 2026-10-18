//+------------------------------------------------------------------+
//| TickProbe.mq5 - Strategy Tester only. For every server day,       |
//| prints the time of the last tick of the day and of the first      |
//| tick, so we can see when GOLD trading stops each day (daily       |
//| close checks need ticks to act on). No orders.                    |
//+------------------------------------------------------------------+
#property version "1.00"
datetime dayStart = 0, firstTick = 0, lastTick = 0;
int      ticks2300 = 0;   // ticks at or after 23:00 server

void Flush()
{
   if(dayStart == 0) return;
   MqlDateTime d; TimeToStruct(dayStart, d);
   PrintFormat("PROBE %s dow=%d first=%s last=%s ticks_after_2300=%d", TimeToString(dayStart, TIME_DATE), d.day_of_week,
               TimeToString(firstTick, TIME_MINUTES | TIME_SECONDS), TimeToString(lastTick, TIME_MINUTES | TIME_SECONDS), ticks2300);
}

void OnTick()
{
   datetime now = TimeCurrent();
   datetime day = now - (now % 86400);
   if(day != dayStart)
   {
      Flush();
      dayStart = day; firstTick = now; ticks2300 = 0;
   }
   lastTick = now;
   MqlDateTime t; TimeToStruct(now, t);
   if(t.hour >= 23) ticks2300++;
}

void OnDeinit(const int reason) { Flush(); }
