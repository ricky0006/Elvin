//+------------------------------------------------------------------+
//|                                              Gold_SND_EA.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Gold Supply and Demand EA with Averaging and Hedging"
#property indicator_chart_window

// Input Parameters
input group "=== EA Settings ==="
input string   EA_Name = "Gold SND EA v1.0";
input int      Magic_Number = 12345;
input double  Lot_Size = 0.01;
input int     Max_Orders = 10;
input double  Max_Lot = 1.0;

input group "=== Supply & Demand Settings ==="
input int      SND_Lookback = 50;        // Lookback period for SND zones
input double  SND_Threshold = 0.0005;    // Minimum price movement for SND
input int     Zone_Expiry = 24;          // Zone expiry in hours

input group "=== Averaging Settings ==="
input double  Averaging_Multiplier = 1.5; // Lot multiplier for averaging
input double  Averaging_Step = 0.0002;    // Price step for averaging
input int     Max_Averaging = 5;          // Maximum averaging orders

input group "=== Hedging Settings ==="
input bool    Enable_Hedging = true;      // Enable hedging strategy
input double  Hedging_Trigger = -100;     // Floating loss to trigger hedging
input double  Hedging_Lot = 0.02;        // Lot size for hedging

input group "=== Risk Management ==="
input double  Stop_Loss = 0.0050;         // Stop Loss in price
input double  Take_Profit = 0.0100;      // Take Profit in price
input double  Max_Floating = 500;         // Maximum floating loss

input group "=== Display Settings ==="
input color   Label_Color = clrWhite;
input int     Label_Size = 8;
input int     Label_X = 20;
input int     Label_Y = 20;

// Global Variables
struct SNDZone {
    double high;
    double low;
    datetime time;
    bool isSupply;
    bool active;
};

SNDZone zones[];
int totalBuyOrders = 0;
int totalSellOrders = 0;
double totalBuyLots = 0;
double totalSellLots = 0;
double maxFloating = 0;
datetime lastZoneCheck = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize arrays
    ArrayResize(zones, 0);
    
    // Create display labels
    CreateLabels();
    
    // Set magic number
    Comment("Gold SND EA Initialized Successfully");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Remove all labels
    DeleteLabels();
    Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Update account information
    UpdateAccountInfo();
    
    // Check for new SND zones every hour
    if(TimeCurrent() - lastZoneCheck >= 3600) {
        ScanForSNDZones();
        lastZoneCheck = TimeCurrent();
    }
    
    // Check for trading opportunities
    CheckTradingOpportunities();
    
    // Manage existing positions
    ManagePositions();
    
    // Update display
    UpdateDisplay();
}

//+------------------------------------------------------------------+
//| Create display labels                                            |
//+------------------------------------------------------------------+
void CreateLabels() {
    string prefix = "GoldSND_";
    
    CreateLabel(prefix + "EA_Name", EA_Name, Label_X, Label_Y);
    CreateLabel(prefix + "Account", "Account: ", Label_X, Label_Y + 20);
    CreateLabel(prefix + "BuyLots", "Buy Lots: ", Label_X, Label_Y + 40);
    CreateLabel(prefix + "SellLots", "Sell Lots: ", Label_X, Label_Y + 60);
    CreateLabel(prefix + "LotDiff", "Lot Diff: ", Label_X, Label_Y + 80);
    CreateLabel(prefix + "BuyOrders", "Buy Orders: ", Label_X, Label_Y + 100);
    CreateLabel(prefix + "SellOrders", "Sell Orders: ", Label_X, Label_Y + 120);
    CreateLabel(prefix + "Balance", "Balance: ", Label_X, Label_Y + 140);
    CreateLabel(prefix + "Equity", "Equity: ", Label_X, Label_Y + 160);
    CreateLabel(prefix + "Floating", "Floating: ", Label_X, Label_Y + 180);
    CreateLabel(prefix + "MaxFloat", "Max Float: ", Label_X, Label_Y + 200);
}

//+------------------------------------------------------------------+
//| Create individual label                                          |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y) {
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_COLOR, Label_Color);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, Label_Size);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
}

//+------------------------------------------------------------------+
//| Delete all labels                                                |
//+------------------------------------------------------------------+
void DeleteLabels() {
    string prefix = "GoldSND_";
    string names[] = {"EA_Name", "Account", "BuyLots", "SellLots", "LotDiff", 
                      "BuyOrders", "SellOrders", "Balance", "Equity", "Floating", "MaxFloat"};
    
    for(int i = 0; i < ArraySize(names); i++) {
        ObjectDelete(0, prefix + names[i]);
    }
}

//+------------------------------------------------------------------+
//| Update account information                                       |
//+------------------------------------------------------------------+
void UpdateAccountInfo() {
    totalBuyOrders = 0;
    totalSellOrders = 0;
    totalBuyLots = 0;
    totalSellLots = 0;
    
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetString(POSITION_SYMBOL) == Symbol() && 
               PositionGetInteger(POSITION_MAGIC) == Magic_Number) {
                
                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                    totalBuyOrders++;
                    totalBuyLots += PositionGetDouble(POSITION_VOLUME);
                } else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                    totalSellOrders++;
                    totalSellLots += PositionGetDouble(POSITION_VOLUME);
                }
            }
        }
    }
    
    // Update max floating
    double currentFloating = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
    if(currentFloating < maxFloating) {
        maxFloating = currentFloating;
    }
}

//+------------------------------------------------------------------+
//| Scan for Supply and Demand zones                                 |
//+------------------------------------------------------------------+
void ScanForSNDZones() {
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    int copied = CopyHigh(Symbol(), PERIOD_H1, 0, SND_Lookback, high);
    if(copied != SND_Lookback) return;
    
    copied = CopyLow(Symbol(), PERIOD_H1, 0, SND_Lookback, low);
    if(copied != SND_Lookback) return;
    
    copied = CopyClose(Symbol(), PERIOD_H1, 0, SND_Lookback, close);
    if(copied != SND_Lookback) return;
    
    // Clear old zones
    ArrayResize(zones, 0);
    
    // Find supply zones (resistance)
    for(int i = 2; i < SND_Lookback - 2; i++) {
        if(high[i] > high[i-1] && high[i] > high[i-2] && 
           high[i] > high[i+1] && high[i] > high[i+2] &&
           MathAbs(high[i] - high[i-1]) > SND_Threshold) {
            
            SNDZone zone;
            zone.high = high[i];
            zone.low = high[i] - SND_Threshold;
            zone.time = TimeCurrent() - i * PeriodSeconds(PERIOD_H1);
            zone.isSupply = true;
            zone.active = true;
            
            ArrayResize(zones, ArraySize(zones) + 1);
            zones[ArraySize(zones) - 1] = zone;
        }
    }
    
    // Find demand zones (support)
    for(int i = 2; i < SND_Lookback - 2; i++) {
        if(low[i] < low[i-1] && low[i] < low[i-2] && 
           low[i] < low[i+1] && low[i] < low[i+2] &&
           MathAbs(low[i] - low[i-1]) > SND_Threshold) {
            
            SNDZone zone;
            zone.high = low[i] + SND_Threshold;
            zone.low = low[i];
            zone.time = TimeCurrent() - i * PeriodSeconds(PERIOD_H1);
            zone.isSupply = false;
            zone.active = true;
            
            ArrayResize(zones, ArraySize(zones) + 1);
            zones[ArraySize(zones) - 1] = zone;
        }
    }
}

//+------------------------------------------------------------------+
//| Check for trading opportunities                                  |
//+------------------------------------------------------------------+
void CheckTradingOpportunities() {
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    for(int i = 0; i < ArraySize(zones); i++) {
        if(!zones[i].active) continue;
        
        // Check if zone is expired
        if(TimeCurrent() - zones[i].time > Zone_Expiry * 3600) {
            zones[i].active = false;
            continue;
        }
        
        // Check if price is in zone
        if(currentPrice >= zones[i].low && currentPrice <= zones[i].high) {
            if(zones[i].isSupply && totalSellOrders < Max_Orders) {
                // Open sell order at supply zone
                OpenOrder(ORDER_TYPE_SELL, Lot_Size, "SND Supply");
                zones[i].active = false; // Use zone only once
            } else if(!zones[i].isSupply && totalBuyOrders < Max_Orders) {
                // Open buy order at demand zone
                OpenOrder(ORDER_TYPE_BUY, Lot_Size, "SND Demand");
                zones[i].active = false; // Use zone only once
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open new order                                                   |
//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE type, double lot, string comment) {
    double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                                        SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    double sl = 0, tp = 0;
    if(type == ORDER_TYPE_BUY) {
        sl = price - Stop_Loss;
        tp = price + Take_Profit;
    } else {
        sl = price + Stop_Loss;
        tp = price - Take_Profit;
    }
    
    MqlTradeRequest request = {};
    request.action = TRADE_ACTION_DEAL;
    request.symbol = Symbol();
    request.volume = lot;
    request.type = type;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = Magic_Number;
    request.comment = comment;
    
    MqlTradeResult result = {};
    OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions() {
    double currentFloating = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Check for averaging opportunities
    CheckAveraging();
    
    // Check for hedging
    if(Enable_Hedging && currentFloating < Hedging_Trigger) {
        CheckHedging();
    }
    
    // Check for max floating loss
    if(currentFloating < -Max_Floating) {
        CloseAllPositions();
    }
}

//+------------------------------------------------------------------+
//| Check for averaging opportunities                                |
//+------------------------------------------------------------------+
void CheckAveraging() {
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetString(POSITION_SYMBOL) == Symbol() && 
               PositionGetInteger(POSITION_MAGIC) == Magic_Number) {
                
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                                     SymbolInfoDouble(Symbol(), SYMBOL_BID) : 
                                     SymbolInfoDouble(Symbol(), SYMBOL_ASK);
                
                double priceDiff = MathAbs(currentPrice - openPrice);
                
                if(priceDiff > Averaging_Step) {
                    // Count existing averaging orders
                    int avgCount = CountAveragingOrders(PositionGetTicket(i));
                    
                    if(avgCount < Max_Averaging) {
                        double newLot = Lot_Size * MathPow(Averaging_Multiplier, avgCount + 1);
                        if(newLot <= Max_Lot) {
                            ENUM_ORDER_TYPE type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                                                  ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                            OpenOrder(type, newLot, "Averaging " + IntegerToString(avgCount + 1));
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Count averaging orders for a position                           |
//+------------------------------------------------------------------+
int CountAveragingOrders(ulong ticket) {
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetString(POSITION_SYMBOL) == Symbol() && 
               PositionGetInteger(POSITION_MAGIC) == Magic_Number) {
                string comment = PositionGetString(POSITION_COMMENT);
                if(StringFind(comment, "Averaging") >= 0) {
                    count++;
                }
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Check for hedging opportunities                                 |
//+------------------------------------------------------------------+
void CheckHedging() {
    if(totalBuyLots > totalSellLots) {
        // Open sell hedge
        double hedgeLot = MathMin(Hedging_Lot, totalBuyLots - totalSellLots);
        if(hedgeLot > 0) {
            OpenOrder(ORDER_TYPE_SELL, hedgeLot, "Hedging");
        }
    } else if(totalSellLots > totalBuyLots) {
        // Open buy hedge
        double hedgeLot = MathMin(Hedging_Lot, totalSellLots - totalBuyLots);
        if(hedgeLot > 0) {
            OpenOrder(ORDER_TYPE_BUY, hedgeLot, "Hedging");
        }
    }
}

//+------------------------------------------------------------------+
//| Close all positions                                             |
//+------------------------------------------------------------------+
void CloseAllPositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetString(POSITION_SYMBOL) == Symbol() && 
               PositionGetInteger(POSITION_MAGIC) == Magic_Number) {
                
                MqlTradeRequest request = {};
                request.action = TRADE_ACTION_DEAL;
                request.symbol = Symbol();
                request.volume = PositionGetDouble(POSITION_VOLUME);
                request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                              ORDER_TYPE_SELL : ORDER_TYPE_BUY;
                request.price = (request.type == ORDER_TYPE_BUY) ? 
                               SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                               SymbolInfoDouble(Symbol(), SYMBOL_BID);
                request.deviation = 10;
                request.magic = Magic_Number;
                request.comment = "Emergency Close";
                
                MqlTradeResult result = {};
                OrderSend(request, result);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update display information                                       |
//+------------------------------------------------------------------+
void UpdateDisplay() {
    string prefix = "GoldSND_";
    
    ObjectSetString(0, prefix + "Account", OBJPROP_TEXT, 
                   "Account: " + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)));
    ObjectSetString(0, prefix + "BuyLots", OBJPROP_TEXT, 
                   "Buy Lots: " + DoubleToString(totalBuyLots, 2));
    ObjectSetString(0, prefix + "SellLots", OBJPROP_TEXT, 
                   "Sell Lots: " + DoubleToString(totalSellLots, 2));
    ObjectSetString(0, prefix + "LotDiff", OBJPROP_TEXT, 
                   "Lot Diff: " + DoubleToString(totalBuyLots - totalSellLots, 2));
    ObjectSetString(0, prefix + "BuyOrders", OBJPROP_TEXT, 
                   "Buy Orders: " + IntegerToString(totalBuyOrders));
    ObjectSetString(0, prefix + "SellOrders", OBJPROP_TEXT, 
                   "Sell Orders: " + IntegerToString(totalSellOrders));
    ObjectSetString(0, prefix + "Balance", OBJPROP_TEXT, 
                   "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
    ObjectSetString(0, prefix + "Equity", OBJPROP_TEXT, 
                   "Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
    
    double currentFloating = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
    color floatingColor = (currentFloating >= 0) ? clrLime : clrRed;
    
    ObjectSetString(0, prefix + "Floating", OBJPROP_TEXT, 
                   "Floating: " + DoubleToString(currentFloating, 2));
    ObjectSetInteger(0, prefix + "Floating", OBJPROP_COLOR, floatingColor);
    
    ObjectSetString(0, prefix + "MaxFloat", OBJPROP_TEXT, 
                   "Max Float: " + DoubleToString(maxFloating, 2));
}