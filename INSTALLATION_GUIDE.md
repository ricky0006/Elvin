# Installation Guide - Gold SND EA

## Prerequisites

Sebelum menginstall EA, pastikan Anda memiliki:
- MetaTrader 5 (MT5) yang sudah terinstall
- Akun demo atau live yang sudah terverifikasi
- Koneksi internet yang stabil
- Pengetahuan dasar tentang trading forex

## Step-by-Step Installation

### Step 1: Download Files
Download semua file yang diperlukan:
- `Gold_SND_EA.mq5` - EA utama
- `Gold_SND_Backtest.mq5` - Versi backtest
- `Gold_SND_Presets.set` - File preset settings
- `README.md` - Dokumentasi lengkap
- `INSTALLATION_GUIDE.md` - Panduan instalasi ini

### Step 2: Install EA ke MT5

#### Method 1: Manual Copy
1. Buka folder MT5 Anda (biasanya di `C:\Users\[Username]\AppData\Roaming\MetaQuotes\Terminal\[ID]\MQL5\`)
2. Masuk ke folder `Experts\`
3. Copy file `Gold_SND_EA.mq5` ke folder tersebut
4. Copy file `Gold_SND_Backtest.mq5` ke folder tersebut

#### Method 2: Via MetaEditor
1. Buka MT5
2. Tekan `F4` atau klik `View` → `MetaEditor`
3. Di MetaEditor, klik `File` → `Open`
4. Browse ke file `Gold_SND_EA.mq5`
5. Klik `Compile` (F7) untuk compile EA

### Step 3: Install Preset Settings
1. Copy file `Gold_SND_Presets.set` ke folder `MQL5\Profiles\`
2. Atau copy ke folder `MQL5\Files\` untuk akses dari EA

### Step 4: Compile EA
1. Di MetaEditor, pastikan tidak ada error
2. Klik `Compile` atau tekan `F7`
3. Pastikan muncul pesan "0 errors, 0 warnings"

### Step 5: Attach EA ke Chart
1. Buka chart Gold (XAUUSD) di timeframe H1 atau H4
2. Klik kanan pada chart
3. Pilih `Expert Advisors` → `Gold_SND_EA`
4. EA akan muncul di chart

## Konfigurasi Awal

### 1. Basic Settings
- **EA_Name**: Nama yang akan ditampilkan
- **Magic_Number**: Nomor unik (ubah jika ada EA lain)
- **Lot_Size**: Ukuran lot sesuai capital Anda

### 2. Risk Management
- **Stop_Loss**: Sesuaikan dengan toleransi risiko
- **Take_Profit**: Target profit yang diinginkan
- **Max_Floating**: Maksimal floating loss yang diizinkan

### 3. Supply & Demand
- **SND_Lookback**: Periode analisis (50-100 candlestick)
- **SND_Threshold**: Sensitivitas deteksi zona
- **Zone_Expiry**: Masa berlaku zona SND

### 4. Averaging & Hedging
- **Averaging_Multiplier**: Multiplier lot size
- **Hedging_Trigger**: Trigger untuk hedging
- **Max_Averaging**: Maksimal order averaging

## Testing EA

### 1. Demo Account
- **Wajib**: Test EA di demo account terlebih dahulu
- **Durasi**: Minimal 1-2 minggu
- **Monitoring**: Perhatikan semua fitur berfungsi

### 2. Backtest
- Gunakan `Gold_SND_Backtest.mq5` untuk testing
- Set periode backtest yang sesuai
- Analisis hasil backtest dengan teliti

### 3. Forward Test
- Test EA di demo dengan data real-time
- Monitor performance dan risk management
- Sesuaikan parameter jika diperlukan

## Troubleshooting

### Common Issues

#### EA Tidak Muncul di Chart
- Pastikan EA sudah di-compile dengan benar
- Restart MT5
- Check folder `Experts` sudah benar

#### Error Compile
- Pastikan syntax MQL5 sudah benar
- Check semua function yang diperlukan
- Update MT5 ke versi terbaru

#### EA Tidak Trading
- Check `AutoTrading` sudah aktif
- Pastikan `Allow live trading` sudah centang
- Check setting `Max_Orders` dan `Max_Lot`

#### Display Labels Tidak Muncul
- Check setting `Label_X` dan `Label_Y`
- Pastikan `Label_Color` dan `Label_Size` sudah benar
- Restart EA jika diperlukan

### Performance Issues

#### EA Lambat
- Kurangi `SND_Lookback` period
- Kurangi frekuensi update display
- Optimize parameter sesuai kebutuhan

#### Memory Usage Tinggi
- Restart EA secara berkala
- Monitor penggunaan memory
- Close chart yang tidak diperlukan

## Optimization Tips

### 1. Parameter Tuning
- **Conservative**: Mulai dengan setting konservatif
- **Gradual**: Naikkan parameter secara bertahap
- **Monitor**: Selalu monitor performance

### 2. Market Conditions
- **Trending**: Gunakan setting aggressive
- **Sideways**: Gunakan setting conservative
- **Volatile**: Sesuaikan SL/TP dan averaging

### 3. Timeframe
- **H1**: Cocok untuk swing trading
- **H4**: Cocok untuk position trading
- **D1**: Cocok untuk long-term trading

## Safety Measures

### 1. Risk Management
- **Never risk more than 2% per trade**
- **Use proper position sizing**
- **Monitor floating loss continuously**

### 2. Emergency Procedures
- **Emergency Close**: Fungsi untuk tutup semua posisi
- **Max Floating**: Proteksi maksimal floating loss
- **Manual Override**: Kemampuan intervensi manual

### 3. Monitoring
- **Daily Check**: Monitor EA setiap hari
- **Performance Review**: Review performance mingguan
- **Parameter Adjustment**: Sesuaikan parameter sesuai kondisi

## Support & Maintenance

### 1. Regular Updates
- Update EA secara berkala
- Monitor perubahan market conditions
- Optimize parameter sesuai kebutuhan

### 2. Backup
- Backup setting EA secara regular
- Backup file preset yang sudah dioptimize
- Document semua perubahan parameter

### 3. Documentation
- Catat semua setting yang digunakan
- Document performance dan hasil trading
- Catat lesson learned dan improvement

## Final Checklist

- [ ] EA sudah di-compile tanpa error
- [ ] EA sudah di-attach ke chart Gold
- [ ] Semua parameter sudah disesuaikan
- [ ] Demo testing sudah dilakukan
- [ ] Risk management sudah dipahami
- [ ] Emergency procedures sudah dipahami
- [ ] Monitoring system sudah siap
- [ ] Backup dan dokumentasi sudah lengkap

## Contact & Support

Jika mengalami masalah atau membutuhkan bantuan:
- Check dokumentasi lengkap di `README.md`
- Review troubleshooting section
- Contact developer untuk support teknis
- Join community forum untuk sharing experience

---

**Selamat Trading! 🚀**

*Pastikan selalu trading dengan bijak dan manage risiko dengan baik.*