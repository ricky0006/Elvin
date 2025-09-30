//+------------------------------------------------------------------+
//|                                                   SMART AI AVGHEDGE|
//|                                        Averaging + Hedge EA (MT5) |
//|                           Rules per request by: SMART AI AVGHEDGE |
//+------------------------------------------------------------------+
#property copyright   "SMART AI AVGHEDGE"
#property version     "1.00"
#property description "EA averaging searah OP awal + hedging saat max averaging tercapai"
#property strict

#include <Trade/Trade.mqh>

//======================== Inputs ========================
input string    InpEaName              = "SMART AI AVGHEDGE";          // EA Name (label)
input double    InpLot                 = 0.10;                          // Lot awal averaging
input ulong     InpMagic               = 987654;                        // Magic number
input int       InpSlippagePoints      = 10;                            // Slippage (points)

// Averaging settings
input bool      InpUseAveraging        = true;                          // Use Averaging
input int       InpJarakAveragingPts   = 300;                           // Jarak Averaging (points)
input double    InpMultiplierAvg       = 1.50;                          // Multy Lot averaging
input int       InpTpAvgPts            = 500;                           // TP Avg (points dari harga rata2)
input int       InpMaxAvg              = 5;                             // Max Avg (jumlah posisi searah)

// Hedging settings
input bool      InpUseHedging          = true;                          // Use Hedging
input double    InpLotHedge            = 0.10;                          // Lot hedge awal
input int       InpJarakHedgePts       = 300;                           // Jarak Hedge (points)
input double    InpMultiplierHedge     = 1.50;                          // Multy lot hedge
input int       InpMaxHedge            = 3;                             // Max Hedge (jumlah posisi berlawanan)

// Money management (basket)
input bool      InpUseTPMoney          = false;                         // Use TP Money (tutup semua)
input double    InpTPMoney             = 50.0;                          // Jumlah Money (target profit)
input bool      InpUseSLMoney          = false;                         // Use SL Money (tutup semua)
input double    InpSLMoney             = 50.0;                          // Jumlah money (maks loss)

//======================== Globals =======================
CTrade          g_trade;
string          g_symbol;
double          g_point;
int             g_digits;

// Helper structure for basket info
struct BasketInfo
{
   int       buyCount;
   int       sellCount;
   double    buyLots;
   double    sellLots;
   double    buyWeightedPrice;  // rata-rata harga buy (weighted)
   double    sellWeightedPrice; // rata-rata harga sell (weighted)
   double    netProfit;         // profit semua posisi dengan magic ini
   double    lastBuyPrice;      // harga posisi buy terakhir (time newest)
   double    lastSellPrice;     // harga posisi sell terakhir (time newest)
};

//======================== Utilities =====================
double NormalizeLot(double lot)
{
   lot = MathMax(lot, SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN));
   double step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   if(step > 0.0)
      lot = MathFloor(lot/step) * step;
   double maxLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   if(maxLot > 0.0)
      lot = MathMin(lot, maxLot);
   return lot;
}

bool IsTradeAllowed()
{
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO ||
      AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL)
      return true;
   return false;
}

int PositionsByMagic()
{
   int total = 0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == (long)InpMagic && PositionGetString(POSITION_SYMBOL) == g_symbol)
            total++;
      }
   }
   return total;
}

BasketInfo GetBasket()
{
   BasketInfo bi;
   bi.buyCount = bi.sellCount = 0;
   bi.buyLots = bi.sellLots = 0.0;
   bi.buyWeightedPrice = bi.sellWeightedPrice = 0.0;
   bi.netProfit = 0.0;
   bi.lastBuyPrice = 0.0;
   bi.lastSellPrice = 0.0;

   datetime lastBuyTime = 0;
   datetime lastSellTime = 0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;

      long type   = PositionGetInteger(POSITION_TYPE);
      double lots = PositionGetDouble(POSITION_VOLUME);
      double price= PositionGetDouble(POSITION_PRICE_OPEN);
      double prof = PositionGetDouble(POSITION_PROFIT);
      datetime t  = (datetime)PositionGetInteger(POSITION_TIME);
      bi.netProfit += prof;

      if(type == POSITION_TYPE_BUY)
      {
         bi.buyCount++;
         bi.buyLots += lots;
         bi.buyWeightedPrice += price * lots;
         if(t >= lastBuyTime){ lastBuyTime = t; bi.lastBuyPrice = price; }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         bi.sellCount++;
         bi.sellLots += lots;
         bi.sellWeightedPrice += price * lots;
         if(t >= lastSellTime){ lastSellTime = t; bi.lastSellPrice = price; }
      }
   }

   if(bi.buyLots > 0.0)  bi.buyWeightedPrice  /= bi.buyLots; else bi.buyWeightedPrice  = 0.0;
   if(bi.sellLots > 0.0) bi.sellWeightedPrice /= bi.sellLots; else bi.sellWeightedPrice = 0.0;
   return bi;
}

// Determine base direction from the first opened position for this magic
// Returns:  1 for BUY base, -1 for SELL base, 0 if none
int DetectBaseDirection()
{
   datetime firstTime = LONG_MAX;
   int base = 0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t < firstTime)
      {
         firstTime = t;
         long type = PositionGetInteger(POSITION_TYPE);
         base = (type == POSITION_TYPE_BUY ? 1 : -1);
      }
   }
   return base;
}

double PowSafe(double a, int n)
{
   if(n <= 0) return 1.0;
   double r = 1.0;
   for(int i=0;i<n;i++) r *= a;
   return r;
}

//======================== Trading Ops ===================
bool OpenBuy(double lot)
{
   g_trade.SetExpertMagicNumber((long)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   lot = NormalizeLot(lot);
   if(lot <= 0.0) return false;
   return g_trade.Buy(lot, g_symbol, 0.0, 0.0, 0.0, InpEaName);
}

bool OpenSell(double lot)
{
   g_trade.SetExpertMagicNumber((long)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   lot = NormalizeLot(lot);
   if(lot <= 0.0) return false;
   return g_trade.Sell(lot, g_symbol, 0.0, 0.0, 0.0, InpEaName);
}

void CloseAllByMagic()
{
   // Close all positions for this symbol+magic
   for(int pass=0; pass<2; pass++)
   {
      // pass 0: close sells, pass 1: close buys (order sometimes matters for margin)
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
         long type = PositionGetInteger(POSITION_TYPE);
         double lots = PositionGetDouble(POSITION_VOLUME);

         g_trade.SetExpertMagicNumber((long)InpMagic);
         g_trade.SetDeviationInPoints(InpSlippagePoints);

         if(pass == 0 && type == POSITION_TYPE_SELL)
            g_trade.PositionClose(ticket, lots);
         if(pass == 1 && type == POSITION_TYPE_BUY)
            g_trade.PositionClose(ticket, lots);
      }
   }
}

//======================== Strategy Logic ================
void TryAveraging(const BasketInfo &bi, int baseDir)
{
   if(!InpUseAveraging) return;
   if(baseDir == 0) return;

   // counts searah base
   int sameCount = (baseDir > 0 ? bi.buyCount : bi.sellCount);
   if(sameCount >= InpMaxAvg) return; // mencapai max averaging

   double lastEntry = (baseDir > 0 ? bi.lastBuyPrice : bi.lastSellPrice);
   double price = (baseDir > 0 ? SymbolInfoDouble(g_symbol, SYMBOL_BID) : SymbolInfoDouble(g_symbol, SYMBOL_ASK));

   // open averaging if price moves against last entry by JarakAveragingPts
   bool enoughDistance = false;
   if(baseDir > 0) // BUY basket: price turun dari last buy
      enoughDistance = (lastEntry - price) >= (InpJarakAveragingPts * g_point);
   else             // SELL basket: price naik dari last sell
      enoughDistance = (price - lastEntry) >= (InpJarakAveragingPts * g_point);

   if(enoughDistance || sameCount == 0)
   {
      // sameCount==0 means there is no position yet in base direction but we have base from historical; guard anyway
      int levelIndex = MathMax(sameCount, 0);
      double lot = InpLot * PowSafe(InpMultiplierAvg, levelIndex);
      if(baseDir > 0) OpenBuy(lot); else OpenSell(lot);
   }
}

void TryHedging(const BasketInfo &bi, int baseDir)
{
   if(!InpUseHedging) return;
   if(baseDir == 0) return;

   // hedging aktif ketika max averaging tercapai
   int sameCount = (baseDir > 0 ? bi.buyCount : bi.sellCount);
   if(sameCount < InpMaxAvg) return; // belum saatnya hedge

   int oppCount  = (baseDir > 0 ? bi.sellCount : bi.buyCount);
   if(oppCount >= InpMaxHedge) return; // capai max hedge

   double lastOpp = (baseDir > 0 ? bi.lastSellPrice : bi.lastBuyPrice);
   double price   = (baseDir > 0 ? SymbolInfoDouble(g_symbol, SYMBOL_ASK) : SymbolInfoDouble(g_symbol, SYMBOL_BID));

   bool enoughDistance = false;
   if(baseDir > 0) // base BUY -> hedge SELL when price naik di atas last sell by jarak
      enoughDistance = (price - lastOpp) >= (InpJarakHedgePts * g_point);
   else            // base SELL -> hedge BUY when price turun di bawah last buy by jarak
      enoughDistance = (lastOpp - price) >= (InpJarakHedgePts * g_point);

   if(enoughDistance || oppCount == 0)
   {
      int levelIndex = MathMax(oppCount, 0);
      double lot = InpLotHedge * PowSafe(InpMultiplierHedge, levelIndex);
      if(baseDir > 0) OpenSell(lot); else OpenBuy(lot);
   }
}

void MaybeResumeAveragingAfterMaxHedge(const BasketInfo &bi, int baseDir)
{
   // Averaging akan buka kembali ketika Max hedge tercapai
   if(!InpUseAveraging || baseDir == 0) return;
   if(!InpUseHedging) return;

   int oppCount = (baseDir > 0 ? bi.sellCount : bi.buyCount);
   if(oppCount < InpMaxHedge) return; // belum capai max hedge

   // Allow averaging again while hedges exist, using the same distance rule from the last same-side entry
   int sameCount = (baseDir > 0 ? bi.buyCount : bi.sellCount);
   if(sameCount >= InpMaxAvg) return;

   double lastEntry = (baseDir > 0 ? bi.lastBuyPrice : bi.lastSellPrice);
   double price = (baseDir > 0 ? SymbolInfoDouble(g_symbol, SYMBOL_BID) : SymbolInfoDouble(g_symbol, SYMBOL_ASK));

   bool enoughDistance = false;
   if(baseDir > 0)
      enoughDistance = (lastEntry - price) >= (InpJarakAveragingPts * g_point);
   else
      enoughDistance = (price - lastEntry) >= (InpJarakAveragingPts * g_point);

   if(enoughDistance)
   {
      int levelIndex = MathMax(sameCount, 0);
      double lot = InpLot * PowSafe(InpMultiplierAvg, levelIndex);
      if(baseDir > 0) OpenBuy(lot); else OpenSell(lot);
   }
}

void TryCloseByMoney(const BasketInfo &bi)
{
   if(InpUseTPMoney && bi.netProfit >= InpTPMoney)
   {
      CloseAllByMagic();
      return;
   }
   if(InpUseSLMoney && bi.netProfit <= -MathAbs(InpSLMoney))
   {
      CloseAllByMagic();
      return;
   }
}

void TryCloseByTpAvg(const BasketInfo &bi, int baseDir)
{
   if(InpUseTPMoney) return; // if money TP is used, it overrides TP Avg
   if(baseDir == 0) return;
   if(InpTpAvgPts <= 0) return;

   double priceBid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double priceAsk = SymbolInfoDouble(g_symbol, SYMBOL_ASK);

   if(baseDir > 0 && bi.buyCount > 0)
   {
      double target = bi.buyWeightedPrice + InpTpAvgPts * g_point;
      if(priceBid >= target) CloseAllByMagic();
   }
   else if(baseDir < 0 && bi.sellCount > 0)
   {
      double target = bi.sellWeightedPrice - InpTpAvgPts * g_point;
      if(priceAsk <= target) CloseAllByMagic();
   }
}

//======================== Event Handlers ================
int OnInit()
{
   g_symbol = _Symbol;
   g_point  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_trade.SetExpertMagicNumber((long)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(!IsTradeAllowed()) return;
   if(!SymbolInfoTick(g_symbol, _Tick)) return;

   BasketInfo bi = GetBasket();

   // If there are no positions, EA waits for user's first OP to set base direction.
   if(PositionsByMagic() == 0)
      return;

   int baseDir = DetectBaseDirection();

   // Money-based close first (hard stop/target)
   TryCloseByMoney(bi);

   // TP Avg close (if enabled)
   TryCloseByTpAvg(bi, baseDir);

   // Entry logic
   // 1) Averaging while not reached max
   TryAveraging(bi, baseDir);

   // 2) Hedging when max averaging reached
   TryHedging(bi, baseDir);

   // 3) Resume averaging when max hedge reached
   MaybeResumeAveragingAfterMaxHedge(bi, baseDir);
}

void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
