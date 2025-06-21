//+------------------------------------------------------------------+
//|                                                 Box Template.mq5 |
//|                                           Based on Template v1.1 |
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
input int Magic = 1; //Magic (Need to use magic number for each different EA)

//--- Trade Settings
input group "Trade Settings";
input double LotSize = 0.1;
input double RiskPercent = 0.5; //RiskPercent (0 = Use Fixed LotSize)
input double TpPoints = 0; //TPoints (0 = No TP)
input double TpFactor = 0; //TpFactor (0 = Use TpPoints)

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

//+------------------------------------------------------------------+
//| Strategy Specific Inputs                                         |
//+------------------------------------------------------------------+
input group "Strategy Inputs";
input int RangeStartHour = 3;
input int RangeStartMinute = 0;
input int RangeEndHour = 7;
input int RangeEndMinute = 30;
input int StopTradingHour = 17;
input int StopTradingMinute = 30;
input int ClosePositionsHour = 19;
input int ClosePositionsMinute = 55;
input int MaxTradesPerDay = 1; //MaxTradesPerDay (Maximum number of executed trades per day - EA cancels remaining orders when limit reached)

//+------------------------------------------------------------------+
//| Class Definitions                                                |
//+------------------------------------------------------------------+

class CRange {
public:
   datetime timeStart;
   datetime timeEnd;
   int dayShift;
   double high;
   double low;
   bool buyPlaced;
   bool sellPlaced;
   TrendType sessionTrend;
   bool timeToTrade;
   int tradesCount; // Track number of trades made in this session
   int currentDay; // Track current day for trade counting
   int executedTradesToday; // Track executed trades per day
   CRange(int ds) { dayShift = ds; tradesCount = 0; currentDay = 0; executedTradesToday = 0; }
   
   void commentRange() {
      Comment("\nRange Start: ", timeStart,
              "\nRange End: ", timeEnd,
              "\nRange High: ", high,
              "\nRange Low: ", low,
              "\nSession Trend: ", sessionTrend,
              "\nTime to Trade: ", timeToTrade,
              "\nExecuted Trades Today: ", executedTradesToday, "/", MaxTradesPerDay
              );
   }
   
   void calculateRange() {
      MqlDateTime structTime;
      MqlDateTime currentTime;
      TimeCurrent(structTime);
      TimeCurrent(currentTime);
      structTime.day = structTime.day - dayShift;
      currentTime.day = currentTime.day - dayShift;
      
      //--- skip if its a Saturday or Sunday
      if (structTime.day_of_week == 6 || structTime.day_of_week == 0) return; 
      
      structTime.sec = 0;
      
      structTime.hour = RangeStartHour;
      structTime.min = RangeStartMinute;
      timeStart = StructToTime(structTime);
      
      if (currentTime.hour < RangeEndHour && dayShift == 0) {
         structTime.hour = currentTime.hour;
         structTime.min = currentTime.min;
      } else {
         structTime.hour = RangeEndHour;
         structTime.min = RangeEndMinute;
      }
      
      timeEnd = StructToTime(structTime);   
      
      //--- Find high and low within range
      int start_shift = iBarShift(_Symbol, Timeframe, timeStart);
      int end_shift = iBarShift(_Symbol, Timeframe, timeEnd);
      int barCount = start_shift - end_shift;
      
      int highestBar = iHighest(_Symbol, Timeframe, MODE_HIGH, barCount, end_shift);
      int lowestBar = iLowest(_Symbol, Timeframe, MODE_LOW, barCount, end_shift);
      high = iHigh(_Symbol, Timeframe, highestBar);
      low = iLow(_Symbol, Timeframe, lowestBar);    
   }
   
   void drawRect() {
      MqlDateTime structTime;
      TimeCurrent(structTime);
      structTime.day = structTime.day - dayShift;
      structTime.sec = 0;
      
      string objName = MQLInfoString(MQL_PROGRAM_NAME) + " " + TimeToString(timeStart); 
      
      //--- Paint the range
      ObjectCreate(0, "Range - " + IntegerToString(structTime.day) + IntegerToString(structTime.year), OBJ_RECTANGLE, 0, timeStart, low, timeEnd, high);
      ObjectSetInteger(0, "Range - " + IntegerToString(structTime.day) + IntegerToString(structTime.year), OBJPROP_FILL, true);
      
      //--- Paint the trading time
      structTime.hour = ClosePositionsHour;
      structTime.min = ClosePositionsMinute;
      datetime tradingEnd = StructToTime(structTime);
      
      ObjectCreate(0, "Trading Period High - " + IntegerToString(structTime.day) + IntegerToString(structTime.year), OBJ_RECTANGLE, 0, timeStart, high, tradingEnd, high);
      ObjectCreate(0, "Trading Period Low - " + IntegerToString(structTime.day) + IntegerToString(structTime.year), OBJ_RECTANGLE, 0, timeStart, low, tradingEnd, low);
   }
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
CRange activeRange(0);
int handleSlowTrendMa;
int handleFastTrendMa;

//+------------------------------------------------------------------+
//| Init, Deinit, OnTick                                             |
//+------------------------------------------------------------------+

int OnInit() {   
   // Initialize trade object with magic number
   trade.SetExpertMagicNumber(Magic);
   
   handleSlowTrendMa = iMA(_Symbol, TrendMaTimeframe, SlowTrendMaPeriod, 0, SlowTrendMaMethod, PRICE_CLOSE);
   handleFastTrendMa = iMA(_Symbol, TrendMaTimeframe, FastTrendMaPeriod, 0, FastTrendMaMethod, PRICE_CLOSE);
   
   for (int i = 1; i < 5; i++) {
      CRange range(i);
      range.calculateRange();
      range.drawRect();
   }
   
   activeRange.buyPlaced = false;
   activeRange.sellPlaced = false;
   
   // Initialize day counter
   CheckAndUpdateDay();
   
   // Debug time information on startup
   Print("=== EA Initialization ===");
   DebugTimeInfo();
   Print("Magic Number: ", Magic);
   Print("Close Positions Time: ", ClosePositionsHour, ":", ClosePositionsMinute);
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
      activeRange.executedTradesToday++;
      Print("Position opened! Executed trades today: ", activeRange.executedTradesToday, "/", MaxTradesPerDay);
      
      // Cancel all remaining pending orders when we've reached the daily limit
      if (activeRange.executedTradesToday >= MaxTradesPerDay) {
         Print("Daily trade limit reached (", MaxTradesPerDay, "). Cancelling all remaining pending orders.");
         CancelAllPendingOrders();
      }
   }
   lastPositions = positions;

   if (positions > 0) {
      //--- Monitor current positions
      ModifyPositions();
   }

   activeRange.commentRange();
   
   // Check if we need to calculate the range
   bool rangeCalculated = false;
   if (timeToCalculateRange()){
      activeRange.calculateRange();
      activeRange.drawRect();
      rangeCalculated = true;
      // Reset order placement flags when new range is calculated
      activeRange.buyPlaced = false;
      activeRange.sellPlaced = false;
      // Reset trade count for new session
      activeRange.tradesCount = 0;
      Print("New session started. Trade count reset to 0.");
   }
   
   // Check if we're in trading time
   if (timeToTrade()) {
      activeRange.timeToTrade = true;
      
      // If range was just calculated or we don't have orders yet, try to place orders
      if (rangeCalculated || (positions == 0 && orders == 0)) {
         if(positions == 0 && orders == 0) {
            TradeLogic();  
         }
      }
   } else {
      activeRange.timeToTrade = false;
   }
   
   // Add debugging for position closing
   if (positions > 0) {
      bool shouldClose = timeToClosePositions();
      if (shouldClose) {
         Print("Time to close positions triggered - Current time: ", TimeToString(TimeCurrent()), 
               " Close time: ", ClosePositionsHour, ":", ClosePositionsMinute);
         CloseAllPositions();
         activeRange.sellPlaced = false;
         activeRange.buyPlaced = false;
      }
   }
}

/*
+------------------------------------------------------------------+
| Strategy                                                         |
+------------------------------------------------------------------+

We will track the highs and lows of the range, then trade
breakouts in the london and ny sessions

+------------------------------------------------------------------+
| Risk Management                                                  |    
+------------------------------------------------------------------+

1. When trade is over 10 pips in profit, set SL to break even
2. Only risk 2% of the account on each trade

*/

void TradeLogic() {   
   // Check if we've reached the maximum number of executed trades for this day
   if (activeRange.executedTradesToday >= MaxTradesPerDay) {
      Print("Maximum executed trades per day (", MaxTradesPerDay, ") reached. No more trades for this day.");
      return;
   }
   
   double ask = SymbolInfoDouble(NULL, SYMBOL_ASK);
   double bid = SymbolInfoDouble(NULL, SYMBOL_BID);
   TrendType currentTrend = determineTrend();
   
   // Log trend change if it's different from the stored trend
   if (activeRange.sessionTrend != currentTrend) {
      Print("Trend changed from ", activeRange.sessionTrend, " to ", currentTrend);
   }
   activeRange.sessionTrend = currentTrend;
   
   if (TradeWithTrend) {
      // Trade with trend logic - place only one order based on trend
      bool trendingUp = activeRange.sessionTrend == Uptrend;
      bool trendingDown = activeRange.sessionTrend == Downtrend;
      
      Print("Current trend: ", activeRange.sessionTrend, " (Uptrend: ", trendingUp, ", Downtrend: ", trendingDown, ")");
      
      // Only place one trade based on the current trend
      if (trendingUp && !activeRange.buyPlaced) {
         Print("Placing BUY order based on uptrend");
         OnBuy();
      } else if (trendingDown && !activeRange.sellPlaced) {
         Print("Placing SELL order based on downtrend");
         OnSell();
      } else {
         Print("No clear trend direction or order already placed. No trade placed.");
      }
   } else {
      // Trade without trend - place both orders
      // Remaining orders will be cancelled when MaxTradesPerDay limit is reached
      Print("Trading without trend - placing both buy and sell orders");
      Print("Orders will be cancelled when daily limit (", MaxTradesPerDay, ") is reached");
      
      if (!activeRange.buyPlaced) {
         OnBuy();
      }
      
      if (!activeRange.sellPlaced) {
         OnSell();
      }
   }
}


//+------------------------------------------------------------------+
//| Buy & Sell Functions                                             |
//+------------------------------------------------------------------+
//--- On Buy
void OnBuy() {
   double sl = activeRange.low;
   
   double lots = LotSize;
   if(RiskPercent > 0) lots = calcLots(activeRange.high-sl);
   
   double tp = 0;
   
   if (TpFactor > 0) {
      tp = activeRange.high + (activeRange.high - activeRange.low) * TpFactor;
   } else if (TpFactor == 0 && TpPoints > 0) {
      tp = activeRange.high + TpPoints * _Point;
   }
   
   MqlDateTime structTime;
   TimeCurrent(structTime);
   structTime.sec = 0;
   
   structTime.hour = StopTradingHour;
   structTime.min = StopTradingMinute;
   datetime cancelAt = StructToTime(structTime);
   
   if (trade.BuyStop(lots, activeRange.high, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, cancelAt)) {
      Print("Buy Order: ", trade.ResultOrder());
      activeRange.buyPlaced = true;
      // Don't increment trade count here - only count executed trades
      Print("Buy order placed. Waiting for execution.");
      
      // Create descriptive comment for the order
      string tradeComment = "Buy Stop above range high " + 
                           DoubleToString(activeRange.high, _Digits) + " (Range: " + DoubleToString(activeRange.low, _Digits) + 
                           " - " + DoubleToString(activeRange.high, _Digits) + ")";
      Print(tradeComment);
   } else {
      Print("Buy Order failed: ", GetLastError());
   }
}

//--- On Sell
void OnSell() {
   double sl = activeRange.high;
   
   double lots = LotSize;
   if(RiskPercent > 0) lots = calcLots(sl-activeRange.low);
   
   double tp = 0;
   
   MqlDateTime structTime;
   TimeCurrent(structTime);
   structTime.sec = 0;
   
   structTime.hour = StopTradingHour;
   structTime.min = StopTradingMinute;
   datetime cancelAt = StructToTime(structTime);
   
   if (TpFactor > 0) {
      tp = activeRange.low - (activeRange.high - activeRange.low) * TpFactor;
   } else if (TpFactor == 0 && TpPoints > 0) {
      tp = activeRange.low - TpPoints * _Point;
   }
   
   if (trade.SellStop(lots, activeRange.low, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, cancelAt)) {
      Print("Sell Order: ", trade.ResultOrder());
      activeRange.sellPlaced = true;
      // Don't increment trade count here - only count executed trades
      Print("Sell order placed. Waiting for execution.");
      
      // Create descriptive comment for the order
      string tradeComment = "Sell Stop below range low " + 
                           DoubleToString(activeRange.low, _Digits) + " (Range: " + DoubleToString(activeRange.low, _Digits) + 
                           " - " + DoubleToString(activeRange.high, _Digits) + ")";
      Print(tradeComment);
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
   
   structTime.hour = RangeEndHour;
   structTime.min = RangeEndMinute;
   datetime timeStart = StructToTime(structTime);
   
   structTime.hour = StopTradingHour;
   structTime.min = StopTradingMinute;
   datetime timeEnd = StructToTime(structTime);
   
   bool isTime = TimeCurrent() > timeStart && TimeCurrent() < timeEnd;
           
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

bool timeToCalculateRange() {
   MqlDateTime structTime;
   TimeCurrent(structTime);
   structTime.sec = 0;
   
   structTime.hour = RangeStartHour;
   structTime.min = RangeStartMinute;
   datetime timeStart = StructToTime(structTime);
   
   structTime.hour = RangeEndHour;
   structTime.min = RangeEndMinute;
   datetime timeEnd = StructToTime(structTime);
   
   bool isTime = TimeCurrent() >= timeStart && TimeCurrent() <= timeEnd;
           
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

// Helper function to debug time calculations
void DebugTimeInfo() {
   MqlDateTime current;
   TimeCurrent(current);
   
   Print("Current time: ", TimeToString(TimeCurrent()),
         " Day of week: ", current.day_of_week,
         " Hour: ", current.hour,
         " Minute: ", current.min);
         
   Print("Close positions time: ", ClosePositionsHour, ":", ClosePositionsMinute);
   Print("Time to close positions: ", timeToClosePositions());
}

void CheckAndUpdateDay() {
   MqlDateTime current;
   TimeCurrent(current);
   int today = current.day + current.mon * 100 + current.year * 10000;
   
   if (activeRange.currentDay != today) {
      activeRange.currentDay = today;
      activeRange.executedTradesToday = 0;
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
   
   // Reset the order placement flags since orders are cancelled
   activeRange.buyPlaced = false;
   activeRange.sellPlaced = false;
}
