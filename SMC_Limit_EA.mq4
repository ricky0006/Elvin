#property strict
#property copyright "SMC Limit EA"
#property link      "https://"
#property version   "1.00"
#property description "EA SMC: Pasang Buy Limit & Sell Limit di 50% Order Block setelah BOS, dengan risk mgmt dan filter untuk XAUUSD."

// ==========================
// Input Parameters
// ==========================
input string InpSymbolMustContain     = "XAU";     // Jalankan hanya jika simbol mengandung string ini (kosongkan untuk semua)
input ENUM_TIMEFRAMES InpStructureTF  = PERIOD_H1;  // TF struktur SMC (BOS & OB)
input int    InpSwingLeft             = 3;          // Kiri swing (fractal)
input int    InpSwingRight            = 3;          // Kanan swing (fractal)

input double InpRiskPercent           = 0.50;       // % resiko per transaksi (balance)
input double InpRiskReward            = 2.0;        // RR target TP
input int    InpATRPeriod             = 14;         // ATR period (struktur TF)
input double InpATRMultiplierSL       = 1.5;        // Minimum SL = ATR * multiplier
input int    InpSLExtraPoints         = 100;        // Buffer tambahan SL (points)
input int    InpTPBufferPoints        = 0;          // Buffer TP (points)

input int    InpMaxSpreadPoints       = 250;        // Maks spread (points)
input int    InpSlippagePoints        = 30;         // Slippage (points)
input int    InpMagicNumber           = 5081101;    // Magic number

input bool   InpUseTradingHours       = true;       // Batasi jam trading
input int    InpStartHour             = 1;          // Jam mulai (server time)
input int    InpEndHour               = 23;         // Jam akhir (server time)

input bool   InpDeleteOppositePending = true;       // Hapus pending berlawanan saat flip struktur
input int    InpPendingExpiryHours    = 48;         // Kadaluarsa pending order (jam)

input bool   InpMoveToBreakEven       = true;       // Pindah SL ke BE saat profit >= nR
input double InpBreakEvenAtR          = 1.0;        // Pindah ke BE pada nR
input bool   InpUseATRTrailing        = false;      // Trailing SL berbasis ATR
input double InpATRTrailMultiplier    = 1.0;        // ATR trailing multiplier

input int    InpRecalcEverySeconds    = 20;         // Interval re-kalkulasi (detik)
input bool   InpOnePendingPerSide     = true;       // Batasi 1 pending per arah
input int    InpMaxTotalOrders        = 2;          // Total order (termasuk pending) maksimum

// ==========================
// Types & Structs
// ==========================
enum MarketBias
{
   Bias_None = 0,
   Bias_Bullish = 1,
   Bias_Bearish = -1
};

struct CandleInfo
{
   double open;
   double high;
   double low;
   double close;
   datetime time;
   int index; // index bar pada TF struktur
};

struct OrderBlockZone
{
   bool    isValid;
   bool    isBullish;      // true jika OB bullish (last down candle sebelum BOS up)
   CandleInfo obCandle;    // candle OB
   double  entryPrice;     // harga entry pending (50% body)
   double  stopPrice;      // harga SL disarankan (akan disesuaikan ATR min)
   double  atr;            // ATR pada candle BOS
};

// ==========================
// Global State
// ==========================
datetime g_lastCalcTime = 0;
MarketBias g_lastBias   = Bias_None;
OrderBlockZone g_lastZone;

// ==========================
// Utility Helpers
// ==========================
bool SymbolIsAllowed()
{
   if(StringLen(InpSymbolMustContain) == 0) return true;
   string sym = Symbol();
   return StringFind(sym, InpSymbolMustContain, 0) >= 0;
}

int SpreadPoints()
{
   return (int)MarketInfo(Symbol(), MODE_SPREAD);
}

double TickSize()
{
   return MarketInfo(Symbol(), MODE_TICKSIZE);
}

double TickValueMoney()
{
   return MarketInfo(Symbol(), MODE_TICKVALUE);
}

double MinLot()
{
   return MarketInfo(Symbol(), MODE_MINLOT);
}

double MaxLot()
{
   return MarketInfo(Symbol(), MODE_MAXLOT);
}

double LotStep()
{
   return MarketInfo(Symbol(), MODE_LOTSTEP);
}

int StopLevelPoints()
{
   return (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
}

bool WithinTradingHours()
{
   if(!InpUseTradingHours) return true;
   int h = TimeHour(TimeCurrent());
   if(InpStartHour <= InpEndHour)
      return (h >= InpStartHour && h < InpEndHour);
   // window menyilang midnight
   return (h >= InpStartHour || h < InpEndHour);
}

bool IsNewRecalcMoment()
{
   if(g_lastCalcTime == 0) return true;
   return (TimeCurrent() - g_lastCalcTime) >= InpRecalcEverySeconds;
}

// Normalize lot ke step broker
double NormalizeLot(double lots)
{
   double step = LotStep();
   if(step <= 0) step = 0.01;
   double normalized = MathFloor(lots/step)*step;
   normalized = MathMax(normalized, MinLot());
   normalized = MathMin(normalized, MaxLot());
   return NormalizeDouble(normalized, 2);
}

int CountOrdersByType(int type)
{
   int count = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() == type) count++;
   }
   return count;
}

int CountAllOurOrders()
{
   int count = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      count++;
   }
   return count;
}

void DeletePendingByType(int type)
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != type) continue;
      if(!OrderDelete(OrderTicket()))
      {
         Print("Failed to delete pending order ", OrderTicket(), " Error:", GetLastError());
         ResetLastError();
      }
   }
}

void DeleteAllOppositePendings(MarketBias bias)
{
   if(!InpDeleteOppositePending) return;
   if(bias == Bias_Bullish)
   {
      DeletePendingByType(OP_SELLLIMIT);
      DeletePendingByType(OP_SELLSTOP);
   }
   else if(bias == Bias_Bearish)
   {
      DeletePendingByType(OP_BUYLIMIT);
      DeletePendingByType(OP_BUYSTOP);
   }
}

// Risk-based lot calculation using tick math
double CalculateLotsByRisk(double entryPrice, double stopPrice)
{
   double riskMoney = AccountBalance() * (InpRiskPercent/100.0);
   double slDistance = MathAbs(entryPrice - stopPrice);
   double ts = TickSize();
   double tv = TickValueMoney();
   if(ts <= 0 || tv <= 0 || slDistance <= 0)
      return 0.0;
   double ticks = slDistance / ts;
   double lossPerLot = ticks * tv; // uang per 1 lot jika kena SL
   if(lossPerLot <= 0) return 0.0;
   double lots = riskMoney / lossPerLot;
   return NormalizeLot(lots);
}

// ATR pada TF struktur
double GetATR(int periodATR)
{
   double atr = iATR(Symbol(), InpStructureTF, periodATR, 0);
   if(atr <= 0)
   {
      // fallback: estimasi ATR sederhana jika indikator tak tersedia
      double high0 = iHigh(Symbol(), InpStructureTF, 0);
      double low0  = iLow(Symbol(), InpStructureTF, 0);
      atr = MathAbs(high0 - low0) * 0.5;
   }
   return atr;
}

bool IsBearish(double o, double c) { return c < o; }
bool IsBullish(double o, double c) { return c > o; }

// Fractal swing detection
bool IsSwingHighTF(int barIndex, int left, int right)
{
   double h = iHigh(Symbol(), InpStructureTF, barIndex);
   for(int i=1; i<=left; i++) if(iHigh(Symbol(), InpStructureTF, barIndex+i) >= h) return false;
   for(int j=1; j<=right; j++) if(iHigh(Symbol(), InpStructureTF, barIndex-j) > h) return false;
   return true;
}

bool IsSwingLowTF(int barIndex, int left, int right)
{
   double l = iLow(Symbol(), InpStructureTF, barIndex);
   for(int i=1; i<=left; i++) if(iLow(Symbol(), InpStructureTF, barIndex+i) <= l) return false;
   for(int j=1; j<=right; j++) if(iLow(Symbol(), InpStructureTF, barIndex-j) < l) return false;
   return true;
}

// Temukan BOS terbaru dan OB yang relevan
bool FindLastBOSAndOB(MarketBias &biasOut, OrderBlockZone &zoneOut)
{
   biasOut = Bias_None;
   zoneOut.isValid = false;

   int bars = iBars(Symbol(), InpStructureTF);
   if(bars < 100) return false;

   int lastSwingHigh = -1;
   int lastSwingLow  = -1;
   datetime lastSwingHighTime = 0;
   datetime lastSwingLowTime  = 0;

   // Cari swing dalam 500 bar terakhir (atau semua jika lebih kecil)
   int scan = MathMin(bars-10, 500);
   for(int i=scan; i>=5; i--)
   {
      if(lastSwingHigh < 0 && IsSwingHighTF(i, InpSwingLeft, InpSwingRight))
      {
         lastSwingHigh = i;
         lastSwingHighTime = iTime(Symbol(), InpStructureTF, i);
      }
      if(lastSwingLow < 0 && IsSwingLowTF(i, InpSwingLeft, InpSwingRight))
      {
         lastSwingLow = i;
         lastSwingLowTime = iTime(Symbol(), InpStructureTF, i);
      }
      if(lastSwingHigh >= 0 && lastSwingLow >= 0) break;
   }

   if(lastSwingHigh < 0 || lastSwingLow < 0) return false;

   // Deteksi BOS: apakah ada close yang menembus swing terbaru
   int bosIndexUp = -1;
   int bosIndexDn = -1;

   double swingHighPrice = iHigh(Symbol(), InpStructureTF, lastSwingHigh);
   double swingLowPrice  = iLow(Symbol(), InpStructureTF, lastSwingLow);

   // Scan bar lebih baru sampai bar 1 (bar 0 masih berjalan)
   for(int j=lastSwingHigh; j>=1; j--)
   {
      double closeJ = iClose(Symbol(), InpStructureTF, j);
      if(closeJ > swingHighPrice)
      {
         bosIndexUp = j; // BOS ke atas
         break;
      }
   }
   for(int k=lastSwingLow; k>=1; k--)
   {
      double closeK = iClose(Symbol(), InpStructureTF, k);
      if(closeK < swingLowPrice)
      {
         bosIndexDn = k; // BOS ke bawah
         break;
      }
   }

   if(bosIndexUp < 0 && bosIndexDn < 0) return false;

   // Pilih BOS paling terbaru (waktu terbesar = index terkecil? iTime menurun dengan index naik)
   // Pada MT4, barIndex kecil = lebih baru. Jadi pilih index lebih kecil
   bool useBull = false;
   if(bosIndexUp >= 0 && bosIndexDn >= 0)
      useBull = (bosIndexUp < bosIndexDn);
   else if(bosIndexUp >= 0)
      useBull = true;
   else
      useBull = false;

   int bosIndex = useBull ? bosIndexUp : bosIndexDn;
   biasOut = useBull ? Bias_Bullish : Bias_Bearish;

   // Identifikasi OB: last opposing candle sebelum BOS
   int searchFrom = bosIndex + 1; // bar sebelum BOS (lebih ke masa lalu)
   int obIndex = -1;
   for(int t=searchFrom; t<=searchFrom+10 && t < bars-1; t++)
   {
      double o = iOpen(Symbol(), InpStructureTF, t);
      double c = iClose(Symbol(), InpStructureTF, t);
      if(useBull && IsBearish(o,c)) { obIndex = t; break; }
      if(!useBull && IsBullish(o,c)) { obIndex = t; break; }
   }

   if(obIndex < 0)
   {
      // fallback: pakai candle sebelum BOS jika tidak ketemu
      obIndex = MathMin(searchFrom, bars-2);
   }

   double oOB = iOpen(Symbol(), InpStructureTF, obIndex);
   double cOB = iClose(Symbol(), InpStructureTF, obIndex);
   double hOB = iHigh(Symbol(), InpStructureTF, obIndex);
   double lOB = iLow(Symbol(), InpStructureTF, obIndex);
   datetime tOB = iTime(Symbol(), InpStructureTF, obIndex);

   // Entry di 50% body dari candle OB
   double bodyMid = (oOB + cOB) / 2.0;

   double entryPrice = bodyMid;
   double rawStop;
   if(useBull)
   {
      // SL di bawah low OB - buffer
      rawStop = lOB - InpSLExtraPoints * Point;
   }
   else
   {
      // SL di atas high OB + buffer
      rawStop = hOB + InpSLExtraPoints * Point;
   }

   // ATR minimum SL distance
   double atr = GetATR(InpATRPeriod);
   double desiredMinDistance = atr * InpATRMultiplierSL;
   double currentDistance = MathAbs(entryPrice - rawStop);
   if(currentDistance < desiredMinDistance)
   {
      if(useBull) rawStop = entryPrice - desiredMinDistance;
      else        rawStop = entryPrice + desiredMinDistance;
   }

   zoneOut.isValid   = true;
   zoneOut.isBullish = useBull;
   zoneOut.entryPrice= entryPrice;
   zoneOut.stopPrice = rawStop;
   zoneOut.atr       = atr;
   zoneOut.obCandle.open  = oOB;
   zoneOut.obCandle.high  = hOB;
   zoneOut.obCandle.low   = lOB;
   zoneOut.obCandle.close = cOB;
   zoneOut.obCandle.time  = tOB;
   zoneOut.obCandle.index = obIndex;

   return true;
}

// Create/modify pending order for given direction
void EnsurePendingForZone(const OrderBlockZone &zone)
{
   if(!zone.isValid) return;

   double entry = NormalizeDouble(zone.entryPrice, Digits);
   double stop  = NormalizeDouble(zone.stopPrice, Digits);
   double riskDistance = MathAbs(entry - stop);
   if(riskDistance <= (Point * (StopLevelPoints()+2)))
   {
      Print("Risk distance too small vs stop level. Skipping pending.");
      return;
   }

   // Hitung TP by RR
   double tp;
   if(zone.isBullish) tp = entry + InpRiskReward * riskDistance + InpTPBufferPoints*Point;
   else               tp = entry - InpRiskReward * riskDistance - InpTPBufferPoints*Point;
   tp = NormalizeDouble(tp, Digits);

   // Lot
   double lots = CalculateLotsByRisk(entry, stop);
   if(lots < MinLot())
   {
      Print("Calculated lots too small: ", DoubleToString(lots,2), " < MinLot ", DoubleToString(MinLot(),2));
      return;
   }

   int desiredType = zone.isBullish ? OP_BUYLIMIT : OP_SELLLIMIT;

   // Batasi jumlah order
   if(CountAllOurOrders() >= InpMaxTotalOrders)
   {
      Print("Max total orders reached. Skipping new pending.");
      return;
   }

   // Cek sudah ada pending searah
   int existingTicket = -1;
   int countSide = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() == desiredType)
      {
         countSide++;
         existingTicket = OrderTicket();
      }
   }

   datetime expiry = TimeCurrent() + InpPendingExpiryHours * 3600;

   if(InpOnePendingPerSide && countSide > 0 && existingTicket > 0)
   {
      // Modify jika beda signifikan
      if(OrderSelect(existingTicket, SELECT_BY_TICKET))
      {
         bool needModify = (MathAbs(OrderOpenPrice() - entry) > 3*Point) ||
                           (MathAbs(OrderStopLoss()  - stop)  > 3*Point) ||
                           (MathAbs(OrderTakeProfit()- tp)    > 3*Point);
         if(needModify)
         {
            if(!OrderModify(existingTicket, entry, stop, tp, expiry, clrDodgerBlue))
            {
               Print("Failed to modify pending order ", existingTicket, " Err:", GetLastError());
               ResetLastError();
            }
            else
            {
               Print("Modified pending order #", existingTicket, " @", DoubleToString(entry,Digits));
            }
         }
      }
      return;
   }

   // Kirim pending baru
   int ticket = OrderSend(Symbol(), desiredType, lots, entry, InpSlippagePoints, stop, tp,
                          "SMC_OB", InpMagicNumber, expiry, zone.isBullish ? clrBlue : clrRed);
   if(ticket < 0)
   {
      Print("OrderSend pending failed: ", GetLastError());
      ResetLastError();
   }
   else
   {
      Print("Placed ", (zone.isBullish?"BuyLimit":"SellLimit"), " #", ticket, " lots=", DoubleToString(lots,2),
            " entry=", DoubleToString(entry,Digits), " SL=", DoubleToString(stop,Digits), " TP=", DoubleToString(tp,Digits));
   }
}

void ManageOpenPositions()
{
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;

      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;

      double entry = OrderOpenPrice();
      double sl    = OrderStopLoss();
      double tp    = OrderTakeProfit();
      double price = (type==OP_BUY) ? Bid : Ask;
      double risk  = MathAbs(entry - sl);

      // Move to BE
      if(InpMoveToBreakEven && risk > 0)
      {
         double profitMove = MathAbs(price - entry);
         if(profitMove >= InpBreakEvenAtR * risk)
         {
            double newSL = entry;
            if(type==OP_BUY && newSL > sl + 2*Point)
            {
               OrderModify(OrderTicket(), entry, NormalizeDouble(newSL,Digits), tp, 0, clrGreen);
            }
            else if(type==OP_SELL && newSL < sl - 2*Point)
            {
               OrderModify(OrderTicket(), entry, NormalizeDouble(newSL,Digits), tp, 0, clrGreen);
            }
         }
      }

      // ATR trailing
      if(InpUseATRTrailing)
      {
         double atr = GetATR(InpATRPeriod);
         double trailDist = atr * InpATRTrailMultiplier;
         if(type==OP_BUY)
         {
            double trailSL = price - trailDist;
            if(trailSL > sl + 2*Point)
               OrderModify(OrderTicket(), entry, NormalizeDouble(trailSL,Digits), tp, 0, clrOrange);
         }
         else if(type==OP_SELL)
         {
            double trailSL = price + trailDist;
            if(trailSL < sl - 2*Point)
               OrderModify(OrderTicket(), entry, NormalizeDouble(trailSL,Digits), tp, 0, clrOrange);
         }
      }
   }
}

// ==========================
// MT4 Event Handlers
// ==========================
int OnInit()
{
   if(!SymbolIsAllowed())
   {
      Print("Symbol filter active. EA disabled on ", Symbol());
   }
   return(INIT_SUCCEEDED);
}

int OnDeinit()
{
   return(0);
}

int start()
{
   if(!SymbolIsAllowed()) return(0);
   if(!WithinTradingHours()) return(0);
   if(SpreadPoints() > InpMaxSpreadPoints) return(0);

   // Kelola posisi berjalan
   ManageOpenPositions();

   // Re-kalkulasi SMC zone secara periodik
   if(IsNewRecalcMoment())
   {
      MarketBias bias;
      OrderBlockZone zone;
      bool ok = FindLastBOSAndOB(bias, zone);
      if(ok && zone.isValid)
      {
         // Hapus pending berlawanan jika ada flip
         if(g_lastBias != Bias_None && bias != g_lastBias)
            DeleteAllOppositePendings(bias);

         g_lastBias = bias;
         g_lastZone = zone;

         // Tempatkan / modifikasi pending di zona
         EnsurePendingForZone(zone);
      }
      g_lastCalcTime = TimeCurrent();
   }

   return(0);
}