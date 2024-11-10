//+------------------------------------------------------------------+
//|                                                   [TEMPLATE].mq5 |
//|                                           Based on Template v1.1 |
//|                                      Copyright 2024, Jerry Zhou. |
//|                                       https://www.jerryzhou.xyz/ |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Jerry Zhou."
#property link      "https://www.jerryzhou.xyz/"
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
input double RiskPercent = 2.0; //RiskPercent (0 = Use Fixed LotSize)
input double TpPoints = 0; //TPoints (0 = No TP)
input double TpFactor = 0; //TpFactor (0 = Use TpPoints)
input double SlPoints = 0; //SLPoints (0 = No SL)
input double SlFactor = 0; //SlFactor (0 = Use SlPoints)

//--- Trailing SL Settings
input group "Trailing SL Settings";
input double TslTriggerPoints = 0; //TslTriggerPoints (0 = No Tsl)
input double TslTriggerFactor = 0.75; //TslTriggerFactor (0 = Use TslTriggerPoints)
input double TslPoints = 25; //TslPoints (0 = Breakeven)

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

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
int barsTotal;

//+------------------------------------------------------------------+
//| Init, Deinit, OnTick                                             |
//+------------------------------------------------------------------+

int OnInit() {   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {

}

void OnTick() {
   bool timeToTrade = timeToTrade();
   int positions = PositionsTotalByMagic(Magic);
   
   if (positions > 0) {
      //--- Monitor current positions
      ModifyPositions();
   }
   
   if (timeToTrade && positions < maxActiveTrades) {
      //--- Only execute one position per bar
      int bars = iBars(_Symbol, Timeframe);
      
      if (barsTotal != bars) {
         barsTotal = bars;
         
         TradeLogic();
      }
   }
   
   if (!timeToTrade && positions > 0) {
      // CloseAllPositions();
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
        
      // Check if TSL is enabled
      if (TslTriggerPoints != 0 && TslTriggerFactor != 0) {
         SetTrailingSL(ask, bid, posTicket);
      }
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

void CloseAllPositions() {
   for (int i=0; i < PositionsTotal(); i++) {
      ulong posTicket = PositionGetTicket(i);
      
      if (PositionGetInteger(POSITION_MAGIC) != Magic) continue; //--- Don't check the position of other EAs
      if (PositionGetSymbol(POSITION_SYMBOL) != _Symbol) continue; //--- Don't change position if chart changes
        
      trade.PositionClose(posTicket);
      Print("Close Position: ", posTicket, " - All Positions Closed");
   }
}

//+------------------------------------------------------------------+
//| Utilities                                                        |
//+------------------------------------------------------------------+
int PositionsTotalByMagic(int magic) {
   int total = 0;
   for (int i=0; i < PositionsTotal(); i++) {
      PositionGetTicket(i);
      if (PositionGetInteger(POSITION_MAGIC) == magic) total++;
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