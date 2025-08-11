## SMC Limit EA (MT4)

EA ini menerapkan pola SMC sederhana:
- Deteksi Struktur (BOS) pada TF struktur (default H1)
- Identifikasi Order Block (OB) terakhir: candle berlawanan sebelum BOS
- Pasang pending order di 50% body OB:
  - Bullish: Buy Limit + SL di bawah low OB (min ATR), TP = RR x SL
  - Bearish: Sell Limit + SL di atas high OB (min ATR), TP = RR x SL
- Filter spread, jam trading, serta manajemen posisi (Break-even, ATR trailing)

### File
- `SMC_Limit_EA.mq4`: letakkan di `MQL4/Experts/` lalu compile di MetaEditor.

### Cara Pakai
1. Copy `SMC_Limit_EA.mq4` ke folder MT4: File > Open Data Folder > `MQL4/Experts/`
2. Buka MetaEditor, compile EA, lalu attach ke chart `XAUUSD` (Gold).
3. Biarkan TF chart sesuai selera; struktur dihitung pada `InpStructureTF` (default H1).
4. Pastikan AutoTrading aktif, serta parameter disesuaikan broker.

### Parameter Penting
- `InpSymbolMustContain` = "XAU": Membatasi EA hanya aktif pada pair yang mengandung "XAU".
- `InpStructureTF` = H1: TF struktur SMC.
- `InpRiskPercent` = 0.5: Risiko per trade (% balance).
- `InpRiskReward` = 2.0: Target RR.
- `InpATRPeriod`, `InpATRMultiplierSL`: Minimum SL berbasis ATR.
- `InpMaxSpreadPoints`: Filter spread maksimum (points).
- `InpUseTradingHours`, `InpStartHour`, `InpEndHour`: Jam trading (server time).
- `InpDeleteOppositePending`: Hapus pending berlawanan saat bias flip.
- `InpMoveToBreakEven`, `InpBreakEvenAtR`: Pindah SL ke BE pada nR.
- `InpUseATRTrailing`, `InpATRTrailMultiplier`: Trailing SL ATR opsional.

### Catatan untuk Gold (XAUUSD)
- Volatilitas tinggi: gunakan `InpRiskPercent` rendah (0.25–0.5%) dan `InpATRMultiplierSL` ≥ 1.5.
- Perhatikan `InpMaxSpreadPoints` sesuai broker (Gold sering lebih lebar dari major FX).
- Disarankan jam aktif London/NY untuk likuiditas (misal 07–22 server time), atur `InpUseTradingHours`.

### Batasan & Saran
- Deteksi SMC di EA ini dibuat konservatif: BOS via break swing dan OB = last opposing candle sebelum BOS. Ini tidak mencakup semua variasi SMC (FVG, liquidity sweep kompleks, multi-timeframe refinement).
- Anda bisa memperketat pemilihan OB (misalnya body > rata-rata, volume, atau confluence FVG) bila diperlukan.
- Selalu uji di demo/backtest sebelum live.

### Troubleshooting
- Tidak muncul pending: cek spread, jam trading, dan apakah BOS + OB valid terdeteksi pada TF struktur.
- Lot terlalu kecil: tingkatkan `InpRiskPercent` atau pastikan SL tidak terlalu jauh.
- Order ditolak: broker `StopLevel` terlalu dekat – EA akan melewatkan jika jarak SL terlalu kecil; sesuaikan buffer atau TF.