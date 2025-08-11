#property strict
#property copyright "2025"
#property link      ""
#property version   "1.00"
#property description "EA menggabungkan Averaging (saat ranging) dan Hedging (saat trending)"
#property description "Trend ditentukan via ADX; Averaging menggunakan grid berdasarkan RSI."

#include <Trade/Trade.mqh>

CTrade Trade;

// ==============================
// Input Parameters
// ==============================
input long   InpMagic                  = 2025081101;   // Magic number
input bool   InpAllowNewTrades         = true;         // Izinkan buka posisi baru
input int    InpMaxSpreadPoints        = 30;           // Maks spread (points)
input int    InpSlippage               = 5;            // Slippage (points)

input bool   InpUseTradingHours        = false;        // Batasi jam trading
input int    InpStartHour              = 1;            // Jam mulai (server time)
input int    InpEndHour                = 23;           // Jam akhir (server time)

// Lot & Risk
input bool   InpUseAutoLot             = false;        // Gunakan auto lot (persentase balance)
input double InpRiskPerTradePct        = 1.0;          // % balance per trade (jika auto lot)
input double InpFixedLot               = 0.10;         // Lot tetap (jika tidak auto)

// Signal timeframe
input ENUM_TIMEFRAMES InpSignalTF      = PERIOD_M15;   // TF untuk signal indikator

// Averaging (Range)
input bool   InpEnableAveraging        = true;         // Aktifkan Averaging/Grid
input int    InpGridStepPoints         = 300;          // Jarak grid (points)
input int    InpMaxAveragingLevels     = 5;            // Maks level averaging per arah
input double InpLotMultiplier          = 1.00;         // Kelipatan lot antar level (1.0 = tetap)

// Basket TP (menutup semua posisi saat profit >= target)
input double InpBasketTPMoney          = 10.0;         // Target profit (currency) untuk close all

// RSI signal untuk entry range
input int    InpRSIPeriod              = 14;           // Periode RSI
input int    InpRSIOverbought          = 70;           // Overbought -> Sell
input int    InpRSIOversold            = 30;           // Oversold  -> Buy

// Hedging (Trend)
input bool   InpEnableHedging          = true;         // Aktifkan Hedging (trend following)
input int    InpADXPeriod              = 14;           // Periode ADX
input double InpADXTrendThreshold      = 25.0;         // Ambang trending (ADX)
input int    InpHedgeStepPoints        = 300;          // Jarak antar hedge (points)
input int    InpMaxHedgeLevels         = 3;            // Maks level hedge
input double InpHedgeLotFactor         = 1.00;         // Lot hedge = exposure lawan * faktor

// Trailing untuk posisi trend (hedge)
input bool   InpUseTrailingStop        = true;         // Aktifkan trailing stop
input int    InpTrailStopPoints        = 400;          // Trail stop (points)
input int    InpTrailStepPoints        = 100;          // Trail step (points)

// Proteksi harian
input bool   InpUseDailyLossLimit      = true;         // Batasi kerugian harian
input double InpDailyLossLimit         = -100.0;       // Batas profit harian (close trade) dibawah ini -> stop open

// ==============================
// Globals & Handles
// ==============================
int          g_rsiHandle = INVALID_HANDLE;
int          g_adxHandle = INVALID_HANDLE;
string       g_symbol;
int          g_digits;
double       g_point;

// ==============================
// Utility helpers
// ==============================
bool CheckTradingHours()
{
   if(!InpUseTradingHours) return true;
   datetime now = TimeCurrent();
   MqlDateTime ts; TimeToStruct(now, ts);
   int hour = ts.hour;
   if(InpStartHour <= InpEndHour)
      return (hour >= InpStartHour && hour < InpEndHour);
   // window across midnight
   return (hour >= InpStartHour || hour < InpEndHour);
}

bool CheckSpreadOk()
{
   long spreadPoints;
   if(!SymbolInfoInteger(g_symbol, SYMBOL_SPREAD, spreadPoints))
      return false;
   return ((int)spreadPoints <= InpMaxSpreadPoints);
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, g_digits);
}

double LotsNormalize(double lots)
{
   double minLot, lotStep, maxLot;
   SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN, minLot);
   SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX, maxLot);
   SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP, lotStep);
   // quantize to step
   double steps = MathFloor((lots - minLot) / lotStep + 0.5);
   double normalized = minLot + steps * lotStep;
   if(normalized < minLot) normalized = minLot;
   if(normalized > maxLot) normalized = maxLot;
   return normalized;
}

int CountPositionsByDirection(int direction)
{
   int total = PositionsTotal();
   int count = 0;
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      string posSymbol; PositionGetString(POSITION_SYMBOL, posSymbol);
      if(posSymbol != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(direction > 0 && type == POSITION_TYPE_BUY) count++;
      if(direction < 0 && type == POSITION_TYPE_SELL) count++;
   }
   return count;
}

int CountAllPositions()
{
   int total = PositionsTotal();
   int count = 0;
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      string posSymbol2; PositionGetString(POSITION_SYMBOL, posSymbol2);
      if(posSymbol2 != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      count++;
   }
   return count;
}

double GetNetExposureLots(int direction)
{
   int total = PositionsTotal();
   double lots = 0.0;
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      string posSymbol3; PositionGetString(POSITION_SYMBOL, posSymbol3);
      if(posSymbol3 != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(direction > 0 && type == POSITION_TYPE_BUY) lots += vol;
      if(direction < 0 && type == POSITION_TYPE_SELL) lots += vol;
   }
   return lots;
}

// returns last open price for given direction (most recent by time)
bool GetLastEntry(int direction, double &price, datetime &timeOpen)
{
   int total = PositionsTotal();
   datetime lastTime = 0;
   double lastPrice = 0.0;
   bool found = false;
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      string posSymbol4; PositionGetString(POSITION_SYMBOL, posSymbol4);
      if(posSymbol4 != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if((direction > 0 && type != POSITION_TYPE_BUY) || (direction < 0 && type != POSITION_TYPE_SELL)) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      double p = PositionGetDouble(POSITION_PRICE_OPEN);
      if(!found || t > lastTime)
      {
         lastTime = t;
         lastPrice = p;
         found = true;
      }
   }
   if(found)
   {
     price = lastPrice;
     timeOpen = lastTime;
   }
   return found;
}

// returns number of levels for direction (positions count capped by max levels)
int GetLevelsForDirection(int direction)
{
   return CountPositionsByDirection(direction);
}

// basket profit (open positions) for this symbol+magic in deposit currency
double GetBasketProfitMoney()
{
   int total = PositionsTotal();
   double sum = 0.0;
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      string posSymbol5; PositionGetString(POSITION_SYMBOL, posSymbol5);
      if(posSymbol5 != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      sum += PositionGetDouble(POSITION_PROFIT);
   }
   return sum;
}

bool CloseAllPositions()
{
   bool ok = true;
   // Close buys first then sells
   for(int pass=0; pass<2; pass++)
   {
      int total = PositionsTotal();
      for(int i=total-1;i>=0;i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         string posSymbol6; PositionGetString(POSITION_SYMBOL, posSymbol6);
         if(posSymbol6 != g_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         long type = PositionGetInteger(POSITION_TYPE);
         if((pass==0 && type!=POSITION_TYPE_BUY) || (pass==1 && type!=POSITION_TYPE_SELL)) continue;
         double volume = PositionGetDouble(POSITION_VOLUME);
         if(type == POSITION_TYPE_BUY)
         {
            ok &= Trade.PositionClose(ticket);
         }
         else if(type == POSITION_TYPE_SELL)
         {
            ok &= Trade.PositionClose(ticket);
         }
      }
   }
   return ok;
}

// daily closed PnL for symbol+magic (today)
double GetTodayClosedProfit()
{
   datetime dayStart = (datetime)StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(!HistorySelect(dayStart, TimeCurrent())) return 0.0;
   int deals = HistoryDealsTotal();
   double pnl = 0.0;
   for(int i=0;i<deals;i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      string dealSymbol; HistoryDealGetString(dealTicket, DEAL_SYMBOL, dealSymbol);
      if(dealSymbol != g_symbol) continue;
      long entry   = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      long magic   = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      if(magic != InpMagic) continue;
      if(entry != DEAL_ENTRY_OUT) continue;
      pnl += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   }
   return pnl;
}

// Calculate lot size
 double CalculateLot(int level, bool isHedge)
 {
    double lot = InpFixedLot;
    if(InpUseAutoLot)
    {
       double balance = AccountInfoDouble(ACCOUNT_BALANCE);
       double riskAmount = balance * InpRiskPerTradePct / 100.0;
       // Approx tick value per lot
       double tickVal = 0.0; SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE, tickVal);
       double tickSize = 0.0; SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE, tickSize);
       double approxSLPoints = MathMax((double)InpGridStepPoints, (double)InpTrailStopPoints);
       double approxMove = approxSLPoints * (tickVal / (tickSize / g_point));
       if(approxMove > 0.0) lot = MathMax(0.01, riskAmount / approxMove);
    }
    // scaling
   if(!isHedge)
      lot *= MathPow(MathMax(1.0, InpLotMultiplier), MathMax(0, level-1));
   else
      lot *= MathMax(1.0, InpHedgeLotFactor);

   return LotsNormalize(lot);
}

// Get RSI latest value
bool GetRSI(double &rsi)
{
   if(g_rsiHandle == INVALID_HANDLE) return false;
   double val[];
   if(CopyBuffer(g_rsiHandle, 0, 0, 2, val) < 2) return false; // need at least current+prev
   rsi = val[0];
   return true;
}

// Trend detection using ADX and DI+/DI-
int GetTrendDirection(double &adxOut)
{
   adxOut = 0.0;
   if(g_adxHandle == INVALID_HANDLE) return 0;
   double adx[], plusDI[], minusDI[];
   int copied0 = CopyBuffer(g_adxHandle, 0, 0, 2, adx);     // ADX main
   int copied1 = CopyBuffer(g_adxHandle, 1, 0, 2, plusDI);  // +DI
   int copied2 = CopyBuffer(g_adxHandle, 2, 0, 2, minusDI); // -DI
   if(copied0 < 2 || copied1 < 2 || copied2 < 2) return 0;
   adxOut = adx[0];
   if(adx[0] < InpADXTrendThreshold) return 0; // ranging
   if(plusDI[0] > minusDI[0]) return 1; // uptrend
   if(minusDI[0] > plusDI[0]) return -1; // downtrend
   return 0;
}

// Open position helper
bool OpenPosition(int direction, double lot)
{
   if(!CheckSpreadOk()) return false;
   double ask, bid;
   SymbolInfoDouble(g_symbol, SYMBOL_ASK, ask);
   SymbolInfoDouble(g_symbol, SYMBOL_BID, bid);
   Trade.SetExpertMagicNumber(InpMagic);
   Trade.SetDeviationInPoints(InpSlippage);
   bool result = false;
   if(direction > 0)
      result = Trade.Buy(lot, g_symbol, ask, 0.0, 0.0, "AVG/HEDGE BUY");
   else
      result = Trade.Sell(lot, g_symbol, bid, 0.0, 0.0, "AVG/HEDGE SELL");
   return result;
}

// Trailing stop for all trend (hedge) positions
void ApplyTrailingStop()
{
   if(!InpUseTrailingStop) return;
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      string posSymbol7; PositionGetString(POSITION_SYMBOL, posSymbol7);
      if(posSymbol7 != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      double priceCurrent = 0.0;
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double priceOpen = PositionGetDouble(POSITION_PRICE_OPEN);

      double bid, ask;
      SymbolInfoDouble(g_symbol, SYMBOL_BID, bid);
      SymbolInfoDouble(g_symbol, SYMBOL_ASK, ask);

      if(type == POSITION_TYPE_BUY)
      {
         priceCurrent = bid;
         double newSL = priceCurrent - InpTrailStopPoints * g_point;
         if(priceCurrent - priceOpen > InpTrailStopPoints * g_point && (sl == 0.0 || newSL > sl + InpTrailStepPoints * g_point))
         {
            Trade.PositionModify((ulong)PositionGetInteger(POSITION_TICKET), NormalizePrice(newSL), tp);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         priceCurrent = ask;
         double newSL = priceCurrent + InpTrailStopPoints * g_point;
         if(priceOpen - priceCurrent > InpTrailStopPoints * g_point && (sl == 0.0 || newSL < sl - InpTrailStepPoints * g_point))
         {
            Trade.PositionModify((ulong)PositionGetInteger(POSITION_TICKET), NormalizePrice(newSL), tp);
         }
      }
   }
}

// Averaging logic during ranging
void HandleAveraging()
{
   if(!InpEnableAveraging || !InpAllowNewTrades) return;
   if(!CheckSpreadOk()) return;
   // basket take profit
   double basket = GetBasketProfitMoney();
   if(InpBasketTPMoney > 0.0 && basket >= InpBasketTPMoney)
   {
      CloseAllPositions();
      return;
   }

   // Entry based on RSI if no positions in that direction
   double rsi;
   if(!GetRSI(rsi)) return;

   // Try to open new initial entries if none positions overall
   if(CountAllPositions() == 0)
   {
      if(rsi >= InpRSIOverbought)
      {
         double lot = CalculateLot(1, false);
         OpenPosition(-1, lot); // SELL
      }
      else if(rsi <= InpRSIOversold)
      {
         double lot = CalculateLot(1, false);
         OpenPosition(1, lot); // BUY
      }
      return;
   }

   // Grid add-ons: if price moved adverse from last entry by grid step
   double ask, bid; SymbolInfoDouble(g_symbol, SYMBOL_ASK, ask); SymbolInfoDouble(g_symbol, SYMBOL_BID, bid);

   // For BUY chain
   int buyLevels = GetLevelsForDirection(1);
   if(buyLevels > 0 && buyLevels < InpMaxAveragingLevels)
   {
      double lastPrice; datetime t;
      if(GetLastEntry(1, lastPrice, t))
      {
         // adverse move for buy = price below last by step
         if((lastPrice - bid) >= InpGridStepPoints * g_point)
         {
            double lot = CalculateLot(buyLevels+1, false);
            OpenPosition(1, lot);
         }
      }
   }

   // For SELL chain
   int sellLevels = GetLevelsForDirection(-1);
   if(sellLevels > 0 && sellLevels < InpMaxAveragingLevels)
   {
      double lastPrice; datetime t;
      if(GetLastEntry(-1, lastPrice, t))
      {
         // adverse move for sell = price above last by step
         if((ask - lastPrice) >= InpGridStepPoints * g_point)
         {
            double lot = CalculateLot(sellLevels+1, false);
            OpenPosition(-1, lot);
         }
      }
   }
}

// Hedging logic during trending
void HandleHedging(int trendDir)
{
   if(!InpEnableHedging || trendDir == 0) return;
   if(!InpAllowNewTrades) return;
   if(!CheckSpreadOk()) return;

   // Determine current exposure
   double longLots = GetNetExposureLots(1);
   double shortLots = GetNetExposureLots(-1);
   double netTrendLots = (trendDir > 0 ? longLots : shortLots);
   double netAgainstLots = (trendDir > 0 ? shortLots : longLots);

   // If no trend-direction positions, consider opening initial trend position
   if(netTrendLots <= 0.0)
   {
      double lot = CalculateLot(1, true);
      OpenPosition(trendDir, lot);
      return;
   }

   // If there is exposure against trend, open hedge add-ons every InpHedgeStepPoints from last trend entry
   int trendLevels = GetLevelsForDirection(trendDir);
   if(trendLevels < InpMaxHedgeLevels && netAgainstLots > 0.0)
   {
      double lastTrendPrice; datetime t;
      if(GetLastEntry(trendDir, lastTrendPrice, t))
      {
         double ask, bid; SymbolInfoDouble(g_symbol, SYMBOL_ASK, ask); SymbolInfoDouble(g_symbol, SYMBOL_BID, bid);
         double curr = (trendDir > 0 ? ask : bid);
         // add when price moves further in trend direction by step OR retraces against but still trending? Keep it simple: add on continuation
         bool shouldAdd = false;
         if(trendDir > 0)
            shouldAdd = ((curr - lastTrendPrice) >= InpHedgeStepPoints * g_point);
         else
            shouldAdd = ((lastTrendPrice - curr) >= InpHedgeStepPoints * g_point);

         if(shouldAdd)
         {
            // hedge lot proportional to opposite exposure
            double baseLot = CalculateLot(trendLevels+1, true);
            double lot = LotsNormalize(MathMax(baseLot, netAgainstLots * InpHedgeLotFactor));
            OpenPosition(trendDir, lot);
         }
      }
   }

   // trailing for trend positions
   ApplyTrailingStop();
}

int OnInit()
{
   g_symbol = _Symbol;
   long tmpDigits; SymbolInfoInteger(g_symbol, SYMBOL_DIGITS, tmpDigits);
   g_digits = (int)tmpDigits;
   double tmpPoint; SymbolInfoDouble(g_symbol, SYMBOL_POINT, tmpPoint);
   g_point = tmpPoint;

   Trade.SetExpertMagicNumber(InpMagic);
   Trade.SetDeviationInPoints(InpSlippage);

   g_rsiHandle = iRSI(g_symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);
   if(g_rsiHandle == INVALID_HANDLE)
   {
      Print("RSI handle creation failed");
      return INIT_FAILED;
   }
   g_adxHandle = iADX(g_symbol, InpSignalTF, InpADXPeriod);
   if(g_adxHandle == INVALID_HANDLE)
   {
      Print("ADX handle creation failed");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
}

void OnTick()
{
   if(!CheckTradingHours()) return;
   if(InpUseDailyLossLimit)
   {
      double todayPnL = GetTodayClosedProfit();
      if(todayPnL <= InpDailyLossLimit)
      {
         // Stop membuka posisi baru
         return;
      }
   }

   double adxValue = 0.0;
   int trendDir = GetTrendDirection(adxValue);

   if(trendDir == 0)
   {
      // Ranging -> Averaging logic
      HandleAveraging();
   }
   else
   {
      // Trending -> Hedging logic
      HandleHedging(trendDir);
   }

   // Basket Take Profit check every tick as safety
   if(InpBasketTPMoney > 0.0)
   {
      double basket = GetBasketProfitMoney();
      if(basket >= InpBasketTPMoney)
      {
         CloseAllPositions();
      }
   }
}

// Notes:
// - EA ini dirancang untuk akun hedging. Pada akun netting, perilaku posisi mungkin berbeda.
// - Averaging/Grid dapat meningkatkan risiko. Gunakan parameter konservatif.
// - Uji di demo sebelum ke akun real.