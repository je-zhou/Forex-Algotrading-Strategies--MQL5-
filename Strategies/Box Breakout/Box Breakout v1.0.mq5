//+------------------------------------------------------------------+
//|                                                 Box Template.mq5 |
//|                                           Based on Template v1.0 |
//|                                      Copyright 2024, Jerry Zhou. |
//|                                       https://www.jerryzhou.xyz/ |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Jerry Zhou."
#property link      "https://www.jerryzhou.xyz/"
#property version   "1.00"

//--- Imports
#include <trade/trade.mqh>
#include <Object.mqh>
//+------------------------------------------------------------------+
//| General Inputs                                                   |
//+------------------------------------------------------------------+
//--- General Settings
input group "General Settings"
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;
input int Magic = 2; //--- Need to use magic number for each different EA
input int maxActiveTrades = 1;

//--- Trade Settings
input group "Trade Settings";
input double LotSize = 0.1;
input double RiskPercent = 2.0; //RiskPercent (0 = Fix)
input double TpPoints = 300;
input double SlPoints = 150;

//--- Trailing SL Settings
input group "Trailing SL Settings";
input double TslTriggerPoints = 100;
input double TslPoints = 100;

//--- Filter Settings
input group "Time Filter Settings";
input int TimeStartHour = 7;
input int TimeStartMin = 10;

input int TimeEndHour = 15;
input int TimeEndMin = 10;

//+------------------------------------------------------------------+
//| Strategy Specific Inputs                                         |
//+------------------------------------------------------------------+
input group "Strategy Inputs";
input int RangeStartHour = 0;
input int RangeStartMinute = 0;
input int RangeEndHour = 6;
input int RangeEndMinute = 0;
input int DeleteOrdersHour = 19;
input int DeleteOrdersMin = 55;
input int ClosePositionsHour = 19;
input int ClosePositionsMin = 55;

//+------------------------------------------------------------------+
//| Class Definitions                                                |
//+------------------------------------------------------------------+

class CRange : public CObject {
public:
   ulong posTicket;
   datetime timeStart;
   datetime timeEnd;
   int dayShift;
   double high;
   double low;
   CRange(int ds) { dayShift = ds; }
   
   void commentRange() {
      Comment("\nRange Start: ", timeStart,
              "\nRange End: ", timeEnd,
              "\nRange High: ", high,
              "\nRange Low: ", low);
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
      ObjectCreate(0, "Range - " + dayShift, OBJ_RECTANGLE, 0, timeStart, low, timeEnd, high);
      ObjectSetInteger(0, "Range - " + dayShift, OBJPROP_FILL, true);
      
      //--- Paint the trading time
      structTime.hour = ClosePositionsHour;
      structTime.min = ClosePositionsHour;
      datetime tradingEnd = StructToTime(structTime);
      
      ObjectCreate(0, "Trading Period High - " + dayShift, OBJ_RECTANGLE, 0, timeStart, high, tradingEnd, high);
      ObjectCreate(0, "Trading Period Low - " + dayShift, OBJ_RECTANGLE, 0, timeStart, low, tradingEnd, low);
   }
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
int barsTotal;
CRange activeRange(0);

//+------------------------------------------------------------------+
//| Init, Deinit, OnTick                                             |
//+------------------------------------------------------------------+

int OnInit() {   
   for (int i = 1; i < 5; i++) {
      CRange range(i);
      range.calculateRange();
      range.drawRect();
   }
  
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {

}

void OnTick() {
   //--- Monitor current positions
   ModifyPositions();
   
   activeRange.calculateRange();
   activeRange.drawRect();
   
   if (timeToTrade()) {
      if(activeRange.posTicket <= 0) {
         TradeLogic();
      }
     
   } else {
      //-- Close all positions
      
      Print("Closing all positions");
      Print(activeRange.posTicket);
      Print(trade.PositionClose(activeRange.posTicket));
      activeRange.posTicket = 0; 
      
   }
}

/*
+------------------------------------------------------------------+
| Strategy                                                         |
+------------------------------------------------------------------+

We will track the highs and lows of the asian session, then trade
breakouts in the london and ny sessions

Asian Session starts at 

+------------------------------------------------------------------+
| Risk Management                                                  |    
+------------------------------------------------------------------+

1. When trade is over 10 pips in profit, set SL to break even
2. Only risk 2% of the account on each trade

*/

void TradeLogic() {   
   double ask = SymbolInfoDouble(NULL, SYMBOL_ASK);
   double bid = SymbolInfoDouble(NULL, SYMBOL_BID);
   
   //--- Buy when price goes above range high
   if (ask > activeRange.high) {
      OnBuy();
   }
   
   if (bid < activeRange.low) {
      OnSell();
   }
}


//+------------------------------------------------------------------+
//| Buy & Sell Functions                                             |
//+------------------------------------------------------------------+
//--- On Buy
void OnBuy() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = activeRange.low;
   
   double lots = LotSize;
   if(RiskPercent > 0) lots = calcLots(ask-sl);
   
   trade.Buy(lots, _Symbol, ask, sl, 0);
   Print("Buy Order: ", trade.ResultOrder());
   activeRange.posTicket = trade.ResultOrder();
}

//--- On Sell
void OnSell() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tp = bid - TpPoints * _Point;
   double sl = activeRange.high;
   
   double lots = LotSize;
   if(RiskPercent > 0) lots = calcLots(sl-bid);
   
   trade.Sell(lots, _Symbol, bid, sl, 0);
   Print("Sell Order: ", trade.ResultOrder());
   activeRange.posTicket = trade.ResultOrder();
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
      if (bid > posPriceOpen + TslTriggerPoints * _Point) {
         double sl = posPriceOpen; //--- SL set to breakeven
         sl =  NormalizeDouble(sl, _Digits);
         
         if (sl > posSl || posSl == 0) {
            trade.PositionModify(posTicket, sl, posTp);
            Print("Position: ", posTicket, " Modified - SL set to breakeven");
         }
      }
   } else {
      //--- Set trailing SL for sell positions
      if (ask < posPriceOpen - TslTriggerPoints * _Point) {
         double sl = posPriceOpen; //--- SL set to breakeven
         sl =  NormalizeDouble(sl, _Digits);
         
         if (sl > posSl || posSl == 0) {
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
   
   structTime.hour = ClosePositionsHour;
   structTime.min = ClosePositionsMin;
   datetime timeEnd = StructToTime(structTime);
   
   bool isTime = TimeCurrent() >= timeStart && TimeCurrent() < timeEnd;
           
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

void CloseAllPositions() {
   for (int i=0; i < PositionsTotal(); i++) {
      ulong posTicket = PositionGetTicket(i);
      
      if (PositionGetInteger(POSITION_MAGIC) != Magic) continue; //--- Don't check the position of other EAs
      if (PositionGetSymbol(POSITION_SYMBOL) != _Symbol) continue; //--- Don't change position if chart changes
      
      Print("Closing Ticket: ", posTicket);
      
      trade.PositionClose(posTicket); 
      
   }
  }