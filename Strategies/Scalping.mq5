//+------------------------------------------------------------------+
//|                                                     Scalping.mq5 |
//|                                      Copyright 2024, Jerry Zhou. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Jerry Zhou."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Imports
#include <Trade/Trade.mqh>

//--- General Settings
input group "General Settings";
input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;
input int Magic = 111;

//--- Trade Settings
input group "Trade Settings";
input double Lots = 0.1;
input double RiskPercent = 2.0; //RiskPercent (0 = Fix)
input int OrderDistPoints = 200;
input int TpPoints = 200;
input int SlPoints = 200;

//--- Trailing SL Settings
input group "Trailing SL Settings";
input int TslPoints = 5;
input int TslTriggerPoints = 5;

//--- Strategy
input group "Stratregy Settings";
input int BarsN = 5;
input int ExpirationHours = 50;

//+------------------------------------------------------------------+
//| Standard Global Variables                                        |
//+------------------------------------------------------------------+
CTrade trade;
ulong buyPos, sellPos;
int totalBars;

//+------------------------------------------------------------------+
//| Init, Deinit, OnTick                                             |
//+------------------------------------------------------------------+
int OnInit(){
   trade.SetExpertMagicNumber(Magic);

   if(!trade.SetTypeFillingBySymbol(_Symbol)){
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }
   
   static bool isInit = false;
   
   if(!isInit){
      isInit = true;
      Print(__FUNCTION__," > EA (re)start...");

      for(int i = PositionsTotal()-1; i >= 0; i--){

         CPositionInfo pos;
         if(pos.SelectByIndex(i)){
            if(pos.Magic() != Magic) continue;
            if(pos.Symbol() != _Symbol) continue;

            Print(__FUNCTION__," > Found open position with ticket #",pos.Ticket(),"...");

            if(pos.PositionType() == POSITION_TYPE_BUY) buyPos = pos.Ticket();
            if(pos.PositionType() == POSITION_TYPE_SELL) sellPos = pos.Ticket();
         }
      }

      for(int i = OrdersTotal()-1; i >= 0; i--){
         COrderInfo order;
         
         if(order.SelectByIndex(i)){
            if(order.Magic() != Magic) continue;
            if(order.Symbol() != _Symbol) continue;

            Print(__FUNCTION__," > Found pending order with ticket #",order.Ticket(),"...");

            if(order.OrderType() == ORDER_TYPE_BUY_STOP) buyPos = order.Ticket();
            if(order.OrderType() == ORDER_TYPE_SELL_STOP) sellPos = order.Ticket();
         }
      }
   }

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){}

void OnTick(){
   processPos(buyPos);
   processPos(sellPos);

   int bars = iBars(_Symbol,Timeframe);

   if(totalBars != bars){
      totalBars = bars;

      if(buyPos <= 0){
         double high = findHigh();

         if(high > 0){
            executeBuy(high);
         }
      }
      
      if(sellPos <= 0){
         double low = findLow();

         if(low > 0){
            executeSell(low);
         }
      }
   }
}



void  OnTradeTransaction(
   const MqlTradeTransaction&    trans,
   const MqlTradeRequest&        request,
   const MqlTradeResult&         result
){
   if(trans.type == TRADE_TRANSACTION_ORDER_ADD){
      COrderInfo order;
      
      if(order.Select(trans.order)){
         if(order.Magic() == Magic){
            if(order.OrderType() == ORDER_TYPE_BUY_STOP){
               buyPos = order.Ticket();
            }else if(order.OrderType() == ORDER_TYPE_SELL_STOP){
               sellPos = order.Ticket();
            }
         }
      }
   }
}

void processPos(ulong &posTicket){
   if(posTicket <= 0) return;
   if(OrderSelect(posTicket)) return;

   CPositionInfo pos;

   if(!pos.SelectByTicket(posTicket)){
      posTicket = 0;
      
      return;
   }else{
      if(pos.PositionType() == POSITION_TYPE_BUY){
         double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
         
         if(bid > pos.PriceOpen() + TslTriggerPoints * _Point){
            double sl = bid - TslPoints * _Point;
            sl = NormalizeDouble(sl,_Digits);
         
            if(sl > pos.StopLoss()){
               trade.PositionModify(pos.Ticket(),sl,pos.TakeProfit());
            }
         }
      }else if(pos.PositionType() == POSITION_TYPE_SELL){
         double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
     
         if(ask < pos.PriceOpen() - TslTriggerPoints * _Point){
            double sl = ask + TslPoints * _Point;
            sl = NormalizeDouble(sl,_Digits);

            if(sl < pos.StopLoss() || pos.StopLoss() == 0){
               trade.PositionModify(pos.Ticket(),sl,pos.TakeProfit());
            }
         }
      }
   }
}

void executeBuy(double entry){
   entry = NormalizeDouble(entry,_Digits);
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   if(ask > entry - OrderDistPoints * _Point) return;
  
   double tp = entry + TpPoints * _Point;
   tp = NormalizeDouble(tp,_Digits);
   
   double sl = entry - SlPoints * _Point;
   sl = NormalizeDouble(sl,_Digits);
   
   double lots = Lots;
   if(RiskPercent > 0) lots = calcLots(entry-sl);

   datetime expiration = iTime(_Symbol,Timeframe,0) + ExpirationHours * PeriodSeconds(PERIOD_H1);

   trade.BuyStop(lots,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration);
   buyPos = trade.ResultOrder();
}



void executeSell(double entry){
   entry = NormalizeDouble(entry,_Digits);  
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   if(bid < entry + OrderDistPoints * _Point) return;

   double tp = entry - TpPoints * _Point;
   tp = NormalizeDouble(tp,_Digits);

   double sl = entry + SlPoints * _Point;
   sl = NormalizeDouble(sl,_Digits);

   double lots = Lots;
   if(RiskPercent > 0) lots = calcLots(sl-entry);

   datetime expiration = iTime(_Symbol,Timeframe,0) + ExpirationHours * PeriodSeconds(PERIOD_H1);

   trade.SellStop(lots,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration);
   sellPos = trade.ResultOrder();
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

double findHigh(){
   double highestHigh = 0;

   for(int i = 0; i < 200; i++){
      double high = iHigh(_Symbol,Timeframe,i);
      
      if(i > BarsN && iHighest(_Symbol,Timeframe,MODE_HIGH,BarsN*2+1,i-BarsN) == i){
         if(high > highestHigh){
            return high;
         }
      }

      highestHigh = MathMax(high,highestHigh);
   }
   return -1;
}

double findLow(){
   double lowestLow = DBL_MAX;

   for(int i = 0; i < 200; i++){
      double low = iLow(_Symbol,Timeframe,i);
      
      if(i > BarsN && iLowest(_Symbol,Timeframe,MODE_LOW,BarsN*2+1,i-BarsN) == i){
         if(low < lowestLow){
            return low;
         }
      }   
      
      lowestLow = MathMin(low,lowestLow);
   }
   return -1;
}