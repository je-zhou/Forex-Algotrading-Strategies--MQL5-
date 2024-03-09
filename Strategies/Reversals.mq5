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
input int maxActiveTrades = 1;

//--- Trade Settings
input group "Trade Settings";
input double LotSize = 0.1;
input double TpPoints = 400;
input double SlPoints = 200;
input double SlBuffer = 100;
input int LongTermTrendPeriod = 200;
input int MediumTermTrendPeriod = 50;
input int ShortTermTrendPeriod = 20;

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
int longTermMAHandler;
int medTermMAHandler;
int shortTermMAHandler;

//+------------------------------------------------------------------+
//| Init, Deinit, OnTick                                             |
//+------------------------------------------------------------------+

int OnInit() {
   longTermMAHandler = iMA(_Symbol, Timeframe, LongTermTrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
   medTermMAHandler = iMA(_Symbol, Timeframe, MediumTermTrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
   shortTermMAHandler = iMA(_Symbol, Timeframe, ShortTermTrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
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
//| Trading reversals                                                |
//| Criteria 1: X candles in one direction, followed by one candle   |    
//|             in the opposite direction                            |   
//| Criteria 2: If the opposite direction candle is following the    |    
//|             higher timeframe trend, place a trade                |  
//|------------------------------------------------------------------|
//| Risk Management                                                  |    
//|------------------------------------------------------------------|
//| 1. Trades will be place with a SL risking only 1% of the account |
//| 2. All trades will be placed during London and NY sessions       | 
//| 3. All trades will be closed before the swap rollover            |                                         
//+------------------------------------------------------------------+

void TradeLogic() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double longTermMA[];
   double medTermMA[];
   double shortTermMA[];

   CopyBuffer(longTermMAHandler,0,0,2,longTermMA);
   CopyBuffer(medTermMAHandler,0,0,2,medTermMA);
   CopyBuffer(shortTermMAHandler,0,0,2,shortTermMA);
   
   double open1 = iOpen(_Symbol, Timeframe, 1);
   double close1 = iClose(_Symbol, Timeframe, 1);
   //--- Uptrend, only look for buys
   if (close1 > longTermMA[1] && close1 > medTermMA[1] && close1 > shortTermMA[1]) {
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
      }
   } else if (close1 < longTermMA[0] && close1 < medTermMA[0] && close1 < shortTermMA[0]) {
   //--- Downtrend, only look for sells
      //--- Bearish Trend Down - Buy on Green Candle
      if (close1 < open1) {
         bool isTrend = true;
         
         for (int i = 2; i < TrendCandles + 2; i++) {
            double openI = iOpen(_Symbol, Timeframe, i);
            double closeI = iClose(_Symbol, Timeframe, i);
            
            if (closeI < openI) {
               isTrend = false;
            }     
         }
         
         if (isTrend) {
            OnSell();
         }
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
         double sl = posPriceOpen;
         sl =  NormalizeDouble(sl, _Digits);
         
         if (sl > posSl || posSl == 0) {
            trade.PositionModify(posTicket, sl, posTp);
            Print("Position: ", posTicket, " Modified - SL set to breakeven");
         }
      }
   } else {
      //--- Set Trailing SL if for buy Positions
      if (ask < posPriceOpen - TslTriggerPoints * _Point) {
         double sl = posPriceOpen;
         sl =  NormalizeDouble(sl, _Digits);
         
         if (sl > posSl || posSl == 0) {
            trade.PositionModify(posTicket, sl, posTp);
            Print("Position: ", posTicket, " Modified - SL set to breakeven");
         }
      }
   }
}

