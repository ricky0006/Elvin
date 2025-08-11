#property strict
#property copyright "SMC Limit EA"
#property link      "https://"
#property version   "1.00"
#property description "EA SMC (MQL5): BuyLimit/SellLimit di 50% OB setelah BOS, RR & ATR SL/TP, filter dan manajemen posisi untuk XAUUSD."

#include <Trade/Trade.mqh>
CTrade trade;

// ==========================
// Input Parameters
// ==========================
input string InpSymbolMustContain     = "XAU";      // Jalankan hanya jika simbol mengandung string ini (kosongkan untuk semua)
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
input int    InpMaxTotalOrders        = 2;          // Total order (pending + posisi) maksimum

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
   int index;
};

struct OrderBlockZone
{
   bool    isValid;
   bool    isBullish;
   CandleInfo obCandle;
   double  entryPrice;
   double  stopPrice;
   double  atr;
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
   return StringFind(_Symbol, InpSymbolMustContain, 0) >= 0;
}

int SpreadPoints()
{
   long spread = 0;
   if(!SymbolInfoInteger(_Symbol, SYMBOL_SPREAD, spread)) return 0;
   return (int)spread;
}

int StopLevelPoints()
{
   long stopLevel = 0;
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stopLevel)) return 0;
   return (int)stopLevel;
}

double MinLot()
{
   double v; SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, v); return v;
}

double MaxLot()
{
   double v; SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, v); return v;
}

double LotStep()
{
   double v; SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, v); return v;
}

bool WithinTradingHours()
{
   if(!InpUseTradingHours) return true;
   int h = TimeHour(TimeCurrent());
   if(InpStartHour <= InpEndHour)
      return (h >= InpStartHour && h < InpEndHour);
   return (h >= InpStartHour || h < InpEndHour);
}

bool IsNewRecalcMoment()
{
   if(g_lastCalcTime == 0) return true;
   return (TimeCurrent() - g_lastCalcTime) >= InpRecalcEverySeconds;
}

double NormalizeLot(double lots)
{
   double step = LotStep();
   if(step <= 0) step = 0.01;
   double normalized = MathFloor(lots/step)*step;
   normalized = MathMax(normalized, MinLot());
   normalized = MathMin(normalized, MaxLot());
   return NormalizeDouble(normalized, 2);
}

// Count our current pending orders and positions
int CountOurPendingByType(ENUM_ORDER_TYPE type)
{
   int count = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_INDEX)) continue;
      string sym; long magicL; long typeL;
      OrderGetString(ORDER_SYMBOL, sym);
      OrderGetInteger(ORDER_MAGIC, magicL);
      OrderGetInteger(ORDER_TYPE, typeL);
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)typeL;
      ulong magic = (ulong)magicL;
      if(sym == _Symbol && magic == (ulong)InpMagicNumber && t == type) count++;
   }
   return count;
}

int CountOurPendingAll()
{
   int count = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_INDEX)) continue;
      string sym; long magicL;
      OrderGetString(ORDER_SYMBOL, sym);
      OrderGetInteger(ORDER_MAGIC, magicL);
      ulong magic = (ulong)magicL;
      if(sym == _Symbol && magic == (ulong)InpMagicNumber) count++;
   }
   return count;
}

int CountOurPositions()
{
   int count = 0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(!PositionSelectByIndex(i)) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(sym == _Symbol && magic == InpMagicNumber) count++;
   }
   return count;
}

int CountAllOurOrders()
{
   return CountOurPendingAll() + CountOurPositions();
}

void DeletePendingByType(ENUM_ORDER_TYPE type)
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_INDEX)) continue;
      string sym; long magicL; long typeL; long ticketL;
      OrderGetString(ORDER_SYMBOL, sym);
      OrderGetInteger(ORDER_MAGIC, magicL);
      OrderGetInteger(ORDER_TYPE, typeL);
      OrderGetInteger(ORDER_TICKET, ticketL);
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)typeL;
      ulong magic = (ulong)magicL;
      ulong ticket = (ulong)ticketL;
      if(sym != _Symbol || magic != (ulong)InpMagicNumber) continue;
      if(t != type) continue;
      if(!trade.OrderDelete((ulong)ticket))
      {
         Print("Failed to delete pending order ", (long)ticket, " Err:", GetLastError());
         ResetLastError();
      }
   }
}

void DeleteAllOppositePendings(MarketBias bias)
{
   if(!InpDeleteOppositePending) return;
   if(bias == Bias_Bullish)
   {
     DeletePendingByType(ORDER_TYPE_SELL_LIMIT);
   }
   else if(bias == Bias_Bearish)
   {
     DeletePendingByType(ORDER_TYPE_BUY_LIMIT);
   }
}

// Risk-based lot calculation using tick math
double CalculateLotsByRisk(double entryPrice, double stopPrice)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent/100.0);
   double slDistance = MathAbs(entryPrice - stopPrice);
   if(slDistance <= 0) return 0.0;
   double tickSize, tickValue;
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tickSize);
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE, tickValue);
   if(tickSize <= 0 || tickValue <= 0) return 0.0;
   double ticks = slDistance / tickSize;
   double lossPerLot = ticks * tickValue;
   if(lossPerLot <= 0) return 0.0;
   double lots = riskMoney / lossPerLot;
   return NormalizeLot(lots);
}

// ATR on chosen TF
int g_atrHandle = INVALID_HANDLE;
int g_atrTF = -1;
int g_atrPeriod = -1;

double GetATR(int periodATR)
{
   if(g_atrHandle == INVALID_HANDLE || g_atrTF != (int)InpStructureTF || g_atrPeriod != periodATR)
   {
      if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
      g_atrHandle = iATR(_Symbol, InpStructureTF, periodATR);
      g_atrTF = (int)InpStructureTF;
      g_atrPeriod = periodATR;
   }
   if(g_atrHandle == INVALID_HANDLE) return 0.0;
   double buf[];
   if(CopyBuffer(g_atrHandle, 0, 0, 2, buf) < 1) return 0.0;
   return buf[0];
}

bool IsBearish(double o, double c) { return c < o; }
bool IsBullish(double o, double c) { return c > o; }

bool IsSwingHighTF(int barIndex, int left, int right)
{
   double h = iHigh(_Symbol, InpStructureTF, barIndex);
   for(int i=1; i<=left; i++) if(iHigh(_Symbol, InpStructureTF, barIndex+i) >= h) return false;
   for(int j=1; j<=right; j++) if(iHigh(_Symbol, InpStructureTF, barIndex-j) > h) return false;
   return true;
}

bool IsSwingLowTF(int barIndex, int left, int right)
{
   double l = iLow(_Symbol, InpStructureTF, barIndex);
   for(int i=1; i<=left; i++) if(iLow(_Symbol, InpStructureTF, barIndex+i) <= l) return false;
   for(int j=1; j<=right; j++) if(iLow(_Symbol, InpStructureTF, barIndex-j) < l) return false;
   return true;
}

bool FindLastBOSAndOB(MarketBias &biasOut, OrderBlockZone &zoneOut)
{
   biasOut = Bias_None;
   zoneOut.isValid = false;

   int bars = iBars(_Symbol, InpStructureTF);
   if(bars < 100) return false;

   int lastSwingHigh = -1;
   int lastSwingLow  = -1;

   int scan = MathMin(bars-10, 500);
   for(int i=scan; i>=5; i--)
   {
      if(lastSwingHigh < 0 && IsSwingHighTF(i, InpSwingLeft, InpSwingRight))
         lastSwingHigh = i;
      if(lastSwingLow < 0 && IsSwingLowTF(i, InpSwingLeft, InpSwingRight))
         lastSwingLow = i;
      if(lastSwingHigh >= 0 && lastSwingLow >= 0) break;
   }

   if(lastSwingHigh < 0 || lastSwingLow < 0) return false;

   int bosIndexUp = -1;
   int bosIndexDn = -1;

   double swingHighPrice = iHigh(_Symbol, InpStructureTF, lastSwingHigh);
   double swingLowPrice  = iLow(_Symbol, InpStructureTF, lastSwingLow);

   for(int j=lastSwingHigh; j>=1; j--)
   {
      double closeJ = iClose(_Symbol, InpStructureTF, j);
      if(closeJ > swingHighPrice) { bosIndexUp = j; break; }
   }
   for(int k=lastSwingLow; k>=1; k--)
   {
      double closeK = iClose(_Symbol, InpStructureTF, k);
      if(closeK < swingLowPrice) { bosIndexDn = k; break; }
   }

   if(bosIndexUp < 0 && bosIndexDn < 0) return false;

   bool useBull;
   if(bosIndexUp >= 0 && bosIndexDn >= 0) useBull = (bosIndexUp < bosIndexDn);
   else if(bosIndexUp >= 0) useBull = true; else useBull = false;

   int bosIndex = useBull ? bosIndexUp : bosIndexDn;
   biasOut = useBull ? Bias_Bullish : Bias_Bearish;

   int searchFrom = bosIndex + 1;
   int obIndex = -1;
   for(int t=searchFrom; t<=searchFrom+10 && t < bars-1; t++)
   {
      double o = iOpen(_Symbol, InpStructureTF, t);
      double c = iClose(_Symbol, InpStructureTF, t);
      if(useBull && IsBearish(o,c)) { obIndex = t; break; }
      if(!useBull && IsBullish(o,c)) { obIndex = t; break; }
   }
   if(obIndex < 0) obIndex = MathMin(searchFrom, bars-2);

   double oOB = iOpen(_Symbol, InpStructureTF, obIndex);
   double cOB = iClose(_Symbol, InpStructureTF, obIndex);
   double hOB = iHigh(_Symbol, InpStructureTF, obIndex);
   double lOB = iLow(_Symbol, InpStructureTF, obIndex);
   datetime tOB = iTime(_Symbol, InpStructureTF, obIndex);

   double bodyMid = (oOB + cOB) / 2.0;
   double entryPrice = bodyMid;
   double rawStop;
   if(useBull) rawStop = lOB - InpSLExtraPoints * _Point; else rawStop = hOB + InpSLExtraPoints * _Point;

   double atr = GetATR(InpATRPeriod);
   double desiredMinDistance = atr * InpATRMultiplierSL;
   double currentDistance = MathAbs(entryPrice - rawStop);
   if(currentDistance < desiredMinDistance)
   {
      if(useBull) rawStop = entryPrice - desiredMinDistance; else rawStop = entryPrice + desiredMinDistance;
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

ulong FindExistingPendingOfType(ENUM_ORDER_TYPE type)
{
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_INDEX)) continue;
      string sym; long magicL; long typeL; long ticketL;
      OrderGetString(ORDER_SYMBOL, sym);
      OrderGetInteger(ORDER_MAGIC, magicL);
      OrderGetInteger(ORDER_TYPE, typeL);
      OrderGetInteger(ORDER_TICKET, ticketL);
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)typeL;
      ulong magic = (ulong)magicL;
      ulong ticket = (ulong)ticketL;
      if(sym == _Symbol && magic == (ulong)InpMagicNumber && t == type)
         return ticket;
   }
   return 0;
}

void EnsurePendingForZone(const OrderBlockZone &zone)
{
   if(!zone.isValid) return;

   double entry = NormalizeDouble(zone.entryPrice, _Digits);
   double stop  = NormalizeDouble(zone.stopPrice, _Digits);
   double riskDistance = MathAbs(entry - stop);
   if(riskDistance <= (_Point * (StopLevelPoints()+2)))
   {
      Print("Risk distance too small vs stop level. Skipping pending.");
      return;
   }

   double tp;
   if(zone.isBullish) tp = entry + InpRiskReward * riskDistance + InpTPBufferPoints*_Point;
   else               tp = entry - InpRiskReward * riskDistance - InpTPBufferPoints*_Point;
   tp = NormalizeDouble(tp, _Digits);

   double lots = CalculateLotsByRisk(entry, stop);
   if(lots < MinLot())
   {
      Print("Calculated lots too small: ", DoubleToString(lots,2), " < MinLot ", DoubleToString(MinLot(),2));
      return;
   }

   ENUM_ORDER_TYPE desiredType = zone.isBullish ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;

   if(CountAllOurOrders() >= InpMaxTotalOrders)
   {
      Print("Max total orders reached. Skipping new pending.");
      return;
   }

   ulong existingTicket = 0;
   int countSide = CountOurPendingByType(desiredType);
   if(InpOnePendingPerSide && countSide > 0)
      existingTicket = FindExistingPendingOfType(desiredType);

   datetime expiry = TimeCurrent() + InpPendingExpiryHours * 3600;

   trade.SetExpertMagicNumber(InpMagicNumber);

   if(existingTicket > 0)
   {
      if(!OrderSelect((ulong)existingTicket)) return;
      double curPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      double curSL    = OrderGetDouble(ORDER_SL);
      double curTP    = OrderGetDouble(ORDER_TP);
      datetime curExp = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      bool needModify = (MathAbs(curPrice - entry) > 3*_Point) || (MathAbs(curSL - stop) > 3*_Point) || (MathAbs(curTP - tp) > 3*_Point) || (curExp != expiry);
      if(needModify)
      {
         if(!trade.OrderModify((ulong)existingTicket, entry, stop, tp, expiry))
         {
            Print("Failed to modify pending order ", (long)existingTicket, " Err:", GetLastError());
            ResetLastError();
         }
         else
         {
            Print("Modified pending order #", (long)existingTicket, " @", DoubleToString(entry,_Digits));
         }
      }
      return;
   }

   bool sent = false;
   if(zone.isBullish)
      sent = trade.BuyLimit(lots, entry, _Symbol, stop, tp, ORDER_TIME_SPECIFIED, expiry, "SMC_OB");
   else
      sent = trade.SellLimit(lots, entry, _Symbol, stop, tp, ORDER_TIME_SPECIFIED, expiry, "SMC_OB");

   if(!sent)
   {
      Print("OrderSend pending failed: ", GetLastError());
      ResetLastError();
   }
   else
   {
      Print("Placed ", (zone.isBullish?"BuyLimit":"SellLimit"), " lots=", DoubleToString(lots,2),
            " entry=", DoubleToString(entry,_Digits), " SL=", DoubleToString(stop,_Digits), " TP=", DoubleToString(tp,_Digits));
   }
}

void ManageOpenPositions()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(!PositionSelectByIndex(i)) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(sym != _Symbol || magic != InpMagicNumber) continue;

      long type = (long)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double price = (type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double risk  = MathAbs(entry - sl);

      if(InpMoveToBreakEven && risk > 0)
      {
         double profitMove = MathAbs(price - entry);
         if(profitMove >= InpBreakEvenAtR * risk)
         {
            double newSL = entry;
            if(type==POSITION_TYPE_BUY && newSL > sl + 2*_Point)
               trade.PositionModify(_Symbol, NormalizeDouble(newSL,_Digits), tp);
            else if(type==POSITION_TYPE_SELL && newSL < sl - 2*_Point)
               trade.PositionModify(_Symbol, NormalizeDouble(newSL,_Digits), tp);
         }
      }

      if(InpUseATRTrailing)
      {
         double atr = GetATR(InpATRPeriod);
         double trailDist = atr * InpATRTrailMultiplier;
         if(type==POSITION_TYPE_BUY)
         {
            double trailSL = price - trailDist;
            if(trailSL > sl + 2*_Point)
               trade.PositionModify(_Symbol, NormalizeDouble(trailSL,_Digits), tp);
         }
         else if(type==POSITION_TYPE_SELL)
         {
            double trailSL = price + trailDist;
            if(trailSL < sl - 2*_Point)
               trade.PositionModify(_Symbol, NormalizeDouble(trailSL,_Digits), tp);
         }
      }
   }
}

// ==========================
// Event Handlers
// ==========================
int OnInit()
{
   if(!SymbolIsAllowed())
      Print("Symbol filter active. EA disabled on ", _Symbol);
   trade.SetExpertMagicNumber(InpMagicNumber);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   if(!SymbolIsAllowed()) return;
   if(!WithinTradingHours()) return;
   if(SpreadPoints() > InpMaxSpreadPoints) return;

   ManageOpenPositions();

   if(IsNewRecalcMoment())
   {
      MarketBias bias;
      OrderBlockZone zone;
      bool ok = FindLastBOSAndOB(bias, zone);
      if(ok && zone.isValid)
      {
         if(g_lastBias != Bias_None && bias != g_lastBias)
            DeleteAllOppositePendings(bias);

         g_lastBias = bias;
         g_lastZone = zone;

         EnsurePendingForZone(zone);
      }
      g_lastCalcTime = TimeCurrent();
   }
}