//+------------------------------------------------------------------+
//|                                                 Box Template.mq5 |
//|                                           Based on Template v1.1 |
//|                                      Copyright 2025, Jerry Zhou. |
//|                                       https://www.jerryzhou.xyz/ |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Jerry Zhou."
#property link      "https://www.jerryzhou.xyz/"
#property version   "1.40"

//--- Imports
#include <Trade\Trade.mqh>

//--- Custom Types
enum TrendType {
   Uptrend = 1,
   Downtrend = 2,
   Ranging = 3,
};

//--- Function Prototypes
int PositionsTotalByMagic(int magic);
int OrdersTotalByMagic(int magic);
bool timeToTrade();
double calcLots(double slPoints);
bool timeToCalculateRange();
bool timeToClosePositions();
void CloseAllPositions();
TrendType determineTrend();
void DebugTimeInfo();
void CheckAndUpdateDay();
void CancelAllPendingOrders();
void CleanupObjects();
void ModifyPositions();
void SetTrailingSL(double ask, double bid, ulong posTicket);
void TradeLogic();
void OnBuy();
void OnSell();

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
input double SlFactor = 1.0; //SlFactor (Multiplier for stop loss distance - 1.0 = at opposite range, 2.0 = 2x range distance)

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
input ENUM_TIMEFRAMES RangeTimeframe = PERIOD_H1; //RangeTimeframe (Fixed timeframe for consistent range calculation)
input int RangeStartHour = 3;
input int RangeStartMinute = 0;
input int RangeEndHour = 7;
input int RangeEndMinute = 30;
input int StopTradingHour = 17;
input int StopTradingMinute = 30;
input int ClosePositionsHour = 19;
input int ClosePositionsMinute = 55;
input int MaxTradesPerDay = 1; //MaxTradesPerDay (Maximum number of executed trades per day - EA cancels remaining orders when limit reached)
input int HistoricalDays = 30; //HistoricalDays (Number of past days to display ranges for - maximum 50)
input bool ShowAllTradingLines = true; //ShowAllTradingLines (Show trading window lines for all historical ranges)

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
   bool rangeCalculated; // Flag to prevent re-calculation of same range
   datetime lastCalculationDate; // Track when range was last calculated
   bool validRange; // Flag to indicate if range calculation was successful
   
   CRange(int ds) { 
      dayShift = ds; 
      tradesCount = 0; 
      currentDay = 0; 
      executedTradesToday = 0; 
      rangeCalculated = false; 
      lastCalculationDate = 0; 
      validRange = false;
      high = 0;
      low = 0;
      timeStart = 0;
      timeEnd = 0;
   }
   
   void commentRange() {
      Comment("\nRange Start: ", timeStart,
              "\nRange End: ", timeEnd,
              "\nRange High: ", high,
              "\nRange Low: ", low,
              "\nSession Trend: ", sessionTrend,
              "\nTime to Trade: ", timeToTrade,
              "\nExecuted Trades Today: ", executedTradesToday, "/", MaxTradesPerDay,
              "\nSL Factor: ", SlFactor
              );
   }
   
   bool calculateRange() {
      //--- Calculate the target date for this range
      datetime targetDate = TimeCurrent() - dayShift * 24 * 3600; // Subtract days in seconds
      MqlDateTime structTime;
      TimeToStruct(targetDate, structTime);
      
      //--- For current day (dayShift = 0), force calculation every time during range period
      if (dayShift == 0) {
         // For current day, always allow re-calculation during range period
         datetime todayDate = targetDate - (targetDate % (24 * 3600)); // Get start of day
         lastCalculationDate = todayDate;
      } else {
         //--- Check if we already calculated this range today (prevent unnecessary re-calculations for historical ranges)
         datetime todayDate = targetDate - (targetDate % (24 * 3600)); // Get start of day
         if (rangeCalculated && lastCalculationDate == todayDate && dayShift > 0) {
            // Already calculated this historical range for today
            return validRange;
         }
      }
      
      //--- Skip weekends - check day_of_week after adjusting the date
      if (structTime.day_of_week == 6 || structTime.day_of_week == 0) {
         if (dayShift <= 5) { // Only print for recent days to avoid spam
            Print("Skipping range calculation for weekend day: ", structTime.day_of_week, " (", TimeToString(targetDate), ")");
         }
         validRange = false;
         return false; 
      }
      
      //--- Set range start time
      structTime.hour = RangeStartHour;
      structTime.min = RangeStartMinute;
      structTime.sec = 0;
      timeStart = StructToTime(structTime);
      
      //--- Set range end time
      structTime.hour = RangeEndHour;
      structTime.min = RangeEndMinute;
      timeEnd = StructToTime(structTime);
      
      //--- For current day (dayShift = 0), limit end time to current time if we're still in range period
      if (dayShift == 0) {
         datetime currentTime = TimeCurrent();
         if (currentTime < timeEnd) {
            timeEnd = currentTime;
         }
      }
      
      //--- Validate time range
      if (timeStart >= timeEnd) {
         if (dayShift <= 5) { // Only print for recent days
            Print("Warning: Invalid time range for day ", dayShift, " - Start: ", TimeToString(timeStart), " End: ", TimeToString(timeEnd));
         }
         validRange = false;
         return false;
      }
      
      //--- Check if we have sufficient historical data
      int testShift = iBarShift(_Symbol, RangeTimeframe, timeStart);
      if (testShift == -1) {
         if (dayShift <= 5) { // Only print for recent days
            Print("Warning: No historical data available for day ", dayShift, " - Date: ", TimeToString(timeStart));
         }
         validRange = false;
         return false;
      }
      
      //--- Find high and low within range using standardized timeframe
      int start_shift = iBarShift(_Symbol, RangeTimeframe, timeStart);
      int end_shift = iBarShift(_Symbol, RangeTimeframe, timeEnd);
      
      //--- Ensure we have valid bar shifts
      if (start_shift == -1 || end_shift == -1) {
         if (dayShift <= 5) { // Only print for recent days
            Print("Warning: Invalid bar shift detected for day ", dayShift, 
                  " timeStart=", TimeToString(timeStart), 
                  " timeEnd=", TimeToString(timeEnd),
                  " start_shift=", start_shift, " end_shift=", end_shift);
         }
         validRange = false;
         return false;
      }
      
      //--- Calculate bar count (start_shift is older, end_shift is newer)
      int barCount = start_shift - end_shift + 1;
      
      //--- Ensure we have at least one bar to analyze
      if (barCount <= 0) {
         if (dayShift <= 5) { // Only print for recent days
            Print("Warning: Invalid bar count for day ", dayShift, ": ", barCount, " start_shift=", start_shift, " end_shift=", end_shift);
         }
         validRange = false;
         return false;
      }
      
      //--- Find highest and lowest bars within the range
      int highestBar = iHighest(_Symbol, RangeTimeframe, MODE_HIGH, barCount, end_shift);
      int lowestBar = iLowest(_Symbol, RangeTimeframe, MODE_LOW, barCount, end_shift);
      
      //--- Validate the results
      if (highestBar == -1 || lowestBar == -1) {
         if (dayShift <= 5) { // Only print for recent days
            Print("Warning: Failed to find highest/lowest bars for day ", dayShift, 
                  ". barCount=", barCount, " end_shift=", end_shift);
         }
         validRange = false;
         return false;
      }
      
      //--- Get the actual high and low values
      double newHigh = iHigh(_Symbol, RangeTimeframe, highestBar);
      double newLow = iLow(_Symbol, RangeTimeframe, lowestBar);
      
      //--- Validate price data
      if (newHigh <= 0 || newLow <= 0 || newHigh <= newLow) {
         if (dayShift <= 5) { // Only print for recent days
            Print("Warning: Invalid price data for day ", dayShift, ". High: ", newHigh, " Low: ", newLow);
         }
         validRange = false;
         return false;
      }
      
      //--- Update range values
      high = newHigh;
      low = newLow;
      rangeCalculated = true;
      validRange = true;
      
      //--- Debug information for range calculation (only for recent days or current day)
      if (dayShift <= 2) {
         Print("Day ", dayShift, " range calculated using ", EnumToString(RangeTimeframe), 
               " - Start: ", TimeToString(timeStart), 
               " End: ", TimeToString(timeEnd),
               " Bars analyzed: ", barCount,
               " High: ", DoubleToString(high, _Digits),
               " Low: ", DoubleToString(low, _Digits),
               " Range size: ", DoubleToString(high - low, _Digits), " points");
      }
      
             return true;
   }
   
   void drawRect() {
      //--- Only draw if we have valid range data
      if (!validRange || high <= 0 || low <= 0 || high <= low || timeStart >= timeEnd) {
         return; // Silently skip invalid ranges
      }
      
      //--- Get the date for this range
      MqlDateTime structTime;
      TimeToStruct(timeStart, structTime); // Use timeStart instead of current time
      
      //--- Create unique object names using the actual range date
      string dateStr = IntegerToString(structTime.year) + "_" + 
                      StringFormat("%02d", structTime.mon) + "_" + 
                      StringFormat("%02d", structTime.day);
      
      string rangeObjName = "Range_" + dateStr + "_" + IntegerToString(dayShift);
      string highObjName = "Trading_High_" + dateStr + "_" + IntegerToString(dayShift);
      string lowObjName = "Trading_Low_" + dateStr + "_" + IntegerToString(dayShift);
      
      //--- Delete existing objects first
      ObjectDelete(0, rangeObjName);
      ObjectDelete(0, highObjName);
      ObjectDelete(0, lowObjName);
      
      //--- Choose colors based on age (newer = more opaque)
      color rangeColor = clrLightGray;
      color highColor = clrRed;
      color lowColor = clrBlue;
      
      // Make older ranges more transparent
      if (dayShift > 7) {
         rangeColor = clrSilver;
         highColor = clrLightCoral;
         lowColor = clrLightSteelBlue;
      }
      if (dayShift > 14) {
         rangeColor = clrGainsboro;
         highColor = clrMistyRose;
         lowColor = clrAliceBlue;
      }
      
      // For current day (dayShift = 0), use brighter colors
      if (dayShift == 0) {
         rangeColor = clrLightBlue;
         highColor = clrRed;
         lowColor = clrBlue;
      }
      
      //--- Paint the range box
      if (ObjectCreate(0, rangeObjName, OBJ_RECTANGLE, 0, timeStart, low, timeEnd, high)) {
         ObjectSetInteger(0, rangeObjName, OBJPROP_FILL, true);
         ObjectSetInteger(0, rangeObjName, OBJPROP_COLOR, rangeColor);
         ObjectSetInteger(0, rangeObjName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, rangeObjName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, rangeObjName, OBJPROP_BACK, true); // Draw in background
         ObjectSetString(0, rangeObjName, OBJPROP_TOOLTIP, 
                        "Range " + IntegerToString(dayShift) + " days ago\n" +
                        "Date: " + TimeToString(timeStart, TIME_DATE) + "\n" +
                        "High: " + DoubleToString(high, _Digits) + "\n" +
                        "Low: " + DoubleToString(low, _Digits) + "\n" +
                        "Size: " + DoubleToString(high - low, _Digits) + " points");
      }
      
      //--- Calculate trading period end time
      MqlDateTime tradingTime;
      TimeToStruct(timeStart, tradingTime); // Use the same date as range
      tradingTime.hour = ClosePositionsHour;
      tradingTime.min = ClosePositionsMinute;
      tradingTime.sec = 0;
      datetime tradingEnd = StructToTime(tradingTime);
      
      //--- Paint the trading period high and low lines 
      bool shouldDrawLines = ShowAllTradingLines || dayShift <= 5;
      
      if (shouldDrawLines) {
         //--- Adjust line width and style based on age
         int lineWidth = (dayShift <= 5) ? 2 : 1; // Thicker lines for recent ranges
         ENUM_LINE_STYLE lineStyle = (dayShift <= 10) ? STYLE_SOLID : STYLE_DOT; // Dotted lines for older ranges
         
         if (ObjectCreate(0, highObjName, OBJ_RECTANGLE, 0, timeEnd, high, tradingEnd, high)) {
            ObjectSetInteger(0, highObjName, OBJPROP_COLOR, highColor);
            ObjectSetInteger(0, highObjName, OBJPROP_STYLE, lineStyle);
            ObjectSetInteger(0, highObjName, OBJPROP_WIDTH, lineWidth);
            ObjectSetString(0, highObjName, OBJPROP_TOOLTIP, 
                           "Range High (" + IntegerToString(dayShift) + " days ago): " + DoubleToString(high, _Digits) + 
                           "\nDate: " + TimeToString(timeStart, TIME_DATE));
         }
         
         if (ObjectCreate(0, lowObjName, OBJ_RECTANGLE, 0, timeEnd, low, tradingEnd, low)) {
            ObjectSetInteger(0, lowObjName, OBJPROP_COLOR, lowColor);
            ObjectSetInteger(0, lowObjName, OBJPROP_STYLE, lineStyle);
            ObjectSetInteger(0, lowObjName, OBJPROP_WIDTH, lineWidth);
            ObjectSetString(0, lowObjName, OBJPROP_TOOLTIP, 
                           "Range Low (" + IntegerToString(dayShift) + " days ago): " + DoubleToString(low, _Digits) + 
                           "\nDate: " + TimeToString(timeStart, TIME_DATE));
         }
      }
      
      // Only print for recent ranges to avoid log spam
      if (dayShift <= 2) {
         Print("Range drawn for day ", dayShift, " - Objects: ", rangeObjName);
      }
   }
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
CRange activeRange(0);
CRange* historicalRanges[];
int handleSlowTrendMa;
int handleFastTrendMa;

//+------------------------------------------------------------------+
//| Init, Deinit, OnTick                                             |
//+------------------------------------------------------------------+

int OnInit() {   
   // Initialize trade object with magic number
   trade.SetExpertMagicNumber(Magic);
   
   // Validate input parameters
   int maxDays = MathMin(HistoricalDays, 50); // Limit to 50 days max
   if (maxDays != HistoricalDays) {
      Print("Historical days limited to maximum of 50. Using: ", maxDays);
   }
   
   // Validate SL Factor
   if (SlFactor <= 0) {
      Print("Warning: SL Factor must be greater than 0. Current value: ", SlFactor);
      Print("Please change SL Factor to a positive value. EA may not work correctly.");
   }
   
   handleSlowTrendMa = iMA(_Symbol, TrendMaTimeframe, SlowTrendMaPeriod, 0, SlowTrendMaMethod, PRICE_CLOSE);
   handleFastTrendMa = iMA(_Symbol, TrendMaTimeframe, FastTrendMaPeriod, 0, FastTrendMaMethod, PRICE_CLOSE);
   
   // Initialize historical ranges array
   ArrayResize(historicalRanges, maxDays);
   
   // Calculate and draw historical ranges
   Print("Calculating historical ranges for ", maxDays, " days...");
   int validRanges = 0;
   
   for (int i = 1; i <= maxDays; i++) {
      historicalRanges[i-1] = new CRange(i);
      if (historicalRanges[i-1].calculateRange()) {
         historicalRanges[i-1].drawRect();
         validRanges++;
      }
      
      // Add a small delay to prevent overwhelming the system
      if (i % 10 == 0) {
         Print("Processed ", i, " days, valid ranges: ", validRanges);
         Sleep(10); // Small delay every 10 ranges
      }
   }
   
   Print("Historical range calculation complete. Valid ranges: ", validRanges, "/", maxDays);
   
   // Initialize current day range (dayShift = 0)
   Print("Initializing current day range...");
   activeRange.buyPlaced = false;
   activeRange.sellPlaced = false;
   
   // Try to calculate current day range if we're in the range period
   if (timeToCalculateRange()) {
      Print("Current time is within range calculation period. Calculating current day range...");
      if (activeRange.calculateRange()) {
         activeRange.drawRect();
         Print("Current day range successfully calculated and drawn.");
      } else {
         Print("Failed to calculate current day range.");
      }
   } else {
      Print("Current time is outside range calculation period.");
   }
   
   // Initialize day counter
   CheckAndUpdateDay();
   
   // Debug time information on startup
   Print("=== EA Initialization ===");
   DebugTimeInfo();
   Print("Magic Number: ", Magic);
   Print("Chart Timeframe: ", EnumToString(Timeframe));
   Print("Range Calculation Timeframe: ", EnumToString(RangeTimeframe));
   Print("Range Time: ", RangeStartHour, ":", StringFormat("%02d", RangeStartMinute), " - ", RangeEndHour, ":", StringFormat("%02d", RangeEndMinute));
   Print("Close Positions Time: ", ClosePositionsHour, ":", ClosePositionsMinute);
   Print("Max Trades Per Day: ", MaxTradesPerDay);
   Print("Historical Days: ", maxDays);
   Print("Trade With Trend: ", TradeWithTrend);
   Print("SL Factor: ", SlFactor);
   Print("========================");
  
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   // Clean up historical ranges
   for (int i = 0; i < ArraySize(historicalRanges); i++) {
      if (CheckPointer(historicalRanges[i]) != POINTER_INVALID) {
         delete historicalRanges[i];
      }
   }
   ArrayFree(historicalRanges);
   
   // Clean up chart objects
   CleanupObjects();
   
   Print("EA deinitialized. Reason: ", reason);
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
   
   // Check if we need to calculate the range - FOR CURRENT DAY, ALLOW RECALCULATION DURING RANGE PERIOD
   bool rangeCalculated = false;
   if (timeToCalculateRange()){
      // For current day, always try to calculate/update range during range period
      Print("Current time is within range calculation period. Updating current day range...");
      Print("Current time: ", TimeToString(TimeCurrent()));
      Print("Range window: ", RangeStartHour, ":", StringFormat("%02d", RangeStartMinute), " - ", RangeEndHour, ":", StringFormat("%02d", RangeEndMinute));
      
      if (activeRange.calculateRange()) {
         activeRange.drawRect();
         rangeCalculated = true;
         Print("Current day range successfully updated and drawn.");
         
         // Only reset order placement flags when NEW range is calculated (not during updates)
         if (!activeRange.buyPlaced && !activeRange.sellPlaced) {
            // Reset trade count for new session only if no orders placed yet
            activeRange.tradesCount = 0;
            Print("New session started. Trade count reset to 0.");
         }
      } else {
         Print("Failed to calculate current day range during OnTick.");
      }
   }
   // NEW: If we're in trade period and don't have a valid range, calculate the completed range
   else if (timeToTrade() && !activeRange.validRange) {
      Print("EA started during trade period without valid range. Calculating completed range for today...");
      Print("Current time: ", TimeToString(TimeCurrent()));
      Print("Range window was: ", RangeStartHour, ":", StringFormat("%02d", RangeStartMinute), " - ", RangeEndHour, ":", StringFormat("%02d", RangeEndMinute));
      
      if (activeRange.calculateRange()) {
         activeRange.drawRect();
         rangeCalculated = true;
         Print("Completed range successfully calculated and drawn for trade period.");
         
         // Reset order placement flags for new session
         activeRange.buyPlaced = false;
         activeRange.sellPlaced = false;
         activeRange.tradesCount = 0;
         Print("Trade session initialized with completed range.");
      } else {
         Print("Failed to calculate completed range for trade period.");
      }
   }
   
   // Handle day transitions and range period completion
   static int lastProcessedDay = 0;
   MqlDateTime current;
   TimeCurrent(current);
   int today = current.day + current.mon * 100 + current.year * 10000;
   
   // Check for new day (reset at midnight or when we detect day change)
   if (lastProcessedDay != today) {
      lastProcessedDay = today;
      // Reset range calculation flag for new day
      Print("New day detected (", today, "). Resetting range for new session.");
      activeRange.rangeCalculated = false;
      activeRange.validRange = false;
      activeRange.buyPlaced = false;
      activeRange.sellPlaced = false;
      
      // Clear previous day's range visual
      string oldDateStr = "";
      MqlDateTime oldTime;
      datetime yesterday = TimeCurrent() - 24 * 3600;
      TimeToStruct(yesterday, oldTime);
      oldDateStr = IntegerToString(oldTime.year) + "_" + 
                  StringFormat("%02d", oldTime.mon) + "_" + 
                  StringFormat("%02d", oldTime.day);
      
      ObjectDelete(0, "Range_" + oldDateStr + "_0");
      ObjectDelete(0, "Trading_High_" + oldDateStr + "_0");
      ObjectDelete(0, "Trading_Low_" + oldDateStr + "_0");
   }
   
   // Check if we're in trading time
   if (timeToTrade() && activeRange.validRange) {
      activeRange.timeToTrade = true;
      
      // Try to place orders if we don't have positions and orders
      if(positions == 0 && orders == 0) {
         TradeLogic();  
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
   // Calculate SL using SL Factor with safety check
   double safeSLFactor = (SlFactor <= 0) ? 1.0 : SlFactor;
   double rangeSize = activeRange.high - activeRange.low;
   double sl = activeRange.low - (rangeSize * (safeSLFactor - 1.0));
   
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
      Print("Entry: ", DoubleToString(activeRange.high, _Digits),
            " SL: ", DoubleToString(sl, _Digits), " (Factor: ", safeSLFactor, ")",
            " Range: ", DoubleToString(activeRange.low, _Digits), " - ", DoubleToString(activeRange.high, _Digits));
      
      // Create descriptive comment for the order
      string tradeComment = "Buy Stop above range high " + 
                           DoubleToString(activeRange.high, _Digits) + " (Range: " + DoubleToString(activeRange.low, _Digits) + 
                           " - " + DoubleToString(activeRange.high, _Digits) + ") SL Factor: " + DoubleToString(safeSLFactor, 1);
      Print(tradeComment);
   } else {
      Print("Buy Order failed: ", GetLastError());
   }
}

//--- On Sell
void OnSell() {
   // Calculate SL using SL Factor with safety check
   double safeSLFactor = (SlFactor <= 0) ? 1.0 : SlFactor;
   double rangeSize = activeRange.high - activeRange.low;
   double sl = activeRange.high + (rangeSize * (safeSLFactor - 1.0));
   
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
      Print("Entry: ", DoubleToString(activeRange.low, _Digits),
            " SL: ", DoubleToString(sl, _Digits), " (Factor: ", safeSLFactor, ")",
            " Range: ", DoubleToString(activeRange.low, _Digits), " - ", DoubleToString(activeRange.high, _Digits));
      
      // Create descriptive comment for the order
      string tradeComment = "Sell Stop below range low " + 
                           DoubleToString(activeRange.low, _Digits) + " (Range: " + DoubleToString(activeRange.low, _Digits) + 
                           " - " + DoubleToString(activeRange.high, _Digits) + ") SL Factor: " + DoubleToString(safeSLFactor, 1);
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

//+------------------------------------------------------------------+
//| Cleanup Functions                                                |
//+------------------------------------------------------------------+
void CleanupObjects() {
   Print("Cleaning up chart objects...");
   int deletedCount = 0;
   
   // Clean up all objects created by this EA
   int totalObjects = ObjectsTotal(0, -1, -1);
   
   for (int i = totalObjects - 1; i >= 0; i--) {
      string objName = ObjectName(0, i, -1, -1);
      
      // Delete objects that match our naming convention
      if (StringFind(objName, "Range_") >= 0 || 
          StringFind(objName, "Trading_High_") >= 0 || 
          StringFind(objName, "Trading_Low_") >= 0) {
         
         if (ObjectDelete(0, objName)) {
            deletedCount++;
         }
      }
   }
   
   Print("Cleanup complete. Deleted ", deletedCount, " objects.");
   ChartRedraw(0);
}
