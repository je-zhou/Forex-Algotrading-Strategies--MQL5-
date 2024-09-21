//+------------------------------------------------------------------+
//|                                                          3MA.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Jerry Zhou"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <trade/trade.mqh>

input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;
input double Lots = 0.1;
input int TpPoints = 300;
input int SlPoints = 200;
input int TslTriggerPoints = 200;
input int TslPoints = 200;

input int kPeriod = 5;
input int dPeriod = 5;
input int stochSmoothing = 5;
input int PointsToSlowEma = 10;

input int Magic = 1; //--- Need to use magic number for each different EA

int movingAvg1Handler;
int movingAvg2Handler;

int stochHandler;

int barsTotal;
CTrade trade;

bool closeToSlowEMA = false;

int OnInit()
  {
  
   Print("ON INIT");
   
   trade.SetExpertMagicNumber(Magic);
   
   movingAvg1Handler = iMA(NULL, Timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
   movingAvg2Handler = iMA(NULL, Timeframe, 150, 0, MODE_EMA, PRICE_CLOSE);
   stochHandler = iStochastic(NULL, Timeframe, kPeriod, dPeriod, stochSmoothing, MODE_SMMA,STO_LOWHIGH);
   
   barsTotal = iBars(NULL, Timeframe);

   return(INIT_SUCCEEDED);
  }
  
  
void OnDeinit(const int reason)
  {
   //---
   Print("ON DEINIT");
  }
  
  
void OnTick()
  {
   //--- Update Position SL
   OnSetTrailingSL();
   
   //--- See if new trade can be made

   int bars = iBars(NULL, Timeframe);
  
   if (barsTotal != bars) {
      barsTotal = bars;
      
      double prevHigh = iHigh(NULL, Timeframe, 1);
      double prevLow = iLow(NULL, Timeframe, 1);
      double prevClose = iClose(NULL, Timeframe, 2);
      double close = iClose(NULL, Timeframe, 1);  
     
      //--- Wait for price to enter between ema1 and ema2
      
      double ema1[];
      double ema2[];
      
      double Karray[];
      double Darray[];
      
      CopyBuffer(movingAvg1Handler, 0, 0, 2, ema1);
      CopyBuffer(movingAvg2Handler, 0, 0, 2, ema2);
      
      bool uptrend = ema1[0] > ema2[0];
      bool betweenEmas = (ema1[0] > prevClose && prevClose > ema2[0]) || (ema1[0] < prevClose && prevClose < ema2[0]);
      
      Print("BetweemEMAS ", betweenEmas);
         
      CopyBuffer(stochHandler, 0, 0, 3, Karray);
      CopyBuffer(stochHandler, 1, 0, 3, Darray);
         
      if (betweenEmas) {
         if (uptrend) {
            closeToSlowEMA = MathAbs(prevLow - ema2[0]) < PointsToSlowEma * _Point;
         } else {
            closeToSlowEMA = MathAbs(ema2[0] - prevHigh) < PointsToSlowEma * _Point;
         }
      } else {
         if (uptrend && (close > ema1[0]) && closeToSlowEMA) {   
            //--- Buy Signal
            OnBuy();
         } else if (!uptrend && (close < ema1[0]) && closeToSlowEMA) {
            //--- Sell Signal
            OnSell();
         }
         
         closeToSlowEMA = false;
      }
    }
  }

void OnBuy() {
   double entry = SymbolInfoDouble(NULL, SYMBOL_ASK);
   entry = NormalizeDouble(entry, _Digits);
   
   double tp = entry + TpPoints * _Point;
   tp = NormalizeDouble(tp, _Digits);
   
   double sl = entry - SlPoints * _Point;
   sl = NormalizeDouble(sl, _Digits);       
   
   trade.Buy(Lots, NULL, entry, sl, tp);
}

void OnSell() {
   double entry = SymbolInfoDouble(NULL, SYMBOL_BID);
   entry = NormalizeDouble(entry, _Digits);
   
   double tp = entry - TpPoints * _Point;
   tp = NormalizeDouble(tp, _Digits);
   
   double sl = entry + SlPoints * _Point;
   sl = NormalizeDouble(sl, _Digits);       
   
   trade.Sell(Lots, NULL, entry, sl, tp);
}

void OnSetTrailingSL() {
   double ask = SymbolInfoDouble(NULL, SYMBOL_ASK);
   double bid = SymbolInfoDouble(NULL, SYMBOL_BID);

   for (int i=0; i < PositionsTotal(); i++) {
      ulong posTicket = PositionGetTicket(i);
      
      if (PositionGetInteger(POSITION_MAGIC) != Magic) continue; //--- Don't check the position of other EAs
      if (PositionGetSymbol(POSITION_SYMBOL) != _Symbol) continue; //--- Don't change position if chart changes

      double posPriceOpen = PositionGetDouble(POSITION_PRICE_OPEN);
      double posSl = PositionGetDouble(POSITION_SL);
      double posTp = PositionGetDouble(POSITION_TP);
      
      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
         if (bid > posPriceOpen + TslTriggerPoints * _Point) {
            double sl = bid - TslPoints * _Point;
            sl =  NormalizeDouble(sl, _Digits);
            
            if (sl > posSl || posSl == 0) {
               trade.PositionModify(posTicket, sl, posTp);
            }
         }
      } else {
         if (ask < posPriceOpen - TslTriggerPoints * _Point) {
            double sl = ask + TslPoints * _Point;
            sl =  NormalizeDouble(sl, _Digits);
            
            if (sl > posSl || posSl == 0) {
               trade.PositionModify(posTicket, sl, posTp);
            }
         }
      }
   }
}