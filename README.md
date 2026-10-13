# GoldScalperM15

**MetaTrader 5 Expert Advisor for XAUUSD (Gold) — M15 trend-pullback scalper**
with ATR-based risk, an economic-calendar news filter, an on-chart control panel and mobile push notifications.

EA เทรดทองคำ (XAUUSD) บน MT5 แบบ Scalping ใน timeframe M15 — เทรดตามเทรนด์ รอย่อแล้วค่อยเข้า, SL/TP ตาม ATR, หลบข่าวแรงอัตโนมัติ, มีแผงควบคุมบนกราฟ และแจ้งเตือนเข้ามือถือ

> ⚠️ **คำเตือน / Disclaimer** — โปรเจกต์นี้ทำเพื่อการศึกษา ยังไม่ผ่านการพิสูจน์ว่าทำกำไรได้ การเทรดทองคำมีความเสี่ยงสูง ทดสอบบนบัญชี Demo ก่อนเสมอ ผู้ใช้รับผิดชอบผลการเทรดเอง
> *For educational purposes only. Not financial advice. Always test on a demo account first.*

---

## ✨ Features

| | |
|---|---|
| 📈 **Strategy** | EMA200 trend filter + EMA 9/21 direction + pullback-to-EMA9 rejection candle + RSI confirmation |
| 🛡️ **Risk** | Fixed lot · SL/TP as ATR multiples · Breakeven · ATR trailing stop · one position at a time |
| 🚦 **Filters** | Trading-hour window · max spread · max trades/day · daily loss limit (% balance) · Friday close · min ATR |
| 📰 **News filter** | Built-in MT5 economic calendar — pauses entries around high-impact events (configurable currencies & window) |
| 🖥️ **Control panel** | Live status, open P/L, today's stats, spread/ATR, next news · **Pause/Resume** and **Close all** buttons |
| 📱 **Notifications** | MT5 mobile push on open/close (TP/SL + P/L), breakeven, news windows, daily-loss stop |
| ⚙️ **Presets** | Safe / Normal / Active `.set` files |

## 📊 Entry logic

Checked once per closed M15 candle:

| | BUY | SELL |
|---|---|---|
| Trend | Close > EMA200, EMA9 > EMA21 | Close < EMA200, EMA9 < EMA21 |
| Pullback | Low touches EMA9, closes back above | High touches EMA9, closes back below |
| Candle | Bullish | Bearish |
| Momentum | RSI 50–70 | RSI 30–50 |

Exit: SL = 1.2×ATR, TP = 1.5×ATR → breakeven at 0.8×ATR → trail at 1.0×ATR (all configurable).

## 🖥️ On-chart panel

```
┌──────────────────────────────────────┐
│ GoldScalper M15  v1.20               │
│ สถานะ: พร้อมเทรด - รอสัญญาณ          │
│ ออเดอร์: BUY 0.01 lot | P/L 3.20 USD  │
│ วันนี้: 2/5 ไม้ | P/L 5.40 USD         │
│ สเปรด: 0.25 / 0.40 | ATR: 6.85        │
│ ข่าวถัดไป: 19:30 USD Nonfarm Payrolls  │
│ [ หยุดชั่วคราว ]   [ ปิดทุกไม้ ]         │
└──────────────────────────────────────┘
```

## 🚀 Installation

**Windows (one click):** run `install_to_MT5.bat` — it compiles the EA with MetaEditor, then (after you confirm) copies it to `MQL5\Experts\MyEA` and the presets to `MQL5\Presets`.

**Manual:** copy `GoldScalperM15.mq5` to your MT5 `MQL5\Experts` folder (File → Open Data Folder), open it in MetaEditor and press **F7**.

Then drag the EA onto an XAUUSD chart, enable **Allow Algo Trading**, and load a preset from the **Inputs** tab.

📖 Full Thai guide (setup, push notifications, backtesting, troubleshooting): [คู่มือ_GoldScalperM15.md](คู่มือ_GoldScalperM15.md)

## ⚙️ Presets

| | Safe | Normal | Active |
|---|---|---|---|
| SL / TP (×ATR) | 1.5 / 1.5 | 1.2 / 1.5 | 1.0 / 1.3 |
| Max trades/day | 3 | 5 | 8 |
| Daily loss limit | 2% | 3% | 4% |
| News window | ±45 min, medium+high, close positions | ±30 min, high | ±15 min, high |

## 📁 Files

```
GoldScalperM15.mq5      EA source (MQL5)
install_to_MT5.bat      compile + install helper
presets/*.set           Safe / Normal / Active input presets
คู่มือ_GoldScalperM15.md  Thai user guide
```

## 🗺️ Roadmap

- [ ] Telegram notifications & remote control
- [ ] Higher-timeframe (H1/H4) trend filter
- [ ] Trade journal export (CSV)
- [ ] Partial take-profit

## Notes

- The news filter uses the MT5 economic calendar, which is **not available in the Strategy Tester** — backtests include trades around news.
- Trading hours are in **broker server time**.
- Symbol names vary by broker (`XAUUSD`, `XAUUSDm`, `GOLD`, …).
