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
input int Magic = 1; //--- Need to use magic number for each different EA

int movingAvg1Handler;
int movingAvg2Handler;
int movingAvg3Handler;

int barsTotal;
CTrade trade;

int OnInit()
  {
  
   Print("ON INIT");
   
   trade.SetExpertMagicNumber(Magic);
   
   movingAvg1Handler = iMA(_Symbol, _Period, 9, 0, MODE_SMMA, PRICE_CLOSE);
   movingAvg2Handler = iMA(_Symbol, _Period, 14, 0, MODE_SMMA, PRICE_CLOSE);
   movingAvg3Handler = iMA(_Symbol, _Period, 50, 0, MODE_SMMA, PRICE_CLOSE);
   
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
  
   for (int i=0; i < PositionsTotal(); i++) {
      ulong posTicket = PositionGetTicket(i);
      
      if (PositionGetInteger(POSITION_MAGIC) != Magic) continue; //--- Don't check the position of other EAs
      if (PositionGetSymbol(POSITION_SYMBOL) != _Symbol) continue; //--- Don't change position if chart changes
      
      double ask = SymbolInfoDouble(NULL, SYMBOL_ASK);
      double bid = SymbolInfoDouble(NULL, SYMBOL_BID);
      
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
  
   //--- See if new trade can be made
   
   datetime now = TimeCurrent();
   MqlDateTime stm;
   TimeToStruct(now,stm);
   
   if (stm.hour > 7 && stm.hour < 16) {
      int bars = iBars(NULL, Timeframe);
  
      if (barsTotal != bars) {
         barsTotal = bars;
         
         double ema1[];
         double ema2[];
         double ema3[];
         
         CopyBuffer(movingAvg1Handler,0,0,2,ema1);
         CopyBuffer(movingAvg2Handler,0,0,2,ema2);
         CopyBuffer(movingAvg3Handler,0,0,1,ema3);
         
         double close = iClose(NULL, Timeframe, 0);  
         
         bool aboveTrendLine = ema1[1] > ema3[0] & ema2[1] > ema3[0];
         
         if (ema1[1] > ema2[1] && ema1[0] < ema2[0] && aboveTrendLine) {
            //--- Buy signal when short term MA crosses above medium term MA
            OnBuy();
         } else if (ema1[1] < ema2[1] && ema1[0] > ema2[0] && !aboveTrendLine) {
            //--- Sell signal when short term MA crosses below medium term MA
            OnSell();
         }
       }
   } else {
      Print("Not in trading session");
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
