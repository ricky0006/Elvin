# Gold Supply and Demand EA (MT5)

EA canggih untuk trading Gold dengan sistem Supply and Demand yang dilengkapi fitur averaging, hedging, dan manajemen risiko yang komprehensif.

## Fitur Utama

### 1. Sistem Supply and Demand (SND)
- **Auto-detection**: EA secara otomatis mendeteksi zona supply (resistance) dan demand (support)
- **Smart Entry**: Entry otomatis saat price berada di zona SND yang valid
- **Zone Expiry**: Zona SND memiliki masa berlaku yang dapat dikonfigurasi

### 2. Sistem Averaging
- **Progressive Lot**: Lot size bertambah secara progresif sesuai multiplier
- **Price-based Trigger**: Averaging dipicu berdasarkan pergerakan harga
- **Maximum Limit**: Batasan maksimal order averaging untuk kontrol risiko

### 3. Sistem Hedging
- **Auto-hedging**: Hedging otomatis saat floating loss mencapai threshold
- **Dynamic Lot**: Lot size hedging disesuaikan dengan imbalance posisi
- **Risk Control**: Mencegah exposure berlebihan

### 4. Manajemen Risiko
- **Stop Loss & Take Profit**: SL/TP otomatis untuk setiap order
- **Maximum Floating Loss**: Proteksi maksimal floating loss
- **Emergency Close**: Penutupan semua posisi saat kondisi darurat

### 5. Display Informasi Real-time
- Nama EA dan nomor akun
- Total lot Buy dan Sell
- Selisih lot (Buy - Sell)
- Jumlah order Buy dan Sell
- Balance dan Equity
- Floating profit/loss saat ini
- Maximum floating loss yang pernah terjadi

## Cara Penggunaan

### 1. Install EA
1. Copy file `Gold_SND_EA.mq5` ke folder `MQL5/Experts/`
2. Compile EA di MetaEditor
3. Attach EA ke chart Gold (XAUUSD)

### 2. Konfigurasi Parameter

#### EA Settings
- **EA_Name**: Nama EA yang ditampilkan
- **Magic_Number**: Nomor unik untuk identifikasi order
- **Lot_Size**: Ukuran lot default
- **Max_Orders**: Maksimal jumlah order yang diizinkan
- **Max_Lot**: Maksimal ukuran lot per order

#### Supply & Demand Settings
- **SND_Lookback**: Periode lookback untuk analisis SND (candlestick)
- **SND_Threshold**: Minimum pergerakan harga untuk validasi zona SND
- **Zone_Expiry**: Masa berlaku zona SND dalam jam

#### Averaging Settings
- **Averaging_Multiplier**: Multiplier untuk lot size averaging
- **Averaging_Step**: Step harga untuk trigger averaging
- **Max_Averaging**: Maksimal jumlah order averaging

#### Hedging Settings
- **Enable_Hedging**: Aktifkan/nonaktifkan fitur hedging
- **Hedging_Trigger**: Threshold floating loss untuk trigger hedging
- **Hedging_Lot**: Ukuran lot untuk order hedging

#### Risk Management
- **Stop_Loss**: Stop loss dalam satuan harga
- **Take_Profit**: Take profit dalam satuan harga
- **Max_Floating**: Maksimal floating loss yang diizinkan

#### Display Settings
- **Label_Color**: Warna label informasi
- **Label_Size**: Ukuran font label
- **Label_X, Label_Y**: Posisi label di chart

### 3. Strategi Trading

#### Entry Rules
- **Buy**: Saat price berada di zona demand (support)
- **Sell**: Saat price berada di zona supply (resistance)
- **Auto-entry**: Entry otomatis tanpa intervensi manual

#### Averaging Rules
- Trigger: Saat price bergerak melawan posisi
- Lot size: Bertambah secara progresif
- Maximum: 5 order averaging per posisi

#### Hedging Rules
- Trigger: Saat floating loss mencapai -$100
- Strategy: Balance posisi buy/sell
- Lot size: Sesuai imbalance posisi

#### Exit Rules
- **Take Profit**: Otomatis sesuai setting
- **Stop Loss**: Otomatis sesuai setting
- **Emergency**: Saat floating loss melebihi batas maksimal

## Keunggulan EA

### 1. Adaptif
- Menyesuaikan dengan kondisi market yang dinamis
- Auto-detection zona SND yang valid
- Manajemen posisi yang fleksibel

### 2. Risk Management
- Multiple layer proteksi risiko
- Kontrol exposure yang ketat
- Emergency exit system

### 3. Profit Optimization
- Averaging untuk cost reduction
- Hedging untuk balance risk
- Smart entry di level optimal

### 4. User Experience
- Display informasi real-time
- Konfigurasi yang mudah
- Monitoring yang komprehensif

## Tips Penggunaan

### 1. Market Conditions
- **Trending Market**: EA akan lebih efektif
- **Sideways Market**: Perhatikan setting SND threshold
- **High Volatility**: Sesuaikan SL/TP dan averaging step

### 2. Risk Management
- Mulai dengan lot size kecil
- Monitor floating loss secara berkala
- Sesuaikan parameter dengan capital

### 3. Optimization
- Test EA di demo account terlebih dahulu
- Optimize parameter sesuai timeframe
- Monitor performance secara regular

## Disclaimer

- EA ini dibuat untuk educational purpose
- Trading forex memiliki risiko tinggi
- Pastikan memahami semua fitur sebelum live trading
- Gunakan money management yang proper
- Test thoroughly di demo account

## Support

Untuk pertanyaan atau support, silakan hubungi developer atau buat issue di repository.

---

**Happy Trading! 🚀**