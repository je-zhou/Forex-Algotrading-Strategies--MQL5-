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
input int TpPoints = 400;
input int SlPoints = 200;
input int TslTriggerPoints = 200;
input int TslPoints = 200;

input int Magic = 2; //--- Need to use magic number for each different EA

int barsTotal;
CTrade trade;

int OnInit()
  {
  
   Print("ON INIT");
   
   trade.SetExpertMagicNumber(Magic);
   
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
         if (bid > posPriceOpen + TslTriggerPoints * +_Point) {
            double sl = bid - TslPoints * + _Point;
            sl =  NormalizeDouble(sl, _Digits);
            
            if (sl > posSl || posSl == 0) {
               trade.PositionModify(posTicket, sl, posTp);
            }
         }
      } else {
         if (ask < posPriceOpen - TslTriggerPoints * +_Point) {
            double sl = ask + TslPoints * + _Point;
            sl =  NormalizeDouble(sl, _Digits);
            
            if (sl > posSl || posSl == 0) {
               trade.PositionModify(posTicket, sl, posTp);
            }
         }
      }
   }
   
   int bars = iBars(NULL, Timeframe);
   
   if (barsTotal != bars) {
      barsTotal = bars;
      
      double atr[];
      CopyBuffer(handleAtr, 0,1,1,atr);
      
      double open = iOpen(NULL, Timeframe,1);
      double close = iClose(NULL, Timeframe,1);  
      
      if (open < close && close - open > atr[0] * TriggerFactor) {
         //---Buy Signals
         OnBuy();

      } else if (open > close && open - close > atr[0] * TriggerFactor) {
         //--- Sell Signals
         OnSell();

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
