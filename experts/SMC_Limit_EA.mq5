#property copyright   ""
#property link        ""
#property version     "1.0"
#property description "SMC Limit EA: Places Buy Limit/Sell Limit on SMC order blocks with risk management. Tuned for XAUUSD (Gold)."
#property strict

input string   InpSymbol                 = "";           // Symbol (empty = current)
input ENUM_TIMEFRAMES InpTimeframe       = PERIOD_M15;   // Analysis timeframe
input int      InpSwingLeftRight         = 3;            // Swing detection left/right bars
input int      InpOBLookbackBars         = 20;           // Max bars back to find last opposite candle before BOS
input double   InpBOSBufferPoints        = 50;           // BOS buffer (points) beyond swing
input bool     InpUseMidOfOB             = true;         // Use 50% of OB candle as entry (mitigation)
input double   InpEntryRefinePercent     = 50.0;         // Entry refine percent of OB range [0..100]

input double   InpRiskPercent            = 1.0;          // Risk per trade (% of equity)
input double   InpRiskRR                 = 2.0;          // Take Profit Risk-Reward (TP = RR * risk)
input int      InpATRPeriod              = 14;           // ATR period for optional SL buffer
input double   InpATRSpecSLMultiplier    = 0.0;          // ATR multiplier added to OB edge for SL

input int      InpMaxPendingPerDirection = 1;            // Max simultaneous pending orders per direction
input int      InpCooldownBars           = 5;            // Cooldown bars after placing an order
input int      InpMinDistancePoints      = 100;          // Min distance from current price for pending (points)
input int      InpMaxSpreadPoints        = 250;          // Max spread allowed (points)

input bool     InpUseSessionFilter       = true;         // Use trading session filter
input int      InpSessionStartHour       = 6;            // Session start hour (broker time)
input int      InpSessionEndHour         = 22;           // Session end hour (broker time)

input bool     InpUseBreakEven           = true;         // Move SL to BE at 1R
input double   InpBreakEvenOffsetPoints  = 10;           // BE offset (points)
input bool     InpUseTrailingATR         = false;        // ATR trailing after BE
input double   InpTrailingATRMul         = 1.5;          // ATR multiplier for trailing

input ulong    InpMagicNumber            = 26012025;     // Magic number
input string   InpOrderComment           = "SMC_Limit_EA"; // Order comment

// Internal state
string    g_symbol;
ENUM_TIMEFRAMES g_tf;
double    g_point, g_tick_size, g_tick_value;
int       g_digits;
double    g_min_lot, g_max_lot, g_lot_step;

// Last processed BOS/OB to avoid duplicates
static datetime g_lastBullSignalBarTime = 0;
static datetime g_lastBearSignalBarTime = 0;
static int      g_cooldownBarsRemainingBull = 0;
static int      g_cooldownBarsRemainingBear = 0;

struct OrderBlock
{
  bool     isBullish;
  int      barIndex;       // Index in rates[] for the OB candle
  datetime barTime;
  double   high;
  double   low;
  double   open;
  double   close;
  double   zoneTop;        // For bullish: open (or body top), for bearish: open
  double   zoneBottom;     // For bullish: low, for bearish: high
  double   entryPrice;     // Refined entry (e.g., 50%)
  double   stopPrice;      // SL beyond the OB
  double   takeProfit;     // TP using RR
};

int OnInit()
{
  g_symbol = (InpSymbol == "" ? _Symbol : InpSymbol);
  g_tf = InpTimeframe;

  g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
  g_point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
  g_tick_size = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
  g_tick_value = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);

  g_min_lot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
  g_max_lot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
  g_lot_step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

  return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
  if(!IsTradeAllowedNow()) return;
  if(!IsSpreadOk()) return;

  ManageOpenPositions();
  ScanAndPlaceOrders();
}

bool IsTradeAllowedNow()
{
  if(!InpUseSessionFilter) return true;
  datetime cur = TimeCurrent();
  MqlDateTime dt; TimeToStruct(cur, dt);
  int hour = dt.hour;
  if(InpSessionStartHour <= InpSessionEndHour)
    return (hour >= InpSessionStartHour && hour < InpSessionEndHour);
  // Session that spans midnight
  return (hour >= InpSessionStartHour || hour < InpSessionEndHour);
}

bool IsSpreadOk()
{
  double spread_points = (SymbolInfoDouble(g_symbol, SYMBOL_ASK) - SymbolInfoDouble(g_symbol, SYMBOL_BID)) / g_point;
  return spread_points <= InpMaxSpreadPoints;
}

// Data fetch
int LoadRates(MqlRates &rates[], int bars_needed)
{
  ArraySetAsSeries(rates, true);
  int copied = CopyRates(g_symbol, g_tf, 0, bars_needed, rates);
  return copied;
}

// Swing detection: return true if bar i is swing high/low with given left/right
bool IsSwingHigh(const MqlRates &rates[], int i, int leftRight)
{
  for(int k=1; k<=leftRight; ++k)
  {
    if(i+k >= ArraySize(rates) || i-k < 0) return false;
    if(!(rates[i].high > rates[i-k].high && rates[i].high > rates[i+k].high))
      return false;
  }
  return true;
}

bool IsSwingLow(const MqlRates &rates[], int i, int leftRight)
{
  for(int k=1; k<=leftRight; ++k)
  {
    if(i+k >= ArraySize(rates) || i-k < 0) return false;
    if(!(rates[i].low < rates[i-k].low && rates[i].low < rates[i+k].low))
      return false;
  }
  return true;
}

// Find most recent swing high and low indices before a given start index
bool FindRecentSwingHighLow(const MqlRates &rates[], int startIndex, int leftRight, int &swingHighIdx, int &swingLowIdx)
{
  swingHighIdx = -1; swingLowIdx = -1;
  int limit = MathMin(startIndex + 200, ArraySize(rates) - 1);
  for(int i = startIndex + 1; i <= limit; ++i)
  {
    if(swingHighIdx == -1 && IsSwingHigh(rates, i, leftRight)) swingHighIdx = i;
    if(swingLowIdx == -1 && IsSwingLow(rates, i, leftRight)) swingLowIdx = i;
    if(swingHighIdx != -1 && swingLowIdx != -1) break;
  }
  return (swingHighIdx != -1 && swingLowIdx != -1);
}

// Detect BOS and corresponding OB; returns true and fills ob if a new signal is detected
bool DetectBOSAndOB(const MqlRates &rates[], int leftRight, int obLookback, double bosBufferPoints, OrderBlock &obOut)
{
  const int bars = ArraySize(rates);
  if(bars < 200) return false;

  int swingHighIdx, swingLowIdx;
  if(!FindRecentSwingHighLow(rates, 1, leftRight, swingHighIdx, swingLowIdx)) return false;

  double bosBuffer = bosBufferPoints * g_point;

  // Check bullish BOS: last closed bar close > swing high + buffer
  bool bullishBOS = (rates[1].close > (rates[swingHighIdx].high + bosBuffer));
  // Check bearish BOS: last closed bar close < swing low - buffer
  bool bearishBOS = (rates[1].close < (rates[swingLowIdx].low - bosBuffer));

  if(!bullishBOS && !bearishBOS) return false;

  if(bullishBOS)
  {
    // Find last bearish candle strictly before BOS within lookback
    int start = MathMin(1 + obLookback, bars - 2);
    for(int i = 2; i <= start; ++i)
    {
      if(rates[i].close < rates[i].open) // bearish candle
      {
        obOut.isBullish = true;
        obOut.barIndex = i;
        obOut.barTime = rates[i].time;
        obOut.high = rates[i].high;
        obOut.low = rates[i].low;
        obOut.open = rates[i].open;
        obOut.close = rates[i].close;
        // OB zone: open to low (full candle)
        obOut.zoneTop = rates[i].open;
        obOut.zoneBottom = rates[i].low;

        double entry = RefineEntry(obOut.zoneTop, obOut.zoneBottom);
        obOut.entryPrice = entry;

        double sl = obOut.zoneBottom - (InpATRSpecSLMultiplier <= 0.0 ? 0.0 : (GetATR(g_tf, InpATRPeriod) * InpATRSpecSLMultiplier));
        obOut.stopPrice = NormalizePrice(sl);

        double tp = entry + InpRiskRR * (entry - obOut.stopPrice);
        obOut.takeProfit = NormalizePrice(tp);

        return true; // First valid OB found (closest to BOS)
      }
    }
  }

  if(bearishBOS)
  {
    // Find last bullish candle strictly before BOS within lookback
    int start = MathMin(1 + obLookback, bars - 2);
    for(int i = 2; i <= start; ++i)
    {
      if(rates[i].close > rates[i].open) // bullish candle
      {
        obOut.isBullish = false;
        obOut.barIndex = i;
        obOut.barTime = rates[i].time;
        obOut.high = rates[i].high;
        obOut.low = rates[i].low;
        obOut.open = rates[i].open;
        obOut.close = rates[i].close;
        // OB zone: open to high
        obOut.zoneTop = rates[i].high;
        obOut.zoneBottom = rates[i].open;

        double entry = RefineEntry(obOut.zoneTop, obOut.zoneBottom);
        obOut.entryPrice = entry;

        double sl = obOut.zoneTop + (InpATRSpecSLMultiplier <= 0.0 ? 0.0 : (GetATR(g_tf, InpATRPeriod) * InpATRSpecSLMultiplier));
        obOut.stopPrice = NormalizePrice(sl);

        double tp = entry - InpRiskRR * (obOut.stopPrice - entry);
        obOut.takeProfit = NormalizePrice(tp);

        return true;
      }
    }
  }

  return false;
}

// Entry refinement to a percentage of OB range
double RefineEntry(double zoneTop, double zoneBottom)
{
  // For bullish: zoneTop > zoneBottom typically (open above low)
  // For bearish: zoneTop > zoneBottom (high above open)
  double range = zoneTop - zoneBottom;
  double pct = MathMax(0.0, MathMin(100.0, InpEntryRefinePercent));
  double entry = zoneBottom + (pct / 100.0) * range;
  return NormalizePrice(entry);
}

// ATR
double GetATR(ENUM_TIMEFRAMES tf, int period)
{
  int handle = iATR(g_symbol, tf, period);
  if(handle == INVALID_HANDLE) return 0.0;
  double atr[]; ArraySetAsSeries(atr, true);
  int copied = CopyBuffer(handle, 0, 0, 3, atr);
  IndicatorRelease(handle);
  if(copied <= 0) return 0.0;
  return atr[0];
}

// Normalize price to tick size
double NormalizePrice(double price)
{
  double ticks = MathRound(price / g_tick_size);
  return ticks * g_tick_size;
}

// Position and order helpers
int CountPendingByDirection(bool bullish)
{
  int total = 0;
  for(int i=0; i<(int)OrdersTotal(); ++i)
  {
    if(!OrderSelect(i, SELECT_BY_INDEX)) continue;
    if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagicNumber) continue;
    if(OrderGetString(ORDER_SYMBOL) != g_symbol) continue;
    ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
    if(bullish && type == ORDER_TYPE_BUY_LIMIT) total++;
    if(!bullish && type == ORDER_TYPE_SELL_LIMIT) total++;
  }
  return total;
}

bool HasSimilarPending(double price, bool bullish)
{
  double tol = 2.0 * g_point;
  for(int i=0; i<(int)OrdersTotal(); ++i)
  {
    if(!OrderSelect(i, SELECT_BY_INDEX)) continue;
    if(OrderGetInteger(ORDER_MAGIC) != (long)InpMagicNumber) continue;
    if(OrderGetString(ORDER_SYMBOL) != g_symbol) continue;
    ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
    if(bullish && type != ORDER_TYPE_BUY_LIMIT) continue;
    if(!bullish && type != ORDER_TYPE_SELL_LIMIT) continue;
    double p = OrderGetDouble(ORDER_PRICE_OPEN);
    if(MathAbs(p - price) <= tol) return true;
  }
  return false;
}

// Lot calculation based on % risk and stop distance
double CalculateVolumeByRisk(double entryPrice, double stopPrice)
{
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  double risk_money = equity * (InpRiskPercent / 100.0);

  double stop_distance = MathAbs(entryPrice - stopPrice); // in price
  if(stop_distance <= 0.0) return 0.0;

  // Money per lot per price unit
  // tick_value: money per tick_size for 1 lot => money per price unit = tick_value / tick_size
  double money_per_price_unit_per_lot = 0.0;
  if(g_tick_size > 0.0) money_per_price_unit_per_lot = g_tick_value / g_tick_size;
  if(money_per_price_unit_per_lot <= 0.0) return 0.0;

  double money_per_lot_for_stop = stop_distance * money_per_price_unit_per_lot;
  if(money_per_lot_for_stop <= 0.0) return 0.0;

  double vol = risk_money / money_per_lot_for_stop;

  // Fit to symbol limits
  vol = MathMax(g_min_lot, MathMin(g_max_lot, vol));
  // Round down to step
  vol = MathFloor(vol / g_lot_step) * g_lot_step;
  vol = NormalizeDouble(vol, 2);
  return vol;
}

bool PlacePending(const OrderBlock &ob)
{
  MqlTradeRequest req; ZeroMemory(req);
  MqlTradeResult  res; ZeroMemory(res);

  req.action = TRADE_ACTION_PENDING;
  req.symbol = g_symbol;
  req.magic = InpMagicNumber;
  req.comment = InpOrderComment;

  req.volume = CalculateVolumeByRisk(ob.entryPrice, ob.stopPrice);
  if(req.volume <= 0.0) return false;

  req.price = ob.entryPrice;
  req.sl = ob.stopPrice;
  req.tp = ob.takeProfit;

  if(ob.isBullish)
  {
    // Ensure buy limit below current Ask
    double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
    if(ob.entryPrice >= ask - InpMinDistancePoints * g_point) return false;
    req.type = ORDER_TYPE_BUY_LIMIT;
  }
  else
  {
    // Ensure sell limit above current Bid
    double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
    if(ob.entryPrice <= bid + InpMinDistancePoints * g_point) return false;
    req.type = ORDER_TYPE_SELL_LIMIT;
  }

  // Good-til-cancelled pending orders
  req.type_filling = ORDER_FILLING_FOK; // not relevant for pending
  req.type_time = ORDER_TIME_GTC;
  req.expiration = 0;

  bool ok = OrderSend(req, res);
  if(!ok)
  {
    PrintFormat("OrderSend failed: %d | %s", res.retcode, res.comment);
    return false;
  }

  PrintFormat("Placed %s LIMIT: ticket=%I64u price=%.2f sl=%.2f tp=%.2f vol=%.2f from OB bar %s",
              ob.isBullish ? "BUY" : "SELL",
              res.order, ob.entryPrice, ob.stopPrice, ob.takeProfit, req.volume,
              TimeToString(ob.barTime));
  return true;
}

void ScanAndPlaceOrders()
{
  // Cooldown decrement per new closed bar
  static datetime lastBarTime = 0;

  MqlRates rates[];
  int needBars = MathMax(400, InpOBLookbackBars + 50);
  int copied = LoadRates(rates, needBars);
  if(copied <= 0) return;

  if(rates[1].time != lastBarTime)
  {
    if(g_cooldownBarsRemainingBull > 0) g_cooldownBarsRemainingBull--;
    if(g_cooldownBarsRemainingBear > 0) g_cooldownBarsRemainingBear--;
    lastBarTime = rates[1].time;
  }

  OrderBlock ob;
  if(!DetectBOSAndOB(rates, InpSwingLeftRight, InpOBLookbackBars, InpBOSBufferPoints, ob))
    return;

  if(ob.isBullish)
  {
    if(g_cooldownBarsRemainingBull > 0) return;
    if(ob.barTime == g_lastBullSignalBarTime) return;
    if(CountPendingByDirection(true) >= InpMaxPendingPerDirection) return;
    if(HasSimilarPending(ob.entryPrice, true)) return;

    if(PlacePending(ob))
    {
      g_lastBullSignalBarTime = ob.barTime;
      g_cooldownBarsRemainingBull = InpCooldownBars;
    }
  }
  else
  {
    if(g_cooldownBarsRemainingBear > 0) return;
    if(ob.barTime == g_lastBearSignalBarTime) return;
    if(CountPendingByDirection(false) >= InpMaxPendingPerDirection) return;
    if(HasSimilarPending(ob.entryPrice, false)) return;

    if(PlacePending(ob))
    {
      g_lastBearSignalBarTime = ob.barTime;
      g_cooldownBarsRemainingBear = InpCooldownBars;
    }
  }
}

void ManageOpenPositions()
{
  // Break-even and ATR trailing
  for(int i=0; i<(int)PositionsTotal(); ++i)
  {
    if(!PositionSelectByIndex(i)) continue;
    if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
    if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;

    ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
    long type = PositionGetInteger(POSITION_TYPE);
    double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);
    double volume = PositionGetDouble(POSITION_VOLUME);

    double price_current = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(g_symbol, SYMBOL_BID) : SymbolInfoDouble(g_symbol, SYMBOL_ASK);

    // 1R distance approximation from SL to entry
    double oneR = MathAbs(price_open - sl);
    if(oneR <= 0.0) continue;

    bool modified = false;
    double new_sl = sl;

    if(InpUseBreakEven)
    {
      if(type == POSITION_TYPE_BUY)
      {
        if(price_current - price_open >= oneR && sl < price_open)
        {
          new_sl = NormalizePrice(price_open + InpBreakEvenOffsetPoints * g_point);
          modified = true;
        }
      }
      else if(type == POSITION_TYPE_SELL)
      {
        if(price_open - price_current >= oneR && (sl == 0.0 || sl > price_open))
        {
          new_sl = NormalizePrice(price_open - InpBreakEvenOffsetPoints * g_point);
          modified = true;
        }
      }
    }

    if(InpUseTrailingATR)
    {
      double atr = GetATR(g_tf, InpATRPeriod);
      if(atr > 0.0)
      {
        if(type == POSITION_TYPE_BUY)
        {
          double trail = NormalizePrice(price_current - atr * InpTrailingATRMul);
          if(trail > new_sl) { new_sl = trail; modified = true; }
        }
        else
        {
          double trail = NormalizePrice(price_current + atr * InpTrailingATRMul);
          if(sl == 0.0 || trail < new_sl) { new_sl = trail; modified = true; }
        }
      }
    }

    if(modified && new_sl != sl)
    {
      MqlTradeRequest req; ZeroMemory(req);
      MqlTradeResult  res; ZeroMemory(res);
      req.action = TRADE_ACTION_SLTP;
      req.symbol = g_symbol;
      req.magic = InpMagicNumber;
      req.position = ticket;
      req.sl = new_sl;
      req.tp = tp;
      if(!OrderSend(req, res))
      {
        PrintFormat("Modify SL failed: %d %s", res.retcode, res.comment);
      }
    }
  }
}