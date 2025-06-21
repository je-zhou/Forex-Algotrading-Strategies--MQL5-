//+------------------------------------------------------------------+
//|                                                   [TEMPLATE].mq5 |
//|                                           Based on Template v1.2 |
//|                                      Copyright 2025, Jerry Zhou. |
//|                                       https://www.jerryzhou.xyz/ |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Jerry Zhou."
#property link      "https://www.jerryzhou.xyz/"
#property version   "1.20"

//--- Imports
#include <Trade\Trade.mqh>

//--- Custom Types
enum TrendType {
   Uptrend = 1,
   Downtrend = 2,
   Ranging = 3,
};

//+------------------------------------------------------------------+
//| General Inputs                                                   |
//+------------------------------------------------------------------+
//--- General Settings
input group "General Settings"
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;
input int Magic = 2; //Magic (Need to use magic number for each different EA)

//--- Trade Settings
input group "Trade Settings";
input double LotSize = 0.1;
input double RiskPercent = 2.0; //RiskPercent (0 = Use Fixed LotSize)
input double TpPoints = 0; //TPoints (0 = No TP)
input double TpFactor = 0; //TpFactor (0 = Use TpPoints)
input double SlPoints = 0; //SLPoints (0 = No SL)
input double SlFactor = 0; //SlFactor (0 = Use SlPoints)
input int MaxTradesPerDay = 3; //MaxTradesPerDay (Maximum number of executed trades per day - EA cancels remaining orders when limit reached)

//--- Trailing SL Settings
input group "Trailing SL Settings";
input double TslTriggerPoints = 0; //TslTriggerPoints (0 = No Tsl)
input double TslTriggerFactor = 0.75; //TslTriggerFactor (0 = Use TslTriggerPoints)
input double TslPoints = 25; //TslPoints (0 = Breakeven)

//--- Trend Settings
input group "Trend Settings";
input bool TradeWithTrend = true; //TradeWithTrend (Forces strategy to only trade with the trend)
input ENUM_TIMEFRAMES TrendMaTimeframe = PERIOD_H1; //TrendMaTimeframe (The timeframe the trending moving average should be calculated)
input ENUM_MA_METHOD SlowTrendMaMethod = MODE_SMA; //SlowTrendMaMethod (The type of moving average used to determine the slow trend)
input int SlowTrendMaPeriod = 200; //SlowTrendMaPeriod (The period used to calculate the slow trending moving average)
input ENUM_MA_METHOD FastTrendMaMethod = MODE_SMMA; //FastTrendMaMethod (The type of moving average used to determine the fast trend)
input int FastTrendMaPeriod = 60; //FastTrendMaPeriod (The period used to calculate the fast trending moving average) 
input double RangeBuffer = 0; //RangeBuffer (Amount in points between the two moving averages to represent a ranging market)

//--- Filter Settings
input group "Time Filter Settings";
input int TimeStartHour = 7;
input int TimeStartMin = 10;
input int TimeEndHour = 15;
input int TimeEndMin = 10;

//--- Position Management Settings
input group "Position Management";
input bool AutoClosePositions = false; //AutoClosePositions (Close positions when time filter is off)
input int ClosePositionsHour = 23;
input int ClosePositionsMinute = 59;

//+------------------------------------------------------------------+
//| Strategy Specific Inputs                                         |
//+------------------------------------------------------------------+
input group "Strategy Inputs";

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
int barsTotal;
int handleSlowTrendMa;
int handleFastTrendMa;
int currentDay;
int executedTradesToday;

//+------------------------------------------------------------------+
//| Init, Deinit, OnTick                                             |
//+------------------------------------------------------------------+

int OnInit() {   
   // Initialize trade object with magic number
   trade.SetExpertMagicNumber(Magic);
   
   // Initialize trend indicators
   handleSlowTrendMa = iMA(_Symbol, TrendMaTimeframe, SlowTrendMaPeriod, 0, SlowTrendMaMethod, PRICE_CLOSE);
   handleFastTrendMa = iMA(_Symbol, TrendMaTimeframe, FastTrendMaPeriod, 0, FastTrendMaMethod, PRICE_CLOSE);
   
   // Initialize day counter
   CheckAndUpdateDay();
   
   // Debug information on startup
   Print("=== EA Initialization ===");
   Print("Magic Number: ", Magic);
   Print("Max Trades Per Day: ", MaxTradesPerDay);
   Print("Trade With Trend: ", TradeWithTrend);
   Print("========================");
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {

}

void OnTick() {
   int positions = PositionsTotalByMagic(Magic);
   int orders = OrdersTotalByMagic(Magic);

   // Check and update day counter
   CheckAndUpdateDay();

   // Check if a new position was opened (order executed)
   static int lastPositions = 0;
   if (positions > lastPositions) {
      // New position opened - increment executed trades counter
      executedTradesToday++;
      Print("Position opened! Executed trades today: ", executedTradesToday, "/", MaxTradesPerDay);
      
      // Cancel all remaining pending orders when we've reached the daily limit
      if (executedTradesToday >= MaxTradesPerDay) {
         Print("Daily trade limit reached (", MaxTradesPerDay, "). Cancelling all remaining pending orders.");
         CancelAllPendingOrders();
      }
   }
   lastPositions = positions;

   if (positions > 0) {
      //--- Monitor current positions
      ModifyPositions();
   }
   
   bool isTimeToTrade = timeToTrade();
   
   if (isTimeToTrade) {
      // Check if we've reached the maximum number of executed trades for this day
      if (executedTradesToday >= MaxTradesPerDay) {
         Comment("Maximum executed trades per day (", MaxTradesPerDay, ") reached. No more trades for this day.");
      } else {
         // Only execute one position per bar
         int bars = iBars(_Symbol, Timeframe);
         
         if (barsTotal != bars) {
            barsTotal = bars;
            
            if(positions == 0 && orders == 0) {
               TradeLogic();
            }
         }
      }
   }
   
   if (AutoClosePositions && !isTimeToTrade && positions > 0) {
      CloseAllPositions();
   }
   
   if (timeToClosePositions()) {
      CloseAllPositions();
   }
}

/*
+------------------------------------------------------------------+
| Strategy                                                         |
+------------------------------------------------------------------+

**********************[ENTER STRATEGY HERE]*************************

+------------------------------------------------------------------+
| Risk Management                                                  |    
+------------------------------------------------------------------+

******************[ENTER RISK MANAGEMENT HERE]**********************

*/

void TradeLogic() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   TrendType currentTrend = determineTrend();
   
   if (TradeWithTrend) {
      // Trade with trend logic
      bool trendingUp = currentTrend == Uptrend;
      bool trendingDown = currentTrend == Downtrend;
      
      Print("Current trend: ", currentTrend, " (Uptrend: ", trendingUp, ", Downtrend: ", trendingDown, ")");
      
      // Only trade based on the current trend
      if (trendingUp) {
         //--- Buy Conditions
         //--- OnBuy();
      } else if (trendingDown) {
         //--- Sell Conditions
         //--- OnSell();
      } else {
         Print("No clear trend direction. No trade placed.");
      }
   } else {
      // Trade without trend consideration
      //--- Buy Conditions
      //--- OnBuy();
      
      //--- Sell Conditions
      //--- OnSell();
   }
}

//+------------------------------------------------------------------+
//| Buy & Sell Functions                                             |
//+------------------------------------------------------------------+
//--- On Buy
void OnBuy() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tp = 0;
   double sl = 0;
   
   // Calculate TP
   if (TpFactor > 0) {
      // Use factor-based TP calculation (implement based on strategy needs)
      tp = ask + TpPoints * _Point; // Default fallback
   } else if (TpPoints > 0) {
      tp = ask + TpPoints * _Point;
   }
   
   // Calculate SL
   if (SlFactor > 0) {
      // Use factor-based SL calculation (implement based on strategy needs)
      sl = ask - SlPoints * _Point; // Default fallback
   } else if (SlPoints > 0) {
      sl = ask - SlPoints * _Point;
   }
   
   double lots = LotSize;
   if(RiskPercent > 0 && sl > 0) lots = calcLots(ask-sl);
   
   if (trade.Buy(lots, _Symbol, ask, sl, tp)) {
      Print("Buy Order executed: ", trade.ResultOrder());
   } else {
      Print("Buy Order failed: ", GetLastError());
   }
}

//--- On Sell
void OnSell() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tp = 0;
   double sl = 0;
   
   // Calculate TP
   if (TpFactor > 0) {
      // Use factor-based TP calculation (implement based on strategy needs)
      tp = bid - TpPoints * _Point; // Default fallback
   } else if (TpPoints > 0) {
      tp = bid - TpPoints * _Point;
   }
   
   // Calculate SL
   if (SlFactor > 0) {
      // Use factor-based SL calculation (implement based on strategy needs)
      sl = bid + SlPoints * _Point; // Default fallback
   } else if (SlPoints > 0) {
      sl = bid + SlPoints * _Point;
   }
   
   double lots = LotSize;
   if(RiskPercent > 0 && sl > 0) lots = calcLots(sl-bid);
   
   if (trade.Sell(lots, _Symbol, bid, sl, tp)) {
      Print("Sell Order executed: ", trade.ResultOrder());
   } else {
      Print("Sell Order failed: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Modify Current Positions Functions                               |
//+------------------------------------------------------------------+
void ModifyPositions() {
   double ask = SymbolInfoDouble(NULL, SYMBOL_ASK);
   double bid = SymbolInfoDouble(NULL, SYMBOL_BID);

   for (int i=0; i < PositionsTotal(); i++) {
      ulong posTicket = PositionGetTicket(i);
      
      if (PositionGetInteger(POSITION_MAGIC) != Magic) continue; //--- Don't check the position of other EAs
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue; //--- Don't change position if chart changes
        
      // Check if TSL is enabled - Fixed condition
      if (TslTriggerPoints != 0 || TslTriggerFactor != 0) {
         SetTrailingSL(ask, bid, posTicket);
      }
   }
}

//--- Set Trailing SL
void SetTrailingSL(double ask, double bid, ulong posTicket) {
   if(!PositionSelectByTicket(posTicket)) return; // Ensure position is selected
   
   double posPriceOpen = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSl = PositionGetDouble(POSITION_SL);
   double posTp = PositionGetDouble(POSITION_TP);
   
   if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
      //--- Set trailing SL for buy positions
      double tslTrigger = posPriceOpen;
      
      //--- Calculate TSL Trigger based on 
      if (TslTriggerFactor > 0) {
         tslTrigger = posPriceOpen + (posPriceOpen - posSl) * TslTriggerFactor;
      } else if (TslTriggerFactor == 0 && TslTriggerPoints > 0) {
         tslTrigger = posPriceOpen + TslTriggerPoints * _Point;
      }
   
      if (bid > tslTrigger) {
         double sl = posPriceOpen + TslPoints * _Point;
         
         sl =  NormalizeDouble(sl, _Digits);
         
         if (sl > posSl || posSl == 0) {
            trade.PositionModify(posTicket, sl, posTp);
            Print("Position: ", posTicket, " Modified - SL set to breakeven");
         }
      }
   } else {
      //--- Set trailing SL for sell positions - Fixed trigger calculation
      double tslTrigger = posPriceOpen;
      
      //--- Calculate TSL Trigger based on 
      if (TslTriggerFactor > 0) {
         tslTrigger = posPriceOpen - (posSl - posPriceOpen) * TslTriggerFactor;
      } else if (TslTriggerFactor == 0 && TslTriggerPoints > 0) {
         tslTrigger = posPriceOpen - TslTriggerPoints * _Point;
      }
      
      if (ask < tslTrigger) {
         double sl = posPriceOpen - TslPoints * _Point;
         sl =  NormalizeDouble(sl, _Digits);
         
         if (sl < posSl || posSl == 0) {
            trade.PositionModify(posTicket, sl, posTp);
            Print("Position: ", posTicket, " Modified - SL set to breakeven");
         }
      }
   }
}

void CloseAllPositions() {
   // Use a reverse loop to avoid issues when positions are closed
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong posTicket = PositionGetTicket(i);
      
      if(!PositionSelectByTicket(posTicket)) {
         Print("Failed to select position at index: ", i);
         continue;
      }
      
      if (PositionGetInteger(POSITION_MAGIC) != Magic) continue; //--- Don't check the position of other EAs
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue; //--- Don't change position if chart changes

      Print("Attempting to close position Ticket: ", posTicket);
      
      // Check if position is still valid before closing
      if(!PositionSelectByTicket(posTicket)) {
         Print("Position ", posTicket, " no longer exists");
         continue;
      }
      
      if(!trade.PositionClose(posTicket)) {
         int error = GetLastError();
         Print("Failed to close position: ", posTicket, " Error: ", error);
         
         // Handle specific errors
         switch(error) {
            case 4109: // ERR_TRADE_DISABLED
               Print("Trading is disabled");
               break;
            case 4108: // ERR_MARKET_CLOSED
               Print("Market is closed");
               break;
            case 4107: // ERR_INSUFFICIENT_MONEY
               Print("Insufficient money to close position");
               break;
            case 4103: // ERR_POSITION_NOT_FOUND
               Print("Position not found - may have been closed already");
               break;
            default:
               Print("Unknown error occurred while closing position");
               break;
         }
      } else {
         Print("Successfully closed position: ", posTicket);
      }
   }
}

//+------------------------------------------------------------------+
//| Utilities                                                        |
//+------------------------------------------------------------------+
int PositionsTotalByMagic(int magic) {
   int total = 0;
   for (int i=0; i < PositionsTotal(); i++) {
      ulong posTicket = PositionGetTicket(i);
      if(!PositionSelectByTicket(posTicket)) continue; // Ensure position is selected
      if (PositionGetInteger(POSITION_MAGIC) == magic) total++;
   }
   return total;
}

int OrdersTotalByMagic(int magic) {
   int total = 0;
   for (int i=0; i < OrdersTotal(); i++) {
      ulong orderTicket = OrderGetTicket(i);
      if(!OrderSelect(orderTicket)) continue; // Ensure order is selected
      if (OrderGetInteger(ORDER_MAGIC) == magic && OrderGetString(ORDER_SYMBOL) == _Symbol) total++;
   }
   return total;
}

bool timeToTrade() {
   MqlDateTime structTime;
   TimeCurrent(structTime);
   structTime.sec = 0;
   
   structTime.hour = TimeStartHour;
   structTime.min = TimeStartMin;
   datetime timeStart = StructToTime(structTime);
   
   structTime.hour = TimeEndHour;
   structTime.min = TimeEndMin;
   datetime timeEnd = StructToTime(structTime);
   
   bool isTime = TimeCurrent() >= timeStart && TimeCurrent() < timeEnd;
   
   Comment("\nServer Time: ", TimeCurrent(),
           "\nTime Start Dt: ", timeStart,
           "\nTime End Dt: ", timeEnd,
           "\nTimeFilter: ", isTime,
           "\nExecuted Trades Today: ", executedTradesToday, "/", MaxTradesPerDay);
           
   return isTime;
}

bool timeToClosePositions() {
   MqlDateTime structTime;
   TimeCurrent(structTime);
   structTime.sec = 0;
   
   structTime.hour = ClosePositionsHour;
   structTime.min = ClosePositionsMinute;
   datetime timeEnd = StructToTime(structTime);
   
   bool isTime = TimeCurrent() >= timeEnd;
   
   // Add debugging information
   if (isTime) {
      Print("Position closing time reached - Current: ", TimeToString(TimeCurrent()), 
            " Close time: ", TimeToString(timeEnd),
            " Close hour: ", ClosePositionsHour, " Close minute: ", ClosePositionsMinute);
   }
           
   return isTime;
}

double calcLots(double slPoints){
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;
   double ticksize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickvalue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double lotstep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   
   double moneyPerLotstep = slPoints / ticksize * tickvalue * lotstep;   
   double lots = MathFloor(risk / moneyPerLotstep) * lotstep;

   lots = MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   lots = MathMax(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
   
   return lots;
}

TrendType determineTrend() {
   double slowTrendMa[];
   double fastTrendMa[];
   CopyBuffer(handleSlowTrendMa, MAIN_LINE, 1,2, slowTrendMa);
   CopyBuffer(handleFastTrendMa, MAIN_LINE, 1,2, fastTrendMa);   
   
   if (fastTrendMa[0] - RangeBuffer * _Point > slowTrendMa[0]) {
      return Uptrend;
   } else if (fastTrendMa[0] < slowTrendMa[0] - RangeBuffer * _Point) {
      return Downtrend;
   }
   
   return Ranging;
}

void CheckAndUpdateDay() {
   MqlDateTime current;
   TimeCurrent(current);
   int today = current.day + current.mon * 100 + current.year * 10000;
   
   if (currentDay != today) {
      currentDay = today;
      executedTradesToday = 0;
      Print("New day started. Executed trades reset to 0.");
   }
}

void CancelAllPendingOrders() {
   Print("Cancelling all pending orders after position execution...");
   int cancelledCount = 0;
   
   // Use reverse loop to avoid issues when orders are cancelled
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong orderTicket = OrderGetTicket(i);
      
      if (!OrderSelect(orderTicket)) continue;
      
      // Only cancel orders with our magic number and symbol
      if (OrderGetInteger(ORDER_MAGIC) != Magic) continue;
      if (OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      
      // Cancel the pending order
      if (trade.OrderDelete(orderTicket)) {
         Print("Cancelled pending order: ", orderTicket, " Type: ", OrderGetInteger(ORDER_TYPE));
         cancelledCount++;
      } else {
         Print("Failed to cancel order: ", orderTicket, " Error: ", GetLastError());
      }
   }
   
   Print("Total pending orders cancelled: ", cancelledCount);
} 