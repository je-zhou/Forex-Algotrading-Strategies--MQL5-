# Box Breakout Strategy

## Inspiration  

This strategy was inspired by Rene Balke's range breakout EA that he is currently using in production to trade a portfolio of FTMO accounts.
This is likely to be my first live traded algorithm and I will also be using this strategy to trade FTMO accounts automatically

## The Strategy

This strategy works on the premise the when price breaks out of a range, it will continue in that direction for the remainder of the trading session.
Therefore the idea is to define a range upon which we will map the high and low, and then place a long trade when price moves above this range, and short trade when the price moves below.

## Risk Management

Because the strategy is based on the notion that breakouts will continue to run, it doesn't make sense to cap our profits with a TP.
Instead, all trades will be closed before the trading day is over which is ~ 1955 GMT

Stops will be at the opposite end of the range the breakout occurs. For example, if a long trade is placed, then the SL will be set at the low of the range and vice versa.

Because we will be trading an FTMO account with this, it is important to manage our bankroll so that there is no risk of ever losing 10% of the account, or 5% in a single trading day.
Therefore we will be risking at most 0.5% of the account balance per trade. 

**Daily Trade Limits**: The `MaxTradesPerDay` parameter controls how many trades can execute per day. When this limit is reached, all remaining pending orders are automatically cancelled by the EA. This prevents over-trading and helps maintain consistent risk management. With a default setting of 1 trade per day and 0.5% risk per trade, maximum daily loss is controlled at 0.5% of account balance.

### Inputs Explained

Below is a short explaination of what each input does.

#### General Settings
 
- Timeframe: What timeframe the range should be calculated on (ideally this should be set to 1m so that it is updated at the finest level)
- Magic: Each EA needs a unique magic number so that it knows which trades are its own if there are multiple EAs running

#### Trade Settings

- LotSize: This is the fixed lot size used if you want to use a consistent lot size each trade. Requires RiskPercent input to be 0.
- RiskPercent: This is how much of the account you want to risk per trade.
- TpPoints: How many fixed points you want to set your take profit at.
- TpFactor: If you want to set a take profit at a multiple of the breakout range.

#### Trailing Stop Loss Settings

- TslTriggerPoints: A fixed number of points before the trade sets a trailing stop loss. Requires TslTriggerFactor to be 0.
- TslTriggerFactor: A multiple of the range at which you want to set a trailing stop loss. Has priority over TslTriggerPoints.
- TslPoints: The number of fixed points you want to set to set the new stop loss at. 0 means setting the stop loss to breakeven.

#### Trend Settings

- TradeWithTrend: Forces strategy to only trade with the trend. **Optimized default: true**
- TrendMaTimeframe: The timeframe the trending moving average should be calculated. **Optimized default: 1 Hour (PERIOD_H1)**
- SlowTrendMaMethod: The type of moving average used to determine the slow trend.
- SlowTrendMaPeriod: The period used to calculate the slow trending moving average.
- FastTrendMaMethod: The type of moving average used to determine the fast trend.
- FastTrendMaPeriod: The period used to calculate the fast trending moving average.
- RangeBuffer: Amount in points between the two moving averages to represent a ranging market.

#### Strategy Specific Inputs

- RangeStartHour: The hour you want the range to start tracking at (0 - 23).
- RangeStartMin: The minute you want the range to start tracking at (0 - 59).
- RangeEndHour: The hour you want the range to stop tracking at (0 - 23).
- RangeEndMin: The minute you want the range to stop tracking at (0 - 59).
- StopTradingHour: The hour you want to stop placing any new orders at (0 - 23).
- StopTradingMinute: The minute you want to stop placing any new orders at (0 - 59).
- ClosePositionsHour: The hour you want to close all positions at (0 - 23).
- ClosePositionsMinute: The minute you want to close all positions at (0 - 59).
- **MaxTradesPerDay**: Maximum number of executed trades allowed per day. When this limit is reached, the EA automatically cancels all remaining pending orders. Default: 1 (provides OCO behavior - only one trade executes per day).

## ChangeLog

- v1.2:
  - **Enhanced MaxTradesPerDay Logic**: Added intelligent pending order cancellation when daily trade limit is reached
  - **Optimized Default Settings**: Changed default TrendMaTimeframe to 1 Hour (PERIOD_H1) for improved trend detection
  - **Improved Order Management**: EA now automatically cancels remaining pending orders when MaxTradesPerDay limit is reached
  - **Better Risk Control**: MaxTradesPerDay parameter now provides true OCO (One-Cancels-Other) behavior when set to 1
  - **Enhanced Logging**: Added detailed logging for order cancellation and daily trade limit tracking
  - **Fixed Input Parameter**: Corrected StopTradingMinute parameter description format
- v1.1:
  - Persistent boxes to make testing clearer
  - Added trading stop time (which can be earlier than the exit all positions time)
  - Added option to trade with trend based on fast and slow moving averages
  - Changed the buy and sell orders from market to stops
- v1.0:
  - First release of the trading bot, with optimized inputs for trading the USD/JPY pair.
