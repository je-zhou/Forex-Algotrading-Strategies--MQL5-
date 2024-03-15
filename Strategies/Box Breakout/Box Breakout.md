# Box Breakout Strategy

## Inspiration  

This strategy was inspired by Rene Balke's range breakout EA that he is currently using in production to trade a portfolio of FTMO accounts.
This is likely to be my first live traded algorithm and I will also be using this strategy to trade FTMO accounts automatically

## The Strategy

This strategy works on the premise the when price breaks out of a range, it will continue in that direction for the remainder of the trading session.
Therefore the idea is to define a range upon which we will map the high and low, and then place a long trade when price moves above this range, and short trade when the price moves below.

## Risk Management

Because we the strategy is based on the notion that breakouts will continue to run, it doesn't make sense to cap our profits with a TP.
Instead, all trades will be closed before the trading day is over which is ~ 1955 GMT

Stops will be at the opposite end of the range the breakout occurs. For example, if a long trade is placed, then the SL will be set at the low of the range and vice versa.

Because we will be trading a FTMO account with this, it is important to manage our bankroll so that there is no risk of ever losing 10% of the account, or 5% in a single trading day.
Therefore we will be risking at most 0.5% of the account balance per trade. The max amount of trades that can be placed in a day is 2, one for each side of the breakout. If both trades fail,
then maximum loss in a day should be 1%, thus we would need 10 consecutive days of losses to break the FTMO's balance drawdown rules. With a 50% win rate, the chance of this happening is very slim.

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

#### Strategy Specific Inputs

- RangeStartHour: The hour you want the range to start tracking at (0 - 23).
- RangeStartMin: The minute you want the range to start tracking at (0 - 59).
- RangeEndHour: The hour you want the range to stop tracking at (0 - 23).
- RangeEndMin: The minute you want the range to stop tracking at (0 - 59).
- ClosePositionsHour: The hour you want to close all positions at (0 - 23).
- ClosePositionsHour: The minute you want to close all positions at (0 - 59).

## Version Control

- v1.0: First release of the trading bot, with optimised inputs for trading the USD/JPY pair.
