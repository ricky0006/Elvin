# AveragingHedgeEA (MT5)

EA ini menggabungkan dua pendekatan:
- Averaging/Grid saat market sideway (ranging) menggunakan sinyal RSI
- Hedging saat market trending menggunakan sinyal ADX (+DI/−DI)

File EA: `AveragingHedgeEA.mq5`

## Instalasi
1. Buka MetaTrader 5 -> File -> Open Data Folder.
2. Masuk ke `MQL5/Experts/` lalu salin `AveragingHedgeEA.mq5` ke folder tersebut.
3. Buka MetaEditor, compile file `AveragingHedgeEA.mq5` sampai sukses.
4. Kembali ke MT5, drag EA ke chart simbol yang ingin ditradingkan. Aktifkan Algo Trading.

## Cara Kerja Singkat
- Ranging (ADX < threshold):
  - Entry awal berdasarkan RSI: Oversold -> Buy, Overbought -> Sell
  - Averaging: menambah posisi pada arah yang sama jika harga bergerak berlawanan sejauh `GridStepPoints`
  - Basket TP: menutup semua posisi saat profit gabungan mencapai `BasketTPMoney`
- Trending (ADX >= threshold):
  - Arah trend ditentukan oleh +DI vs −DI (ADX timeframe input)
  - Buka posisi searah trend. Jika ada eksposur yang melawan trend, EA menambah hedge searah trend tiap `HedgeStepPoints`
  - Trailing stop opsional untuk posisi searah trend

## Parameter Utama
- Magic & Eksekusi:
  - `Magic`: penanda unik EA
  - `AllowNewTrades`: izinkan buka posisi baru
  - `MaxSpreadPoints`, `Slippage`: proteksi eksekusi
- Waktu Trading:
  - `UseTradingHours`, `StartHour`, `EndHour`
- Lot & Risiko:
  - `UseAutoLot`: jika true, lot dihitung dari `%RiskPerTradePct`
  - `FixedLot`: lot tetap bila `UseAutoLot=false`
  - `RiskPerTradePct`: persen balance per entry (perkiraan)
- Timeframe Sinyal:
  - `SignalTF`: TF indikator RSI/ADX
- Averaging (Range):
  - `EnableAveraging`
  - `GridStepPoints`: jarak grid (point)
  - `MaxAveragingLevels`: maksimum level per arah
  - `LotMultiplier`: kelipatan lot tiap level (1.0 = tetap)
  - `BasketTPMoney`: target profit gabungan untuk close semua posisi
  - `RSIPeriod`, `RSIOverbought`, `RSIOversold`
- Hedging (Trend):
  - `EnableHedging`
  - `ADXPeriod`, `ADXTrendThreshold`
  - `HedgeStepPoints`, `MaxHedgeLevels`, `HedgeLotFactor`
  - Trailing: `UseTrailingStop`, `TrailStopPoints`, `TrailStepPoints`
- Proteksi Harian:
  - `UseDailyLossLimit`, `DailyLossLimit` (nilai negatif, contoh: -100)

## Rekomendasi Awal (silakan sesuaikan)
- Timeframe sinyal: M15 atau H1
- `ADXTrendThreshold`: 20–25
- `GridStepPoints`: 200–400 (disesuaikan volatilitas)
- `HedgeStepPoints`: 200–400
- `BasketTPMoney`: 5–20 (akun kecil), naikkan sesuai balance
- `LotMultiplier`: 1.0 (konservatif), gunakan >1.0 dengan sangat hati-hati

## Catatan Risiko
- Averaging/Grid dan Hedging meningkatkan eksposur. Set parameter secara konservatif, uji di akun demo terlebih dahulu.
- EA ini dirancang untuk akun hedging. Di akun netting, perilaku posisi bisa berbeda.
- Perhatikan `MaxSpreadPoints` agar tidak entry saat spread melebar.

## Logika Teknis (ringkas)
- Ranging: entry awal pakai RSI, penambahan posisi jika bergerak berlawanan >= `GridStepPoints` dari entry terakhir arah yang sama.
- Trending: +DI > −DI -> uptrend, sebaliknya downtrend jika ADX >= threshold. Tambah hedge pada kelanjutan tren setiap `HedgeStepPoints` dan aktifkan trailing jika diizinkan.

## Dukungan
Butuh penyesuaian (misal filter sesi, SL/TP per posisi, news filter, multi‑symbol)? Beri tahu kebutuhan Anda dan parameter yang diinginkan.