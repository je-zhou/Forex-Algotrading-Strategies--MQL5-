//+------------------------------------------------------------------+
//|                                                 Box Template.mq5 |
//|                                           Based on Template v1.0 |
//|                                      Copyright 2024, Jerry Zhou. |
//|                                       https://www.jerryzhou.xyz/ |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Jerry Zhou."
#property link      "https://www.jerryzhou.xyz/"
#property version   "1.10"

//--- Imports
#include <trade/trade.mqh>
#include <Object.mqh>

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
input ENUM_TIMEFRAMES TrendMaTimeframe = PERIOD_M6; //TrendMaTimeframe (The timeframe the trending moving average should be calculated)
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

//+------------------------------------------------------------------+
//| Class Definitions                                                |
//+------------------------------------------------------------------+

class CRange : public CObject {
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
   CRange(int ds) { dayShift = ds; }
   
   void commentRange() {
      Comment("\nRange Start: ", timeStart,
              "\nRange End: ", timeEnd,
              "\nRange High: ", high,
              "\nRange Low: ", low,
              "\nSession Trend: ", sessionTrend,
              "\nTime to Trade: ", timeToTrade
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
      ObjectCreate(0, "Range - " + structTime.day + structTime.year, OBJ_RECTANGLE, 0, timeStart, low, timeEnd, high);
      ObjectSetInteger(0, "Range - " + structTime.day + structTime.year, OBJPROP_FILL, true);
      
      //--- Paint the trading time
      structTime.hour = ClosePositionsHour;
      structTime.min = ClosePositionsHour;
      datetime tradingEnd = StructToTime(structTime);
      
      ObjectCreate(0, "Trading Period High - " + structTime.day + structTime.year, OBJ_RECTANGLE, 0, timeStart, high, tradingEnd, high);
      ObjectCreate(0, "Trading Period Low - " + structTime.day + structTime.year, OBJ_RECTANGLE, 0, timeStart, low, tradingEnd, low);
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
   handleSlowTrendMa = iMA(_Symbol, TrendMaTimeframe, SlowTrendMaPeriod, 0, SlowTrendMaMethod, PRICE_CLOSE);
   handleFastTrendMa = iMA(_Symbol, TrendMaTimeframe, FastTrendMaPeriod, 0, FastTrendMaMethod, PRICE_CLOSE);
   
   for (int i = 1; i < 5; i++) {
      CRange range(i);
      range.calculateRange();
      range.drawRect();
   }
   
   activeRange.buyPlaced = false;
   activeRange.sellPlaced = false;
  
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {

}

void OnTick() {
   //--- Monitor current positions
   ModifyPositions();
   
   activeRange.commentRange();
   
   if (timeToCalculateRange()){
      activeRange.calculateRange();
      activeRange.drawRect();
   }
   
   if (timeToTrade()) {
      activeRange.calculateRange();
      activeRange.drawRect();
      activeRange.timeToTrade = true;
      
      if(PositionsTotal() == 0) {
         TradeLogic();  
      }
   } else {
      activeRange.timeToTrade = false;
   }
   
   if (timeToClosePositions()) {
      //-- Close all positions
     
      CloseAllPositions();
      activeRange.sellPlaced = false;
      activeRange.buyPlaced = false;
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
   double ask = SymbolInfoDouble(NULL, SYMBOL_ASK);
   double bid = SymbolInfoDouble(NULL, SYMBOL_BID);
   activeRange.sessionTrend = determineTrend();
   
   bool trendingUp = true;
   bool trendingDown = true;
   
   if (TradeWithTrend) {
      trendingUp = activeRange.sessionTrend == Uptrend;
      trendingDown = activeRange.sessionTrend == Downtrend;
   }
   
   
   //--- Buy when price goes above range high
   if (trendingUp && !activeRange.buyPlaced) {
      OnBuy();
   }
   
   if (trendingDown && !activeRange.sellPlaced) {
      OnSell();
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
      
      //--- if (PositionGetInteger(POSITION_MAGIC) != Magic) continue; //--- Don't check the position of other EAs
      if (PositionGetSymbol(POSITION_SYMBOL) != _Symbol) continue; //--- Don't change position if chart changes
        
      SetTrailingSL(ask, bid, posTicket);
   }
}

//--- Set Trailing SL
void SetTrailingSL(double ask, double bid, ulong posTicket) {
   double posPriceOpen = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSl = PositionGetDouble(POSITION_SL);
   double posTp = PositionGetDouble(POSITION_TP);
   
   if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
      //--- Set trailing SL for buy positions
      double tslTrigger = bid + 1;
      
      //--- Calculate TSL Trigger based on 
      if (TslTriggerFactor > 0) {
         tslTrigger = posPriceOpen + (posPriceOpen - posSl) * TslTriggerFactor;
      } else if (TslTriggerFactor == 0 && TslPoints > 0) {
         tslTrigger = posPriceOpen + TslPoints * _Point;
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
      //--- Set trailing SL for sell positions
      double tslTrigger = ask - 1;
      
      //--- Calculate TSL Trigger based on 
      if (TslTriggerFactor > 0) {
         tslTrigger = posPriceOpen - (posSl - posPriceOpen) * TslTriggerFactor;
      } else if (TslTriggerFactor == 0 && TslPoints > 0) {
         tslTrigger = posPriceOpen - TslPoints * _Point;
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
           
   return isTime;
}

void CloseAllPositions() {
   for (int i=0; i < PositionsTotal(); i++) {
      ulong posTicket = PositionGetTicket(i);
      
      /*
      if (PositionGetInteger(POSITION_MAGIC) != Magic) continue; //--- Don't check the position of other EAs
      if (PositionGetSymbol(POSITION_SYMBOL) != _Symbol) continue; //--- Don't change position if chart changes
      */
      Print("Closing Ticket: ", posTicket);
      trade.PositionClose(posTicket); 
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

