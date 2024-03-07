//+------------------------------------------------------------------+
//|                                                    Reversals.mq5 |
//|                                      Copyright 2024, Jerry Zhou. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Jerry Zhou."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Imports
#include <trade/trade.mqh>

//--- General Settings
input group "General Settings"
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;
input int Magic = 2; //--- Need to use magic number for each different EA

//--- Trade Settings
input group "Trade Settings";
input double LotSize = 0.1;
input double TpPoints = 400;
input double SlPoints = 200;
input double SlBuffer = 100;


//--- Trailing SL Settings
input group "Trailing SL Settings";
input double TslTriggerPoints = 200;
input double TslPoints = 200;

//+------------------------------------------------------------------+
//| Strategy Specific Inputs                                         |
//+------------------------------------------------------------------+
input group "Strategy Inputs";
input int TrendCandles = 3;

//+------------------------------------------------------------------+
//| Standard Global Variables                                        |
//+------------------------------------------------------------------+
CTrade trade;
int barsTotal;

//+------------------------------------------------------------------+
//| Init, Deinit, OnTick                                             |
//+------------------------------------------------------------------+

int OnInit() {
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

void OnTick() {
   //--- Monitor current positions
   ModifyPositions();
  
   //--- Only execute one position per bar
   int bars = iBars(_Symbol, Timeframe);
   
   if (barsTotal != bars) {
      barsTotal = bars;
      
      TradeLogic();
      
   }
}

//+------------------------------------------------------------------+
//| Trading Functions                                                |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Strategy                                                         |
//|------------------------------------------------------------------|
//|
//+------------------------------------------------------------------+
void TradeLogic() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double open1 = iOpen(_Symbol, Timeframe, 1);
   double close1 = iClose(_Symbol, Timeframe, 1);      
   
   //--- Bullish Trend Up - Sell on Red Candle
   if (open1 < close1) {
      bool isTrend = true;
      
      for (int i = 2; i < TrendCandles + 2; i++) {
         double openI = iOpen(_Symbol, Timeframe, i);
         double closeI = iClose(_Symbol, Timeframe, i);
         
         if (openI < closeI) {
            isTrend = false;
         }     
      }
      
      if (isTrend) {
         OnBuy();
     }
   } else {
   //--- Bearish Candles
      bool isTrend = true;
      
      for (int i = 2; i < TrendCandles + 2; i++) {
         double openI = iOpen(_Symbol, Timeframe, i);
         double closeI = iClose(_Symbol, Timeframe, i);
         
         if (openI > closeI) {
            isTrend = false;
         }     
      }
      
      if (isTrend) {
         OnSell();
      }
   }
}

//--- On Buy

void OnBuy() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tp = ask + TpPoints * _Point;
   double sl = iLow(_Symbol, Timeframe,  iLowest(_Symbol, Timeframe, MODE_LOW, TrendCandles + 1)) - SlBuffer * _Point;
   
   trade.Buy(LotSize, _Symbol, ask, sl, tp);
}

//--- On Sell
void OnSell() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tp = bid - TpPoints * _Point;
   double sl = iHigh(_Symbol, Timeframe, iHighest(_Symbol, Timeframe, MODE_LOW, TrendCandles + 1)) + SlBuffer * _Point;
   
   trade.Sell(LotSize, _Symbol, bid, sl, tp);
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
      //--- Set Trailing SL if for buy Positions
      if (bid > posPriceOpen + TslTriggerPoints * _Point) {
         double sl = bid - TslPoints * _Point;
         sl =  NormalizeDouble(sl, _Digits);
         
         if (sl > posSl || posSl == 0) {
            trade.PositionModify(posTicket, sl, posTp);
            Print("Position: ", posTicket, " Modified - SL set to breakeven");
         }
      }
   } else {
      //--- Set Trailing SL if for buy Positions
      if (ask < posPriceOpen - TslTriggerPoints * _Point) {
         double sl = ask + TslPoints * _Point;
         sl =  NormalizeDouble(sl, _Digits);
         
         if (sl > posSl || posSl == 0) {
            trade.PositionModify(posTicket, sl, posTp);
            Print("Position: ", posTicket, " Modified - SL set to breakeven");
         }
      }
   }
}

