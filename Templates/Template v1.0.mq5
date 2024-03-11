//+------------------------------------------------------------------+
//|                                                   [TEMPLATE].mq5 |
//|                                      Copyright 2024, Jerry Zhou. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Jerry Zhou."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Imports
#include <trade/trade.mqh>

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
input int TrendCandles = 3;
input int LongTermTrendPeriod = 200;
input int MediumTermTrendPeriod = 50;
input int ShortTermTrendPeriod = 20;

//+------------------------------------------------------------------+
//| Standard Global Variables                                        |
//+------------------------------------------------------------------+
CTrade trade;
int barsTotal;
int longTermMAHandler;
int medTermMAHandler;
int shortTermMAHandler;

//+------------------------------------------------------------------+
//| Init, Deinit, OnTick                                             |
//+------------------------------------------------------------------+

int OnInit() {   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {

}

void OnTick() {
   //--- Monitor current positions
   ModifyPositions();
   
   if (timeToTrade()) {
      //--- Only execute one position per bar
      int bars = iBars(_Symbol, Timeframe);
      
      if (barsTotal != bars) {
         barsTotal = bars;
         
         TradeLogic();
      }
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
   
   //--- Buy Conditions
   //--- OnBuy();
   
   //--- Sell Conditions
   //--- OnSell();
}

//+------------------------------------------------------------------+
//| Buy & Sell Functions                                             |
//+------------------------------------------------------------------+
//--- On Buy
void OnBuy() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tp = ask + TpPoints * _Point;
   double sl = ask - SlPoints * _Point;
   
   double lots = LotSize;
   if(RiskPercent > 0) lots = calcLots(ask-sl);
   
   trade.Buy(lots, _Symbol, ask, sl, tp);
}

//--- On Sell
void OnSell() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tp = bid - TpPoints * _Point;
   double sl = bid + SlPoints * _Point;
   
   double lots = LotSize;
   if(RiskPercent > 0) lots = calcLots(sl-bid);
   
   trade.Sell(lots, _Symbol, bid, sl, tp);
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
           "\nTimeFilter: ", isTime);
           
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