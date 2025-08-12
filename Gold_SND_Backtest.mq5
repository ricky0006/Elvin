//+------------------------------------------------------------------+
//|                                        Gold_SND_Backtest.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Gold SND EA Backtest Version"
#property indicator_chart_window

// Input Parameters (same as main EA)
input group "=== EA Settings ==="
input string   EA_Name = "Gold SND EA Backtest v1.0";
input int      Magic_Number = 12345;
input double  Lot_Size = 0.01;
input int     Max_Orders = 10;
input double  Max_Lot = 1.0;

input group "=== Supply & Demand Settings ==="
input int      SND_Lookback = 50;
input double  SND_Threshold = 0.0005;
input int     Zone_Expiry = 24;

input group "=== Averaging Settings ==="
input double  Averaging_Multiplier = 1.5;
input double  Averaging_Step = 0.0002;
input int     Max_Averaging = 5;

input group "=== Hedging Settings ==="
input bool    Enable_Hedging = true;
input double  Hedging_Trigger = -100;
input double  Hedging_Lot = 0.02;

input group "=== Risk Management ==="
input double  Stop_Loss = 0.0050;
input double  Take_Profit = 0.0100;
input double  Max_Floating = 500;

input group "=== Backtest Settings ==="
input bool    Enable_Backtest = true;
input datetime Start_Date = D'2024.01.01';
input datetime End_Date = D'2024.12.31';
input bool    Show_Statistics = true;

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

// Backtest Statistics
struct BacktestStats {
    int totalTrades;
    int winningTrades;
    int losingTrades;
    double totalProfit;
    double totalLoss;
    double maxDrawdown;
    double winRate;
    double profitFactor;
    double averageWin;
    double averageLoss;
    datetime startTime;
    datetime endTime;
};

BacktestStats stats;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize arrays
    ArrayResize(zones, 0);
    
    // Initialize backtest statistics
    InitializeStats();
    
    // Create display labels
    CreateLabels();
    
    // Set magic number
    Comment("Gold SND EA Backtest Initialized Successfully");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Remove all labels
    DeleteLabels();
    
    // Show final statistics
    if(Show_Statistics) {
        ShowFinalStats();
    }
    
    Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check if we're in backtest period
    if(!IsInBacktestPeriod()) return;
    
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
    
    // Update backtest statistics
    UpdateStats();
}

//+------------------------------------------------------------------+
//| Initialize backtest statistics                                   |
//+------------------------------------------------------------------+
void InitializeStats() {
    stats.totalTrades = 0;
    stats.winningTrades = 0;
    stats.losingTrades = 0;
    stats.totalProfit = 0;
    stats.totalLoss = 0;
    stats.maxDrawdown = 0;
    stats.winRate = 0;
    stats.profitFactor = 0;
    stats.averageWin = 0;
    stats.averageLoss = 0;
    stats.startTime = Start_Date;
    stats.endTime = End_Date;
}

//+------------------------------------------------------------------+
//| Check if current time is in backtest period                     |
//+------------------------------------------------------------------+
bool IsInBacktestPeriod() {
    if(!Enable_Backtest) return true;
    
    datetime currentTime = TimeCurrent();
    return (currentTime >= Start_Date && currentTime <= End_Date);
}

//+------------------------------------------------------------------+
//| Update backtest statistics                                       |
//+------------------------------------------------------------------+
void UpdateStats() {
    // Count closed positions
    for(int i = 0; i < HistoryDealsTotal(); i++) {
        if(HistoryDealSelect(HistoryDealGetTicket(i))) {
            if(HistoryDealGetString(HistoryDealGetTicket(i), DEAL_SYMBOL) == Symbol() &&
               HistoryDealGetInteger(HistoryDealGetTicket(i), DEAL_MAGIC) == Magic_Number) {
                
                double profit = HistoryDealGetDouble(HistoryDealGetTicket(i), DEAL_PROFIT);
                
                if(profit > 0) {
                    stats.winningTrades++;
                    stats.totalProfit += profit;
                } else if(profit < 0) {
                    stats.losingTrades++;
                    stats.totalLoss += MathAbs(profit);
                }
            }
        }
    }
    
    stats.totalTrades = stats.winningTrades + stats.losingTrades;
    
    if(stats.totalTrades > 0) {
        stats.winRate = (double)stats.winningTrades / stats.totalTrades * 100;
    }
    
    if(stats.totalLoss > 0) {
        stats.profitFactor = stats.totalProfit / stats.totalLoss;
    }
    
    if(stats.winningTrades > 0) {
        stats.averageWin = stats.totalProfit / stats.winningTrades;
    }
    
    if(stats.losingTrades > 0) {
        stats.averageLoss = stats.totalLoss / stats.losingTrades;
    }
    
    // Calculate max drawdown
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double currentDrawdown = currentBalance - currentEquity;
    
    if(currentDrawdown > stats.maxDrawdown) {
        stats.maxDrawdown = currentDrawdown;
    }
}

//+------------------------------------------------------------------+
//| Show final backtest statistics                                   |
//+------------------------------------------------------------------+
void ShowFinalStats() {
    string statsText = "=== BACKTEST STATISTICS ===\n";
    statsText += "Period: " + TimeToString(stats.startTime) + " to " + TimeToString(stats.endTime) + "\n";
    statsText += "Total Trades: " + IntegerToString(stats.totalTrades) + "\n";
    statsText += "Winning Trades: " + IntegerToString(stats.winningTrades) + "\n";
    statsText += "Losing Trades: " + IntegerToString(stats.losingTrades) + "\n";
    statsText += "Win Rate: " + DoubleToString(stats.winRate, 2) + "%\n";
    statsText += "Total Profit: " + DoubleToString(stats.totalProfit, 2) + "\n";
    statsText += "Total Loss: " + DoubleToString(stats.totalLoss, 2) + "\n";
    statsText += "Profit Factor: " + DoubleToString(stats.profitFactor, 2) + "\n";
    statsText += "Average Win: " + DoubleToString(stats.averageWin, 2) + "\n";
    statsText += "Average Loss: " + DoubleToString(stats.averageLoss, 2) + "\n";
    statsText += "Max Drawdown: " + DoubleToString(stats.maxDrawdown, 2) + "\n";
    
    MessageBox(statsText, "Backtest Results", MB_OK|MB_ICONINFORMATION);
}

//+------------------------------------------------------------------+
//| Create display labels                                            |
//+------------------------------------------------------------------+
void CreateLabels() {
    string prefix = "GoldSND_";
    
    CreateLabel(prefix + "EA_Name", EA_Name, 20, 20);
    CreateLabel(prefix + "Account", "Account: ", 20, 40);
    CreateLabel(prefix + "BuyLots", "Buy Lots: ", 20, 60);
    CreateLabel(prefix + "SellLots", "Sell Lots: ", 20, 80);
    CreateLabel(prefix + "LotDiff", "Lot Diff: ", 20, 100);
    CreateLabel(prefix + "BuyOrders", "Buy Orders: ", 20, 120);
    CreateLabel(prefix + "SellOrders", "Sell Orders: ", 20, 140);
    CreateLabel(prefix + "Balance", "Balance: ", 20, 160);
    CreateLabel(prefix + "Equity", "Equity: ", 20, 180);
    CreateLabel(prefix + "Floating", "Floating: ", 20, 200);
    CreateLabel(prefix + "MaxFloat", "Max Float: ", 20, 220);
    
    // Add backtest specific labels
    CreateLabel(prefix + "Backtest", "BACKTEST MODE", 20, 240);
    CreateLabel(prefix + "Period", "Period: ", 20, 260);
    CreateLabel(prefix + "Stats", "Stats: ", 20, 280);
}

//+------------------------------------------------------------------+
//| Create individual label                                          |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y) {
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
}

//+------------------------------------------------------------------+
//| Delete all labels                                                |
//+------------------------------------------------------------------+
void DeleteLabels() {
    string prefix = "GoldSND_";
    string names[] = {"EA_Name", "Account", "BuyLots", "SellLots", "LotDiff", 
                      "BuyOrders", "SellOrders", "Balance", "Equity", "Floating", "MaxFloat",
                      "Backtest", "Period", "Stats"};
    
    for(int i = 0; i < ArraySize(names); i++) {
        ObjectDelete(0, prefix + names[i]);
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
    
    // Update backtest specific display
    ObjectSetString(0, prefix + "Period", OBJPROP_TEXT, 
                   "Period: " + TimeToString(Start_Date) + " to " + TimeToString(End_Date));
    ObjectSetString(0, prefix + "Stats", OBJPROP_TEXT, 
                   "Stats: " + IntegerToString(stats.totalTrades) + " trades, " + 
                   DoubleToString(stats.winRate, 1) + "% win rate");
}

// Include all other functions from the main EA here...
// (Copy all the remaining functions from Gold_SND_EA.mq5)