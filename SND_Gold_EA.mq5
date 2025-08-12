//+------------------------------------------------------------------+
//|                                                SND_Gold_EA.mq5  |
//|                     Supply & Demand with Averaging + Hedging     |
//|                                      Designed for Gold (XAUUSD)  |
//+------------------------------------------------------------------+
#property copyright "OpenAI"
#property link      "https://openai.com"
#property version   "1.000"
#property strict
#property description "EA berbasis Supply & Demand dengan averaging dan hedging, dilengkapi dashboard."

#include <Trade/Trade.mqh>

//============================ Inputs ==========================================
input string   InpEaName                      = "SND Gold EA"; // Nama EA
input string   InpTradeSymbol                 = "";            // Simbol trading (kosong=chart symbol)
input long     InpMagicNumber                 = 24082025;       // Magic Number
input ENUM_TIMEFRAMES InpSignalTimeframe      = PERIOD_M15;     // Timeframe sinyal

// Entry & SND
input int      InpFractalDepth                = 5;              // Fractal depth untuk S/R
input double   InpZoneATRMultiplier           = 0.5;            // Lebar zona SND = ATR * multiplier
input int      InpATRPeriod                   = 14;             // ATR periode untuk zona & filter volatilitas
input double   InpMinATRPoints                = 100;            // Minimum ATR (points) agar entry (filter volatilitas)
input bool     InpUsePinBarRejection          = true;           // Konfirmasi candle pin bar
input bool     InpUseEngulfingRejection       = true;           // Konfirmasi candle engulfing

enum ZoneRuleMode { ZONE_FRACTAL_ATR=0, ZONE_PIVOT_HL=1, ZONE_ORDER_BLOCK=2 };
input ZoneRuleMode InpZoneRule                = ZONE_FRACTAL_ATR; // Mode perhitungan zona SND
input int      InpZoneLookupBars              = 300;            // Maks bar untuk cari zona
input int      InpPivotLeftRight              = 3;              // Pivot HL: jumlah bar kiri/kanan
input double   InpOBPadATRMult                = 0.0;            // Order Block: padding zona = ATR * mult

// Risk & Positioning
input double   InpInitialLot                  = 0.01;           // Lot awal
input bool     InpUseLotMultiplier            = true;           // Gunakan martingale lot multiplier untuk averaging
input double   InpLotMultiplier               = 1.5;            // Lot multiplier untuk averaging
input double   InpMaxTotalLot                 = 5.0;            // Batas total lot untuk simbol ini
input int      InpMaxPositionsPerDirection    = 10;             // Batas posisi per arah

// Grid / Averaging
input bool     InpUseATRGridStep              = true;           // Grid step berbasis ATR
input int      InpGridStepPoints              = 300;            // Grid step (points) jika tidak pakai ATR
input double   InpGridATRMultiplier           = 0.25;           // Grid step = ATR * multiplier
// Profit-based Averaging (scale-in)
input bool     InpEnableProfitAveraging       = true;           // Tambah posisi saat profit (scale-in)
input bool     InpProfitGridUseATR            = true;           // Step profit berbasis ATR
input int      InpProfitGridStepPoints        = 300;            // Step profit (points) jika tidak pakai ATR
input double   InpProfitGridATRMultiplier     = 0.30;           // Step profit = ATR * multiplier

// SL/TP & Exits
input bool     InpUseSLTP                     = true;           // Gunakan SL/TP dinamis
input double   InpSL_ATRMult                  = 1.8;            // SL = ATR * mult
input double   InpTP_ATRMult                  = 1.2;            // TP = ATR * mult
input bool     InpUseTrailingStop             = true;           // Trailing stop dinamis
input double   InpTrail_ATRMult               = 0.8;            // Trailing stop = ATR * mult

// Hedging
input bool     InpEnableHedge                 = true;           // Aktifkan hedging saat floating berat
input double   InpHedgeTriggerDDPercent       = 5.0;            // Trigger hedge saat DD >= % equity
input double   InpHedgeLotRatioToNet          = 1.0;            // Lot hedge = ratio * |lotBuy-lotSell|
input int      InpMaxHedgePositions           = 3;              // Maks posisi hedge

enum HedgeTriggerMode { HEDGE_ACCOUNT_DD_PERCENT=0, HEDGE_CYCLE_FLOAT_MONEY=1, HEDGE_CYCLE_DD_PERCENT=2 };
input HedgeTriggerMode InpHedgeTriggerMode    = HEDGE_CYCLE_DD_PERCENT; // Mode pemicu hedging
input double   InpHedgeCycleTriggerMoney      = -100.0;         // Trigger hedge bila floating cycle <= nilai ini (uang akun)
input double   InpHedgeCycleTriggerPercent    = 1.5;            // Trigger hedge bila |floating cycle| >= % equity

// Hedge Unlock (otomatis keluar dari kondisi lock)
input bool     InpEnableHedgeUnlock           = true;           // Aktifkan mekanisme unlock saat terkunci
input double   InpLockLotTolerance            = 0.01;           // Toleransi selisih lot agar dianggap lock
// Dynamic TP unlock
input bool     InpUnlockUseDynamicTP          = true;           // Gunakan TP dinamis berbasis ATR
input double   InpUnlockK_ATRProfit           = 0.6;            // Koefisien target profit dinamis (k)
input double   InpUnlockEquityCapPercent      = 0.4;            // Batas % equity untuk target profit (ambil lebih kecil)
// Midline break-even unlock
input bool     InpUnlockUseMidline            = true;           // Unlock saat harga kembali ke midpoint
input double   InpUnlockMidlineBufferATR      = 0.12;           // Buffer BE = ATR * mult
input int      InpUnlockMinLockBars           = 45;             // Minimum bar dalam kondisi lock sebelum midline unlock
// Partial release (opsional)
input bool     InpUnlockPartialEnabled        = false;          // Lepas sisi profit sebagian
input double   InpUnlockPartialATRMult        = 0.25;           // Ambang profit sisi = ATR * mult * lotSide
// Fail-safe time unlock
input int      InpUnlockFailSafeBars          = 100;            // Paksa unlock bila lock terlalu lama
input double   InpUnlockFailSafeAllowLoss     = -10.0;          // Batas loss (uang) yang masih diterima saat fail-safe
// Volatility gate
input bool     InpUnlockVolGateEnabled        = true;           // Hanya unlock saat volatilitas memadai
input double   InpUnlockVolGateATRRatio       = 1.2;            // ATR_now >= ratio * ATR_SMA(20)

// Basket TP (TP Money All)
input bool     InpEnableTPMoneyAll            = false;          // Aktifkan TP Money All (basket TP)
input double   InpTPMoneyAllAmount            = 100.0;          // Target profit uang (mata uang akun)
input bool     InpTPMoneyAllAllSymbols        = false;          // Hitung semua simbol dengan magic ini (true) atau hanya simbol EA (false)

// SND Zones Display
input bool     InpShowZones                   = true;           // Tampilkan zona Supply/Demand
input int      InpZoneHistoryBars             = 200;            // Panjang zona ke kiri (jumlah bar historis)
input int      InpZoneRightBars               = 20;             // Panjang zona ke kanan (bar ke depan)
input bool     InpZoneFill                    = true;           // Isi zona dengan warna transparan
input color    InpSupplyColor                 = clrTomato;      // Warna border zona Supply
input int      InpSupplyLineWidth             = 2;              // Ketebalan garis Supply
input int      InpSupplyFillAlpha             = 40;             // Transparansi isi Supply (0-255)
input color    InpDemandColor                 = clrLimeGreen;   // Warna border zona Demand
input int      InpDemandLineWidth             = 2;              // Ketebalan garis Demand
input int      InpDemandFillAlpha             = 40;             // Transparansi isi Demand (0-255)

// Filters
input int      InpMaxSpreadPoints             = 250;            // Maks spread (points)
input int      InpMaxSlippagePoints           = 50;             // Maks slippage (points)

// Misc
input bool     InpAllowBuy                    = true;           // Izinkan BUY
input bool     InpAllowSell                   = true;           // Izinkan SELL
input bool     InpOneEntryPerBar              = true;           // Batasi entry 1x tiap bar
input bool     InpRestrictInitialEntry        = true;           // OP awal hanya 1 sampai clear (kecuali averaging/hedging yg aktif)

//============================ Globals =========================================
CTrade         g_trade;
string         g_symbol;
double         g_point;
int            g_digits;
double         g_tickSize;
double         g_tickValue;
MqlTick        g_tick;
long           g_accountNumber;

// Cycle management
int            g_cycleId = 1;                 // Current cycle id
bool           g_cycleAdvancedOnThisLock = false;

// Indicator handles
int            g_handleATR = INVALID_HANDLE;
int            g_handleFractals = INVALID_HANDLE;

// State
datetime       g_lastBarTime = 0;
double         g_minFloatingSeen = 0.0; // paling negatif
bool           g_initialized = false;

// Label IDs
string         g_labelPrefix = "SND_GOLD_EA_DASH_";
string         g_zonePrefix  = "SND_GOLD_EA_ZONE_";

//============================ Utilities =======================================
double NormalizeLot(double lots)
{
   double lotStep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double v = MathMax(minLot, MathMin(maxLot, MathFloor(lots/lotStep)*lotStep));
   return v;
}

bool RefreshTick()
{
   if(!SymbolInfoTick(g_symbol, g_tick))
      return false;
   return true;
}

bool SpreadOk()
{
   double spreadPoints = (SymbolInfoInteger(g_symbol, SYMBOL_SPREAD));
   return (spreadPoints <= InpMaxSpreadPoints);
}

bool EnsureIndicators()
{
   if(g_handleATR == INVALID_HANDLE)
   {
      g_handleATR = iATR(g_symbol, InpSignalTimeframe, InpATRPeriod);
      if(g_handleATR == INVALID_HANDLE) return false;
   }
   if(g_handleFractals == INVALID_HANDLE)
   {
      g_handleFractals = iFractals(g_symbol, InpSignalTimeframe);
      if(g_handleFractals == INVALID_HANDLE) return false;
   }
   return true;
}

bool GetATR(double &atrPoints)
{
   if(!EnsureIndicators()) return false;
   double buff[];
   if(CopyBuffer(g_handleATR, 0, 0, 2, buff) <= 0)
      return false;
   double atrPrice = buff[0];
   atrPoints = atrPrice / g_point; // convert to points
   return true;
}

bool GetLastFractals(double &lastUpPrice, double &lastDownPrice)
{
   if(!EnsureIndicators()) return false;
   double upBuff[];   // buffer index 0 = up fractal per docs
   double dnBuff[];   // buffer index 1 = down fractal
   if(CopyBuffer(g_handleFractals, 0, 0, 200, upBuff) <= 0) return false;
   if(CopyBuffer(g_handleFractals, 1, 0, 200, dnBuff) <= 0) return false;

   lastUpPrice = 0.0;
   lastDownPrice = 0.0;

   for(int i=0;i<ArraySize(upBuff);i++)
   {
      if(upBuff[i] != 0.0) { lastUpPrice = upBuff[i]; break; }
   }
   for(int i=0;i<ArraySize(dnBuff);i++)
   {
      if(dnBuff[i] != 0.0) { lastDownPrice = dnBuff[i]; break; }
   }
   return (lastUpPrice>0.0 || lastDownPrice>0.0);
}

bool FindLastPivotHighLow(int leftRight, int lookbackBars, double &pivotHigh, double &pivotLow)
{
   pivotHigh = 0.0; pivotLow = 0.0;
   int maxShift = MathMax(leftRight+1, MathMin(lookbackBars, 1000));
   // search from most recent past candle
   for(int shift=leftRight+1; shift<=maxShift; ++shift)
   {
      bool isHigh = true; bool isLow = true;
      double h = iHigh(g_symbol, InpSignalTimeframe, shift);
      double l = iLow(g_symbol, InpSignalTimeframe, shift);
      if(h == 0 || l == 0) continue;
      for(int k=1; k<=leftRight; ++k)
      {
         double hk = iHigh(g_symbol, InpSignalTimeframe, shift-k);
         double hl = iHigh(g_symbol, InpSignalTimeframe, shift+k);
         if(!(h > hk && h > hl)) isHigh = false;

         double lk = iLow(g_symbol, InpSignalTimeframe, shift-k);
         double ll = iLow(g_symbol, InpSignalTimeframe, shift+k);
         if(!(l < lk && l < ll)) isLow = false;

         if(!isHigh && !isLow) break;
      }
      if(pivotHigh==0.0 && isHigh) pivotHigh = h;
      if(pivotLow==0.0 && isLow) pivotLow = l;
      if(pivotHigh>0.0 && pivotLow>0.0) break;
   }
   return (pivotHigh>0.0 || pivotLow>0.0);
}

bool FindLastOrderBlocks(int lookbackBars, double &supplyLow, double &supplyHigh, double &demandLow, double &demandHigh)
{
   supplyLow = supplyHigh = demandLow = demandHigh = 0.0;
   int maxShift = MathMin(lookbackBars, 1000);
   // Supply: last bearish engulfing body
   for(int shift=1; shift<=maxShift; ++shift)
   {
      if(IsBearishEngulfing(shift))
      {
         double o,h,l,c; GetCandle(shift,o,h,l,c);
         supplyLow = MathMin(o,c);
         supplyHigh = MathMax(o,c);
         break;
      }
   }
   // Demand: last bullish engulfing body
   for(int shift=1; shift<=maxShift; ++shift)
   {
      if(IsBullishEngulfing(shift))
      {
         double o,h,l,c; GetCandle(shift,o,h,l,c);
         demandLow = MathMin(o,c);
         demandHigh = MathMax(o,c);
         break;
      }
   }
   return (supplyHigh>0.0 || demandHigh>0.0);
}

bool ComputeZones(double &supLow, double &supHigh, double &demLow, double &demHigh)
{
   supLow=supHigh=demLow=demHigh=0.0;
   double atrPts; if(!GetATR(atrPts)) return false;
   double padPrice = PointsToPrice(atrPts * InpZoneATRMultiplier);

   if(InpZoneRule == ZONE_FRACTAL_ATR)
   {
     double upF=0, dnF=0; if(!GetLastFractals(upF, dnF)) return false;
     if(upF>0){ supLow = upF - padPrice; supHigh = upF + padPrice; }
     if(dnF>0){ demLow = dnF - padPrice; demHigh = dnF + padPrice; }
     return (supHigh>0.0 || demHigh>0.0);
   }
   else if(InpZoneRule == ZONE_PIVOT_HL)
   {
     double ph=0, pl=0; if(!FindLastPivotHighLow(InpPivotLeftRight, InpZoneLookupBars, ph, pl)) return false;
     if(ph>0){ supLow = ph - padPrice; supHigh = ph + padPrice; }
     if(pl>0){ demLow = pl - padPrice; demHigh = pl + padPrice; }
     return (supHigh>0.0 || demHigh>0.0);
   }
   else if(InpZoneRule == ZONE_ORDER_BLOCK)
   {
     double sL,sH,dL,dH; if(!FindLastOrderBlocks(InpZoneLookupBars, sL,sH,dL,dH)) return false;
     double obPad = PointsToPrice(atrPts * InpOBPadATRMult);
     if(sH>0){ supLow = MathMin(sL,sH) - obPad; supHigh = MathMax(sL,sH) + obPad; }
     if(dH>0){ demLow = MathMin(dL,dH) - obPad; demHigh = MathMax(dL,dH) + obPad; }
     return (supHigh>0.0 || demHigh>0.0);
   }
   return false;
}

void GetCandle(int shift, double &o, double &h, double &l, double &c)
{
   o = iOpen(g_symbol, InpSignalTimeframe, shift);
   h = iHigh(g_symbol, InpSignalTimeframe, shift);
   l = iLow(g_symbol, InpSignalTimeframe, shift);
   c = iClose(g_symbol, InpSignalTimeframe, shift);
}

bool IsBullishPinBar(int shift, double ratioThreshold = 2.0)
{
   double o,h,l,c; GetCandle(shift,o,h,l,c);
   double body = MathAbs(c-o);
   double lowerWick = o<c ? (o-l) : (c-l);
   double upperWick = h - MathMax(o,c);
   if(c <= o) return false;
   if(lowerWick <= 0) return false;
   if(lowerWick/body >= ratioThreshold && lowerWick > upperWick)
      return true;
   return false;
}

bool IsBearishPinBar(int shift, double ratioThreshold = 2.0)
{
   double o,h,l,c; GetCandle(shift,o,h,l,c);
   double body = MathAbs(c-o);
   double upperWick = h - MathMax(o,c);
   double lowerWick = MathMin(o,c) - l;
   if(c >= o) return false;
   if(upperWick <= 0) return false;
   if(upperWick/body >= ratioThreshold && upperWick > lowerWick)
      return true;
   return false;
}

bool IsBullishEngulfing(int shift)
{
   // shift candle engulfs previous candle bearish body
   double o1,h1,l1,c1; GetCandle(shift+1,o1,h1,l1,c1);
   double o0,h0,l0,c0; GetCandle(shift,o0,h0,l0,c0);
   if(c1 > o1 && c0 > o0) return false; // need prev bearish, current bullish
   if(!(c1 < o1 && c0 > o0)) return false;
   double prevBodyHigh = o1;
   double prevBodyLow  = c1;
   return (o0 <= prevBodyLow && c0 >= prevBodyHigh);
}

bool IsBearishEngulfing(int shift)
{
   double o1,h1,l1,c1; GetCandle(shift+1,o1,h1,l1,c1);
   double o0,h0,l0,c0; GetCandle(shift,o0,h0,l0,c0);
   if(c1 < o1 && c0 < o0) return false; // need prev bullish, current bearish
   if(!(c1 > o1 && c0 < o0)) return false;
   double prevBodyHigh = c1;
   double prevBodyLow  = o1;
   return (o0 >= prevBodyHigh && c0 <= prevBodyLow);
}

bool ConfirmBullishRejection()
{
   if(InpUsePinBarRejection && IsBullishPinBar(1)) return true;
   if(InpUseEngulfingRejection && IsBullishEngulfing(1)) return true;
   return false;
}

bool ConfirmBearishRejection()
{
   if(InpUsePinBarRejection && IsBearishPinBar(1)) return true;
   if(InpUseEngulfingRejection && IsBearishEngulfing(1)) return true;
   return false;
}

//====================== Position & PnL Helpers ================================
struct DirectionStats
{
   double totalLots;
   int    positionsCount;
   double totalProfit;
   double worstPrice;   // worst price for averaging reference
   double lastOpenPrice;// most recent open price in that direction
   double sumPriceVolume; // sum(price_open * volume)
   double avgOpenPrice;   // volume-weighted average open price
};

void ComputeDirectionStats(DirectionStats &buyStats, DirectionStats &sellStats, double &totalFloating)
{
   buyStats.totalLots = 0; buyStats.positionsCount = 0; buyStats.totalProfit = 0; buyStats.worstPrice = 0; buyStats.lastOpenPrice = 0; buyStats.sumPriceVolume=0; buyStats.avgOpenPrice=0;
   sellStats.totalLots = 0; sellStats.positionsCount = 0; sellStats.totalProfit = 0; sellStats.worstPrice = 0; sellStats.lastOpenPrice = 0; sellStats.sumPriceVolume=0; sellStats.avgOpenPrice=0;
   totalFloating = 0;

   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      long   mg  = (long)PositionGetInteger(POSITION_MAGIC);
      if(sym != g_symbol || mg != InpMagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double price  = PositionGetDouble(POSITION_PRICE_OPEN);
      double profit = PositionGetDouble(POSITION_PROFIT);

      totalFloating += profit;

      if(type == POSITION_TYPE_BUY)
      {
         buyStats.totalLots += volume;
         buyStats.positionsCount++;
         buyStats.totalProfit += profit;
         buyStats.lastOpenPrice = price;
         buyStats.sumPriceVolume += price * volume;
         if(buyStats.worstPrice == 0 || price > buyStats.worstPrice) buyStats.worstPrice = price; // worst for buy is highest
      }
      else if(type == POSITION_TYPE_SELL)
      {
         sellStats.totalLots += volume;
         sellStats.positionsCount++;
         sellStats.totalProfit += profit;
         sellStats.lastOpenPrice = price;
         sellStats.sumPriceVolume += price * volume;
         if(sellStats.worstPrice == 0 || price < sellStats.worstPrice) sellStats.worstPrice = price; // worst for sell is lowest
      }
   }
   if(buyStats.totalLots > 0) buyStats.avgOpenPrice = buyStats.sumPriceVolume / buyStats.totalLots;
   if(sellStats.totalLots > 0) sellStats.avgOpenPrice = sellStats.sumPriceVolume / sellStats.totalLots;
}

int CountHedgePositions()
{
   int cnt = 0;
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "HEDGE", 0) >= 0) cnt++;
   }
   return cnt;
}

int CountHedgePositionsForCycle(int cycleId)
{
   int cnt = 0;
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "HEDGE", 0) >= 0)
      {
         int cyc = ExtractCycleFromComment(comment);
         if(cyc == cycleId) cnt++;
      }
   }
   return cnt;
}

bool ShouldHedgeForCycle(int cycleId)
{
   DirectionStats buyStats, sellStats; double totalFloating;
   ComputeDirectionStatsForCycle(cycleId, buyStats, sellStats, totalFloating);
   if(buyStats.positionsCount==0 && sellStats.positionsCount==0) return false;

   if(InpHedgeTriggerMode == HEDGE_ACCOUNT_DD_PERCENT)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double ddPercent = (balance<=0) ? 0 : (MathMax(0.0, (balance - equity)) / balance * 100.0);
      return (ddPercent >= InpHedgeTriggerDDPercent);
   }
   else if(InpHedgeTriggerMode == HEDGE_CYCLE_FLOAT_MONEY)
   {
      return (totalFloating <= InpHedgeCycleTriggerMoney);
   }
   else if(InpHedgeTriggerMode == HEDGE_CYCLE_DD_PERCENT)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) return false;
      double ddPct = MathAbs(totalFloating) / equity * 100.0;
      return (ddPct >= InpHedgeCycleTriggerPercent && totalFloating < 0);
   }
   return false;
}

//============================ Trade Helpers ==================================
string MakeCycleComment(const string base)
{
   return base + " CYCLE:" + IntegerToString(g_cycleId);
}

int ExtractCycleFromComment(const string comment)
{
   int pos = StringFind(comment, "CYCLE:", 0);
   if(pos < 0) return 0;
   string sub = StringSubstr(comment, pos+6);
   return (int)StringToInteger(sub);
}

int DetectMaxCycleFromOpenPositions()
{
   int maxCycle = 0;
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      string cmt = PositionGetString(POSITION_COMMENT);
      int cyc = ExtractCycleFromComment(cmt);
      if(cyc > maxCycle) maxCycle = cyc;
   }
   return maxCycle;
}

bool HasEAOpenPositionsInCycle(int cycleId)
{
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      int cyc = ExtractCycleFromComment(PositionGetString(POSITION_COMMENT));
      if(cyc == cycleId) return true;
   }
   return false;
}

void ComputeDirectionStatsForCycle(int cycleId, DirectionStats &buyStats, DirectionStats &sellStats, double &totalFloating)
{
   buyStats.totalLots = 0; buyStats.positionsCount = 0; buyStats.totalProfit = 0; buyStats.worstPrice = 0; buyStats.lastOpenPrice = 0; buyStats.sumPriceVolume=0; buyStats.avgOpenPrice=0;
   sellStats.totalLots = 0; sellStats.positionsCount = 0; sellStats.totalProfit = 0; sellStats.worstPrice = 0; sellStats.lastOpenPrice = 0; sellStats.sumPriceVolume=0; sellStats.avgOpenPrice=0;
   totalFloating = 0;

   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      int cyc = ExtractCycleFromComment(PositionGetString(POSITION_COMMENT));
      if(cyc != cycleId) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double price  = PositionGetDouble(POSITION_PRICE_OPEN);
      double profit = PositionGetDouble(POSITION_PROFIT);

      totalFloating += profit;

      if(type == POSITION_TYPE_BUY)
      {
         buyStats.totalLots += volume;
         buyStats.positionsCount++;
         buyStats.totalProfit += profit;
         buyStats.lastOpenPrice = price;
         buyStats.sumPriceVolume += price * volume;
         if(buyStats.worstPrice == 0 || price > buyStats.worstPrice) buyStats.worstPrice = price;
      }
      else if(type == POSITION_TYPE_SELL)
      {
         sellStats.totalLots += volume;
         sellStats.positionsCount++;
         sellStats.totalProfit += profit;
         sellStats.lastOpenPrice = price;
         sellStats.sumPriceVolume += price * volume;
         if(sellStats.worstPrice == 0 || price < sellStats.worstPrice) sellStats.worstPrice = price;
      }
   }
   if(buyStats.totalLots > 0) buyStats.avgOpenPrice = buyStats.sumPriceVolume / buyStats.totalLots;
   if(sellStats.totalLots > 0) sellStats.avgOpenPrice = sellStats.sumPriceVolume / sellStats.totalLots;
}

void ManageCycleAdvance()
{
   // If current cycle becomes locked, advance to next cycle once
   DirectionStats b,s; double pf;
   ComputeDirectionStatsForCycle(g_cycleId, b, s, pf);
   if(IsLocked(b,s))
   {
      if(!g_cycleAdvancedOnThisLock)
      {
         g_cycleId++;
         g_cycleAdvancedOnThisLock = true;
         PrintFormat("[Cycle] Locked detected. Advancing to new cycle %d", g_cycleId);
      }
   }
   else
   {
      g_cycleAdvancedOnThisLock = false;
   }
}

bool OpenMarketOrder(ENUM_ORDER_TYPE orderType, double lots, double slPrice=0.0, double tpPrice=0.0, string comment="")
{
   lots = NormalizeLot(lots);
   if(lots <= 0) return false;

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpMaxSlippagePoints);

   string fullComment = MakeCycleComment(comment);

   bool ok = false;
   if(orderType == ORDER_TYPE_BUY)
      ok = g_trade.Buy(lots, g_symbol, 0.0, slPrice, tpPrice, fullComment);
   else if(orderType == ORDER_TYPE_SELL)
      ok = g_trade.Sell(lots, g_symbol, 0.0, slPrice, tpPrice, fullComment);

   return ok;
}

double PriceToPoints(double priceDistance)
{
   return priceDistance / g_point;
}

double PointsToPrice(double points)
{
   return points * g_point;
}

//=========================== Core Logic =======================================
bool HasEAOpenPositions()
{
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      return true; // ada posisi EA apapun (buy/sell/hedge)
   }
   return false;
}

void TryEntrySignals()
{
   if(InpOneEntryPerBar)
   {
      datetime ct = iTime(g_symbol, InpSignalTimeframe, 0);
      if(ct == g_lastBarTime) return; // already processed
   }

   // Restrict new base entries to one per cycle
   if(InpRestrictInitialEntry && HasEAOpenPositionsInCycle(g_cycleId))
      return;

   double atrPoints; if(!GetATR(atrPoints)) return;
   if(atrPoints < InpMinATRPoints) return; // low volatility filter

   // Compute zones based on rule
   double supLow=0,supHigh=0,demLow=0,demHigh=0;
   if(!ComputeZones(supLow,supHigh,demLow,demHigh)) return;

   // Current price reference
   if(!RefreshTick()) return;
   double bid = g_tick.bid;
   double ask = g_tick.ask;
   double mid = (bid+ask)/2.0;

   bool inDemand = (demHigh>0.0 && mid>=demLow && mid<=demHigh);
   bool inSupply = (supHigh>0.0 && mid>=supLow && mid<=supHigh);

   DirectionStats buyStats, sellStats; double totalFloating;
   ComputeDirectionStatsForCycle(g_cycleId, buyStats, sellStats, totalFloating);

   double lotBudgetLeft = MathMax(0.0, InpMaxTotalLot - (buyStats.totalLots + sellStats.totalLots));

   // Prepare SL/TP
   double slPriceBuy=0, tpPriceBuy=0, slPriceSell=0, tpPriceSell=0;
   if(InpUseSLTP)
   {
      double slPts = atrPoints * InpSL_ATRMult;
      double tpPts = atrPoints * InpTP_ATRMult;
      slPriceBuy = bid - PointsToPrice(slPts);
      tpPriceBuy = bid + PointsToPrice(tpPts);
      slPriceSell = ask + PointsToPrice(slPts);
      tpPriceSell = ask - PointsToPrice(tpPts);
   }

   if(SpreadOk())
   {
      if(InpAllowBuy && inDemand && ConfirmBullishRejection())
      {
         if(buyStats.positionsCount < InpMaxPositionsPerDirection && lotBudgetLeft > 0)
         {
            double lots = MathMin(InpInitialLot, lotBudgetLeft);
            if(OpenMarketOrder(ORDER_TYPE_BUY, lots, slPriceBuy, tpPriceBuy, "SND BUY"))
            {
               if(InpOneEntryPerBar) g_lastBarTime = iTime(g_symbol, InpSignalTimeframe, 0);
            }
         }
      }

      if(InpAllowSell && inSupply && ConfirmBearishRejection())
      {
         if(sellStats.positionsCount < InpMaxPositionsPerDirection && lotBudgetLeft > 0)
         {
            double lots = MathMin(InpInitialLot, lotBudgetLeft);
            if(OpenMarketOrder(ORDER_TYPE_SELL, lots, slPriceSell, tpPriceSell, "SND SELL"))
            {
               if(InpOneEntryPerBar) g_lastBarTime = iTime(g_symbol, InpSignalTimeframe, 0);
            }
         }
      }
   }
}

void ManageAveraging()
{
   double atrPoints; if(!GetATR(atrPoints)) return;
   double stepPts = InpUseATRGridStep ? MathMax(1.0, atrPoints * InpGridATRMultiplier) : InpGridStepPoints;
   double stepPtsProfit = InpEnableProfitAveraging ? (InpProfitGridUseATR ? MathMax(1.0, atrPoints * InpProfitGridATRMultiplier) : InpProfitGridStepPoints) : 0.0;

   DirectionStats buyStats, sellStats; double totalFloating;
   ComputeDirectionStatsForCycle(g_cycleId, buyStats, sellStats, totalFloating);

   if(!RefreshTick()) return;
   double bid = g_tick.bid;
   double ask = g_tick.ask;

   double lotBudgetLeft = MathMax(0.0, InpMaxTotalLot - (buyStats.totalLots + sellStats.totalLots));

   // Averaging BUY: add when price goes further down by step from last buy open price (adverse)
   if(InpAllowBuy && buyStats.positionsCount > 0 && buyStats.positionsCount < InpMaxPositionsPerDirection && lotBudgetLeft > 0)
   {
      double referencePrice = buyStats.lastOpenPrice; // most recent entry
      double adverseMovePts = PriceToPoints(referencePrice - ask);
      if(adverseMovePts >= stepPts)
      {
         double nextLot = InpUseLotMultiplier ? (InpInitialLot * MathPow(InpLotMultiplier, buyStats.positionsCount))
                                              : InpInitialLot;
         nextLot = MathMin(nextLot, lotBudgetLeft);

         double sl=0,tp=0;
         if(InpUseSLTP)
         {
            double slPts = atrPoints * InpSL_ATRMult;
            double tpPts = atrPoints * InpTP_ATRMult;
            sl = bid - PointsToPrice(slPts);
            tp = bid + PointsToPrice(tpPts);
         }
         OpenMarketOrder(ORDER_TYPE_BUY, nextLot, sl, tp, "AVG BUY");
         // refresh budget
         lotBudgetLeft = MathMax(0.0, InpMaxTotalLot - (buyStats.totalLots + sellStats.totalLots + nextLot));
      }

      // Profit-based scale-in for BUY
      if(InpEnableProfitAveraging && stepPtsProfit > 0.0 && lotBudgetLeft > 0)
      {
         double profitMovePts = PriceToPoints(bid - referencePrice);
         if(profitMovePts >= stepPtsProfit)
         {
            double nextLot = InpUseLotMultiplier ? (InpInitialLot * MathPow(InpLotMultiplier, buyStats.positionsCount))
                                                 : InpInitialLot;
            nextLot = MathMin(nextLot, lotBudgetLeft);

            double sl=0,tp=0;
            if(InpUseSLTP)
            {
               double slPts = atrPoints * InpSL_ATRMult;
               double tpPts = atrPoints * InpTP_ATRMult;
               sl = bid - PointsToPrice(slPts);
               tp = bid + PointsToPrice(tpPts);
            }
            OpenMarketOrder(ORDER_TYPE_BUY, nextLot, sl, tp, "SCALE BUY");
         }
      }
   }

   // Averaging SELL: add when price goes further up by step from last sell open price (adverse)
   if(InpAllowSell && sellStats.positionsCount > 0 && sellStats.positionsCount < InpMaxPositionsPerDirection && lotBudgetLeft > 0)
   {
      double referencePrice = sellStats.lastOpenPrice;
      double adverseMovePts = PriceToPoints(bid - referencePrice);
      if(adverseMovePts >= stepPts)
      {
         double nextLot = InpUseLotMultiplier ? (InpInitialLot * MathPow(InpLotMultiplier, sellStats.positionsCount))
                                              : InpInitialLot;
         nextLot = MathMin(nextLot, lotBudgetLeft);

         double sl=0,tp=0;
         if(InpUseSLTP)
         {
            double slPts = atrPoints * InpSL_ATRMult;
            double tpPts = atrPoints * InpTP_ATRMult;
            sl = ask + PointsToPrice(slPts);
            tp = ask - PointsToPrice(tpPts);
         }
         OpenMarketOrder(ORDER_TYPE_SELL, nextLot, sl, tp, "AVG SELL");
         // refresh budget
         lotBudgetLeft = MathMax(0.0, InpMaxTotalLot - (buyStats.totalLots + sellStats.totalLots + nextLot));
      }

      // Profit-based scale-in for SELL
      if(InpEnableProfitAveraging && stepPtsProfit > 0.0 && lotBudgetLeft > 0)
      {
         double profitMovePts = PriceToPoints(referencePrice - bid);
         if(profitMovePts >= stepPtsProfit)
         {
            double nextLot = InpUseLotMultiplier ? (InpInitialLot * MathPow(InpLotMultiplier, sellStats.positionsCount))
                                                 : InpInitialLot;
            nextLot = MathMin(nextLot, lotBudgetLeft);

            double sl=0,tp=0;
            if(InpUseSLTP)
            {
               double slPts = atrPoints * InpSL_ATRMult;
               double tpPts = atrPoints * InpTP_ATRMult;
               sl = ask + PointsToPrice(slPts);
               tp = ask - PointsToPrice(tpPts);
            }
            OpenMarketOrder(ORDER_TYPE_SELL, nextLot, sl, tp, "SCALE SELL");
         }
      }
   }
}

void ManageTrailingStops()
{
   if(!InpUseTrailingStop) return;
   double atrPoints; if(!GetATR(atrPoints)) return;
   double trailPts = atrPoints * InpTrail_ATRMult;
   double trailPriceDistance = PointsToPrice(trailPts);

   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);

      if(!RefreshTick()) return;

      if(type == POSITION_TYPE_BUY)
      {
         double newSL = MathMax(sl, g_tick.bid - trailPriceDistance);
         if(newSL > sl && newSL < g_tick.bid)
         {
            g_trade.PositionModify(ticket, newSL, tp);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double newSL = MathMin(sl==0?DBL_MAX:sl, g_tick.ask + trailPriceDistance);
         if((sl == 0 && newSL > g_tick.ask) || (sl != 0 && newSL < sl && newSL > g_tick.ask))
         {
            g_trade.PositionModify(ticket, newSL, tp);
         }
      }
   }
}

//=========================== Basket TP (Money All) =============================
double ComputeEAProfitBasket(bool allSymbols)
{
   double totalProfit = 0.0;
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      if(!allSymbols && sym != g_symbol) continue;
      totalProfit += PositionGetDouble(POSITION_PROFIT);
   }
   return totalProfit;
}

void CloseEAPositionsBasket(bool allSymbols)
{
   // Close from last to first to avoid reindexing surprises
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      if(!allSymbols && sym != g_symbol) continue;
      g_trade.SetExpertMagicNumber(InpMagicNumber);
      g_trade.SetDeviationInPoints(InpMaxSlippagePoints);
      g_trade.PositionClose(ticket);
   }
}

void ManageTPMoneyAll()
{
   if(!InpEnableTPMoneyAll) return;
   double pf = ComputeEAProfitBasket(InpTPMoneyAllAllSymbols);
   if(pf >= InpTPMoneyAllAmount)
   {
      CloseEAPositionsBasket(InpTPMoneyAllAllSymbols);
   }
}

//=========================== Hedge Unlock =====================================
datetime g_lockStartTime = 0;

bool IsLocked(const DirectionStats &buyStats, const DirectionStats &sellStats)
{
   if(buyStats.positionsCount <= 0 || sellStats.positionsCount <= 0) return false;
   double diff = MathAbs(buyStats.totalLots - sellStats.totalLots);
   return (diff <= InpLockLotTolerance);
}

void UpdateLockTimer(const DirectionStats &buyStats, const DirectionStats &sellStats)
{
   bool locked = IsLocked(buyStats, sellStats);
   if(locked)
   {
      if(g_lockStartTime == 0) g_lockStartTime = TimeCurrent();
   }
   else
   {
      g_lockStartTime = 0;
   }
}

int BarsSince(datetime t)
{
   if(t == 0) return 0;
   datetime nowBar = iTime(g_symbol, InpSignalTimeframe, 0);
   if(nowBar <= 0) return 0;
   int count = 0;
   for(int i=0; ; ++i)
   {
      datetime ti = iTime(g_symbol, InpSignalTimeframe, i);
      if(ti <= 0 || ti < t) break;
      count++;
      if(count > 10000) break;
   }
   return count;
}

double GetATRSMA(int period)
{
   if(!EnsureIndicators()) return 0.0;
   int cnt = MathMax(1, period);
   double buff[];
   if(CopyBuffer(g_handleATR, 0, 0, cnt, buff) < cnt) return 0.0;
   double sum=0.0; for(int i=0;i<cnt;i++) sum += buff[i];
   return sum/cnt;
}

void CloseSidePositions(int positionType) // POSITION_TYPE_BUY / POSITION_TYPE_SELL
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if((int)PositionGetInteger(POSITION_TYPE) != positionType) continue;
      g_trade.SetExpertMagicNumber(InpMagicNumber);
      g_trade.SetDeviationInPoints(InpMaxSlippagePoints);
      g_trade.PositionClose(ticket);
   }
}

void ManageHedgeUnlock()
{
   if(!InpEnableHedgeUnlock) return;

   DirectionStats buyStats, sellStats; double totalFloating;
   ComputeDirectionStats(buyStats, sellStats, totalFloating);
   UpdateLockTimer(buyStats, sellStats);

   if(!IsLocked(buyStats, sellStats)) return;

   // Volatility gate
   if(InpUnlockVolGateEnabled)
   {
      double atrNowPts; if(!GetATR(atrNowPts)) return;
      double atrNowPrice = PointsToPrice(atrNowPts);
      double atrSMA = GetATRSMA(20);
      if(atrSMA <= 0) return;
      if((atrNowPrice) < (PointsToPrice(atrSMA) * InpUnlockVolGateATRRatio)) return;
   }

   // Compute dynamic target in currency
   double atrPts; if(!GetATR(atrPts)) return;
   double priceMove = PointsToPrice(atrPts);
   double ticks = (g_tickSize > 0 ? priceMove / g_tickSize : 0);
   double lotBase = (buyStats.totalLots + sellStats.totalLots) * 0.5;
   double dynTarget = InpUnlockK_ATRProfit * ticks * g_tickValue * lotBase;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double equityCap = equity * (InpUnlockEquityCapPercent/100.0);
   double targetUnlock = MathMax(0.0, MathMin(dynTarget, equityCap));

   // 1) Dynamic TP unlock
   if(InpUnlockUseDynamicTP && totalFloating >= targetUnlock && targetUnlock > 0.0)
   {
      CloseEAPositionsBasket(false);
      return;
   }

   int barsLocked = BarsSince(g_lockStartTime);

   // 2) Midline break-even unlock after min bars
   if(InpUnlockUseMidline && barsLocked >= InpUnlockMinLockBars)
   {
      if(!RefreshTick()) return;
      double bid=g_tick.bid, ask=g_tick.ask; double mid=(bid+ask)/2.0;
      double avgBuy = buyStats.avgOpenPrice;
      double avgSell = sellStats.avgOpenPrice;
      if(avgBuy>0.0 && avgSell>0.0)
      {
         double midline = (avgBuy + avgSell)/2.0;
         double buffer  = PointsToPrice(atrPts * InpUnlockMidlineBufferATR);
         if(MathAbs(mid - midline) <= buffer)
         {
            CloseEAPositionsBasket(false);
            return;
         }
      }
   }

   // 3) Partial release (optional)
   if(InpUnlockPartialEnabled)
   {
      double partThresh = ticks * g_tickValue * InpUnlockPartialATRMult; // per 1 lot
      if(buyStats.totalLots>0 && buyStats.totalProfit >= partThresh*buyStats.totalLots)
      {
         CloseSidePositions(POSITION_TYPE_BUY);
         return;
      }
      if(sellStats.totalLots>0 && sellStats.totalProfit >= partThresh*sellStats.totalLots)
      {
         CloseSidePositions(POSITION_TYPE_SELL);
         return;
      }
   }

   // 4) Fail-safe time unlock
   if(barsLocked >= InpUnlockFailSafeBars)
   {
      double allowLoss = InpUnlockFailSafeAllowLoss;
      // If allowLoss is negative, it is a permissible loss threshold (e.g., -10)
      if(totalFloating >= allowLoss)
      {
         CloseEAPositionsBasket(false);
         return;
      }
   }
}

// Keep standard hedging in place
void ManageHedge()
{
   if(!InpEnableHedge) return;

   // Use per-cycle trigger logic
   if(!ShouldHedgeForCycle(g_cycleId)) return;

   DirectionStats buyStats, sellStats; double totalFloating;
   ComputeDirectionStatsForCycle(g_cycleId, buyStats, sellStats, totalFloating);

   int hedgeCount = CountHedgePositionsForCycle(g_cycleId);
   if(hedgeCount >= InpMaxHedgePositions) return;

   double netLot = MathAbs(buyStats.totalLots - sellStats.totalLots);
   if(netLot <= 0.0) return;

   double hedgeLot = NormalizeLot(MathMin(netLot * InpHedgeLotRatioToNet, InpMaxTotalLot));
   if(hedgeLot <= 0.0) return;

   // Hedge ke arah yang berlawanan dengan net exposure untuk cycle ini
   if(buyStats.totalLots > sellStats.totalLots)
   {
      OpenMarketOrder(ORDER_TYPE_SELL, hedgeLot, 0, 0, "HEDGE SELL");
   }
   else if(sellStats.totalLots > buyStats.totalLots)
   {
      OpenMarketOrder(ORDER_TYPE_BUY, hedgeLot, 0, 0, "HEDGE BUY");
   }
}

//============================== Dashboard =====================================
void CreateOrUpdateLabel(const string name, const string text, int corner, int xOffset, int yOffset, color clr)
{
   string objName = g_labelPrefix + name;
   if(ObjectFind(0, objName) == -1)
   {
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
      ObjectSetString (0, objName, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   }
   ObjectSetInteger(0, objName, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, xOffset);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, yOffset);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetString (0, objName, OBJPROP_TEXT, text);
}

void UpdateDashboard()
{
   DirectionStats buyStats, sellStats; double totalFloating;
   ComputeDirectionStats(buyStats, sellStats, totalFloating);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Max floating (paling negatif) tracking
   if(g_initialized)
   {
      if(totalFloating < g_minFloatingSeen) g_minFloatingSeen = totalFloating;
   }

   int corner = CORNER_RIGHT_UPPER;
   int x = 10; // distance from right border
   int y = 10;
   int dy = 14;

   string line;
   int row = 0;

   line = StringFormat("EA: %s", InpEaName);
   CreateOrUpdateLabel("00_EA", line, corner, x, y + dy*row++, clrWhite);

   g_accountNumber = AccountInfoInteger(ACCOUNT_LOGIN);
   line = StringFormat("Akun: %I64d", g_accountNumber);
   CreateOrUpdateLabel("01_ACC", line, corner, x, y + dy*row++, clrWhite);

   line = StringFormat("Lot BUY: %.2f", buyStats.totalLots);
   CreateOrUpdateLabel("02_LB", line, corner, x, y + dy*row++, clrLime);

   line = StringFormat("Lot SELL: %.2f", sellStats.totalLots);
   CreateOrUpdateLabel("03_LS", line, corner, x, y + dy*row++, clrOrange);

   line = StringFormat("Selisih Lot: %.2f", buyStats.totalLots - sellStats.totalLots);
   CreateOrUpdateLabel("04_DIF", line, corner, x, y + dy*row++, clrAqua);

   line = StringFormat("Jumlah OP BUY: %d", buyStats.positionsCount);
   CreateOrUpdateLabel("05_CB", line, corner, x, y + dy*row++, clrLime);

   line = StringFormat("Jumlah OP SELL: %d", sellStats.positionsCount);
   CreateOrUpdateLabel("06_CS", line, corner, x, y + dy*row++, clrOrange);

   line = StringFormat("Balance: %.2f", balance);
   CreateOrUpdateLabel("07_BAL", line, corner, x, y + dy*row++, clrWhite);

   line = StringFormat("Equity: %.2f", equity);
   CreateOrUpdateLabel("08_EQ", line, corner, x, y + dy*row++, clrWhite);

   color pfClr = totalFloating >= 0 ? clrLime : clrTomato;
   line = StringFormat("Floating/Profit: %.2f", totalFloating);
   CreateOrUpdateLabel("09_FP", line, corner, x, y + dy*row++, pfClr);

   line = StringFormat("Max Floating: %.2f", g_minFloatingSeen);
   CreateOrUpdateLabel("10_MF", line, corner, x, y + dy*row++, clrGold);
}

void ClearDashboard()
{
   // delete all objects with prefix
   int total = ObjectsTotal(0, -1, -1);
   for(int i=total-1; i>=0; --i)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_labelPrefix, 0) == 0)
         ObjectDelete(0, name);
   }
}

//============================== SND Zones =====================================
void DrawOrUpdateZoneRect(const string name, datetime t1, datetime t2, double priceLow, double priceHigh, color clr)
{
   string objName = g_zonePrefix + name;
   if(ObjectFind(0, objName) == -1)
   {
      ObjectCreate(0, objName, OBJ_RECTANGLE, 0, t1, priceLow, t2, priceHigh);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, (name=="SUPPLY"?InpSupplyLineWidth:InpDemandLineWidth));
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_FILL, InpZoneFill);
      if(InpZoneFill)
      {
         int alpha = (name=="SUPPLY"?InpSupplyFillAlpha:InpDemandFillAlpha);
         color fill = (name=="SUPPLY"?InpSupplyColor:InpDemandColor);
         ObjectSetInteger(0, objName, OBJPROP_BACK, true);
         ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, objName, OBJPROP_ZORDER, 0);
         // In MT5, rectangle fill uses OBJPROP_COLOR with alpha component if supported by theme; keep border color and rely on platform fill flag
         // Some builds need style only; we keep settings minimal.
      }
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, (name=="SUPPLY"?InpSupplyLineWidth:InpDemandLineWidth));
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_FILL, InpZoneFill);
      ObjectMove(0, objName, 0, t1, priceLow);
      ObjectMove(0, objName, 1, t2, priceHigh);
   }
}

void DeleteZoneRect(const string name)
{
   string objName = g_zonePrefix + name;
   if(ObjectFind(0, objName) != -1)
      ObjectDelete(0, objName);
}

void UpdateSNDZones()
{
   if(!InpShowZones)
   {
      DeleteZoneRect("SUPPLY");
      DeleteZoneRect("DEMAND");
      return;
   }
   double supLow=0,supHigh=0,demLow=0,demHigh=0;
   if(!ComputeZones(supLow,supHigh,demLow,demHigh)) { DeleteZoneRect("SUPPLY"); DeleteZoneRect("DEMAND"); return; }

   int leftBars = MathMax(10, InpZoneHistoryBars);
   int rightBars = MathMax(5, InpZoneRightBars);
   datetime tRight = TimeCurrent() + (datetime)(PeriodSeconds(InpSignalTimeframe) * rightBars);
   datetime tLeft  = iTime(g_symbol, InpSignalTimeframe, leftBars);
   if(tLeft == 0) tLeft = TimeCurrent() - (datetime)(PeriodSeconds(InpSignalTimeframe) * leftBars);

   if(supHigh > 0.0)
      DrawOrUpdateZoneRect("SUPPLY", tLeft, tRight, supLow, supHigh, InpSupplyColor);
   else
      DeleteZoneRect("SUPPLY");

   if(demHigh > 0.0)
      DrawOrUpdateZoneRect("DEMAND", tLeft, tRight, demLow, demHigh, InpDemandColor);
   else
      DeleteZoneRect("DEMAND");
}

void ClearZones()
{
   // delete all objects with prefix
   int total = ObjectsTotal(0, -1, -1);
   for(int i=total-1; i>=0; --i)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_zonePrefix, 0) == 0)
         ObjectDelete(0, name);
   }
}

//============================= Lifecycle =====================================
int OnInit()
{
   g_symbol = (InpTradeSymbol == "" ? _Symbol : InpTradeSymbol);
   g_point  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_tickSize  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   g_tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);

   if(!EnsureIndicators())
   {
      Print("[Init] Gagal membuat indikator.");
      return(INIT_FAILED);
   }

   if(!RefreshTick())
   {
      Print("[Init] Gagal refresh tick.");
      return(INIT_FAILED);
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_minFloatingSeen = 0.0;
   g_initialized = true;

   // Initialize cycle from existing positions
   int maxCycle = DetectMaxCycleFromOpenPositions();
   if(maxCycle > 0) g_cycleId = maxCycle; else g_cycleId = 1;

   EventSetTimer(2); // for dashboard refresh and management even if no ticks

   PrintFormat("%s initialized on %s (digits=%d, point=%g) cycle=%d", InpEaName, g_symbol, g_digits, g_point, g_cycleId);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ClearDashboard();
   ClearZones();
}

void OnTimer()
{
   // Management that does not require every tick
   UpdateDashboard();
   UpdateSNDZones();
}

void OnTick()
{
   if(_Symbol != g_symbol) return; // attached chart symbol changed

   // Basket TP check first to avoid opening new trades on the same tick
   ManageTPMoneyAll();

   // Unlock management when hedged/locked
   ManageHedgeUnlock();

   // Advance cycle when current becomes locked
   ManageCycleAdvance();

   // Core pipeline
   TryEntrySignals();
   ManageAveraging();
   ManageTrailingStops();
   ManageHedge();

   // Dashboard + Zones refresh
   UpdateDashboard();
   UpdateSNDZones();
}

//+------------------------------------------------------------------+