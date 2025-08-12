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

// Basket TP (TP Money All)
input bool     InpEnableTPMoneyAll            = false;          // Aktifkan TP Money All (basket TP)
input double   InpTPMoneyAllAmount            = 100.0;          // Target profit uang (mata uang akun)
input bool     InpTPMoneyAllAllSymbols        = false;          // Hitung semua simbol dengan magic ini (true) atau hanya simbol EA (false)

// Filters
input int      InpMaxSpreadPoints             = 250;            // Maks spread (points)
input int      InpMaxSlippagePoints           = 50;             // Maks slippage (points)

// Misc
input bool     InpAllowBuy                    = true;           // Izinkan BUY
input bool     InpAllowSell                   = true;           // Izinkan SELL
input bool     InpOneEntryPerBar              = true;           // Batasi entry 1x tiap bar

//============================ Globals =========================================
CTrade         g_trade;
string         g_symbol;
double         g_point;
int            g_digits;
double         g_tickSize;
double         g_tickValue;
MqlTick        g_tick;
long           g_accountNumber;

// Indicator handles
int            g_handleATR = INVALID_HANDLE;
int            g_handleFractals = INVALID_HANDLE;

// State
datetime       g_lastBarTime = 0;
double         g_minFloatingSeen = 0.0; // paling negatif
bool           g_initialized = false;

// Label IDs
string         g_labelPrefix = "SND_GOLD_EA_DASH_";

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
};

void ComputeDirectionStats(DirectionStats &buyStats, DirectionStats &sellStats, double &totalFloating)
{
   buyStats.totalLots = 0; buyStats.positionsCount = 0; buyStats.totalProfit = 0; buyStats.worstPrice = 0; buyStats.lastOpenPrice = 0;
   sellStats.totalLots = 0; sellStats.positionsCount = 0; sellStats.totalProfit = 0; sellStats.worstPrice = 0; sellStats.lastOpenPrice = 0;
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
         if(buyStats.worstPrice == 0 || price > buyStats.worstPrice) buyStats.worstPrice = price; // worst for buy is highest
      }
      else if(type == POSITION_TYPE_SELL)
      {
         sellStats.totalLots += volume;
         sellStats.positionsCount++;
         sellStats.totalProfit += profit;
         sellStats.lastOpenPrice = price;
         if(sellStats.worstPrice == 0 || price < sellStats.worstPrice) sellStats.worstPrice = price; // worst for sell is lowest
      }
   }
}

int CountHedgePositions()
{
   int cnt = 0;
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "HEDGE", 0) >= 0) cnt++;
   }
   return cnt;
}

//============================ Trade Helpers ==================================
bool OpenMarketOrder(ENUM_ORDER_TYPE orderType, double lots, double slPrice=0.0, double tpPrice=0.0, string comment="")
{
   lots = NormalizeLot(lots);
   if(lots <= 0) return false;

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpMaxSlippagePoints);

   bool ok = false;
   if(orderType == ORDER_TYPE_BUY)
      ok = g_trade.Buy(lots, g_symbol, 0.0, slPrice, tpPrice, comment);
   else if(orderType == ORDER_TYPE_SELL)
      ok = g_trade.Sell(lots, g_symbol, 0.0, slPrice, tpPrice, comment);

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
void TryEntrySignals()
{
   if(InpOneEntryPerBar)
   {
      datetime ct = iTime(g_symbol, InpSignalTimeframe, 0);
      if(ct == g_lastBarTime) return; // already processed
   }

   double atrPoints; if(!GetATR(atrPoints)) return;
   if(atrPoints < InpMinATRPoints) return; // low volatility filter

   double upFractal, dnFractal; if(!GetLastFractals(upFractal, dnFractal)) return;
   double zoneHalfWidthPts = MathMax(1.0, atrPoints * InpZoneATRMultiplier);

   // Current price reference
   if(!RefreshTick()) return;
   double bid = g_tick.bid;
   double ask = g_tick.ask;
   double mid = (bid+ask)/2.0;

   // Demand zone around last down fractal (support)
   bool inDemand = false;
   if(dnFractal > 0.0)
   {
      double lower = dnFractal - PointsToPrice(zoneHalfWidthPts);
      double upper = dnFractal + PointsToPrice(zoneHalfWidthPts);
      if(mid >= lower && mid <= upper) inDemand = true;
   }

   // Supply zone around last up fractal (resistance)
   bool inSupply = false;
   if(upFractal > 0.0)
   {
      double lower = upFractal - PointsToPrice(zoneHalfWidthPts);
      double upper = upFractal + PointsToPrice(zoneHalfWidthPts);
      if(mid >= lower && mid <= upper) inSupply = true;
   }

   DirectionStats buyStats, sellStats; double totalFloating;
   ComputeDirectionStats(buyStats, sellStats, totalFloating);

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

   // Entry conditions
   if(SpreadOk())
   {
      // BUY
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

      // SELL
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

   DirectionStats buyStats, sellStats; double totalFloating;
   ComputeDirectionStats(buyStats, sellStats, totalFloating);

   if(!RefreshTick()) return;
   double bid = g_tick.bid;
   double ask = g_tick.ask;

   double lotBudgetLeft = MathMax(0.0, InpMaxTotalLot - (buyStats.totalLots + sellStats.totalLots));

   // Averaging BUY: add when price goes further down by step from last buy open price
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
      }
   }

   // Averaging SELL: add when price goes further up by step from last sell open price
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

void ManageHedge()
{
   if(!InpEnableHedge) return;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double ddPercent = (balance<=0) ? 0 : (MathMax(0.0, (balance - equity)) / balance * 100.0);

   DirectionStats buyStats, sellStats; double totalFloating;
   ComputeDirectionStats(buyStats, sellStats, totalFloating);

   int hedgeCount = CountHedgePositions();

   if(ddPercent >= InpHedgeTriggerDDPercent && hedgeCount < InpMaxHedgePositions)
   {
      double netLot = MathAbs(buyStats.totalLots - sellStats.totalLots);
      if(netLot <= 0.0) return;

      double hedgeLot = NormalizeLot(MathMin(netLot * InpHedgeLotRatioToNet, InpMaxTotalLot));
      if(hedgeLot <= 0.0) return;

      // Hedge ke arah yang berlawanan dengan net exposure
      if(buyStats.totalLots > sellStats.totalLots)
      {
         // Net buy, buka sell hedge
         OpenMarketOrder(ORDER_TYPE_SELL, hedgeLot, 0, 0, "HEDGE SELL");
      }
      else if(sellStats.totalLots > buyStats.totalLots)
      {
         OpenMarketOrder(ORDER_TYPE_BUY, hedgeLot, 0, 0, "HEDGE BUY");
      }
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

   EventSetTimer(2); // for dashboard refresh and management even if no ticks

   PrintFormat("%s initialized on %s (digits=%d, point=%g)", InpEaName, g_symbol, g_digits, g_point);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ClearDashboard();
}

void OnTimer()
{
   // Management that does not require every tick
   UpdateDashboard();
}

void OnTick()
{
   if(_Symbol != g_symbol) return; // attached chart symbol changed

   // Basket TP check first to avoid opening new trades on the same tick
   ManageTPMoneyAll();

   // Core pipeline
   TryEntrySignals();
   ManageAveraging();
   ManageTrailingStops();
   ManageHedge();

   // Dashboard refresh also here for responsiveness
   UpdateDashboard();
}

//+------------------------------------------------------------------+