# Phantom Edge EA

## Overview

Phantom Edge EA is an advanced algorithmic trading Expert Advisor (EA) designed for the MetaTrader platform. 
It combines technical analysis, risk management, and dynamic trade management techniques to execute both normal and breakout trades. 
The EA supports hedging, trailing stops, partial position closing, and utilizes multiple timeframes (M15, M30) for trend confirmation and liquidity sweep detection.

---

## Key Features

- **Risk-Based Lot Sizing:** Calculates the appropriate lot size based on account balance and a user-defined risk percentage.
- **Technical Analysis:** Uses indicators like ATR, SMA, RSI, and MACD for determining market direction and volatility conditions.
- **Multi-Timeframe Confirmation:**
  - **M30 Trend Break:** Confirms swing high/low conditions on the M30 timeframe.
  - **M15 Liquidity Sweep:** Detects liquidity sweeps around M15 swing levels for additional confirmation.
- **Breakout Trading:** Identifies and executes volatility breakout trades when ATR exceeds a specified multiple of its average.
- **Hedging & Recovery:** Automatically places hedge trades when account drawdown exceeds a set percentage.
- **Trade Management:**
  - **Trailing Stop and Trailing TP:** Adjusts stop-loss and take-profit levels dynamically based on ATR.
  - **Partial Position Close:** Optionally closes part of a position when a specified profit threshold is reached.
- **Flexible Input Parameters:** Easily configurable inputs for lot sizes, risk percentage, trade frequency, indicator settings, and more.

---

## Usage

1. **Input Parameters:**  
   Configure the input parameters to suit your trading strategy. Key parameters include:
   - **Risk and Lot Management:** `RiskPercentage`, `Lots`, `UseIncrementalLots`, `LotIncrement`
   - **Trade Frequency:** `TradeFrequency`, `MaxTrades`, `MaxVolatilityTrades`
   - **Stop Loss / Take Profit Settings:** `SLMultiplier`, `TP`, `TP_Points`, `SL_Points`
   - **Trailing Management:** `UseTrailingStop`, `TrailingStopMultiplier`, `UseTrailingTP`
   - **Hedging and Recovery:** `EnableHedging`, `MaxDrawdownPercent`, `HedgeLotMultiplier`, `EnableRecoveryMode`
   - **Technical Indicators:** `RSI_Period`, `MA_Period`, `MACD_Fast`, `MACD_Slow`, `MACD_Signal`, `ATR_Period`, `ATR_Average_Period`
   - **Breakout and Partial Close:** `EnableVolatilityBreakout`, `ATR_Multiplier`, `EnablePartialClose`, `PartialCloseLotFraction`, `PartialCloseTriggerRatio`, `PartialRiskRewardRatio`
   - **Multi-Timeframe Confirmation:** `M30_SwingLookback`

2. **Execution:**  
   Once the EA is attached and the parameters are set, it will monitor the market conditions:
   - It uses the SMA on the M15 timeframe to determine the overall trend.
   - It checks for M30 trend break conditions and validates them with M15 liquidity sweep analysis.
   - It dynamically calculates lot sizes based on the risk percentage and ATR values.
   - If conditions are met, the EA opens a trade (normal or breakout) and manages it with dynamic stop loss, take profit, and trailing adjustments.
   - Hedging is automatically initiated if the account drawdown reaches the specified threshold.

3. **Monitoring and Debugging:**  
   Debug logs are printed to the Experts log in MetaTrader, providing details about indicator values, lot size calculations, trade execution, trailing stop adjustments, partial closes, and hedging actions. These logs can be used to troubleshoot or fine-tune the EA settings.

---

## Input Parameters Details

| Parameter                      | Description                                                                                           | Default Value |
|--------------------------------|-------------------------------------------------------------------------------------------------------|---------------|
| `Lots`                         | Fallback lot size if risk-based calculation fails.                                                  | 0.1           |
| `UseIncrementalLots`           | Enables incremental lot sizing.                                                                       | true          |
| `LotIncrement`                 | The increment amount for lot sizing.                                                                  | 0.2           |
| `MaxTrades`                    | Maximum number of normal trades allowed.                                                              | 1             |
| `TradeFrequency`               | Minimum number of seconds between consecutive trades.                                               | 10            |
| `SLMultiplier`                 | Multiplier used to set the stop-loss distance based on ATR.                                           | 7.5           |
| `TP`                           | Take profit offset (price units) for normal trades (set to 0 to disable).                             | 1750          |
| `PreventExceedingMaxTrades`    | Prevents opening new trades if the maximum allowed is reached.                                        | true          |
| `UseTrailingStop`              | Enables dynamic trailing stop adjustments.                                                          | false         |
| `TrailingStopMultiplier`       | Multiplier for trailing stop distance based on ATR.                                                 | 3.5           |
| `UseTrailingTP`                | Enables dynamic trailing take profit adjustments.                                                   | true          |
| `EnableHedging`                | Enables hedging when drawdown conditions are met.                                                   | true          |
| `MaxDrawdownPercent`           | Drawdown percentage that triggers hedging.                                                          | 10.0          |
| `HedgeLotMultiplier`           | Multiplier applied to lot size for hedge trades.                                                    | 1.5           |
| `EnableRecoveryMode`           | Enables recovery mode in adverse market conditions.                                                 | true          |
| `ReverseMode`                  | Inverts trade signals.                                                                                | false         |
| `ReverseBreakoutTrades`        | Reverses breakout trade signals if enabled.                                                         | false         |
| `MaxVolatilityTrades`          | Maximum number of volatility breakout trades allowed.                                               | 2             |
| `RSI_Period`                   | Period for the RSI indicator.                                                                         | 14            |
| `MA_Period`                    | Period for the simple moving average used for trend detection.                                      | 50            |
| `MACD_Fast`, `MACD_Slow`, `MACD_Signal` | Parameters for the MACD indicator.                                                                | 12, 26, 9     |
| `ATR_Period`                   | Period for the Average True Range indicator.                                                        | 14            |
| `ATR_Average_Period`           | Period for averaging the ATR values for breakout validation.                                        | 14            |
| `EnableVolatilityBreakout`     | Enables trading based on volatility breakout signals.                                               | false         |
| `ATR_Multiplier`               | Multiplier to determine breakout conditions.                                                        | 2.0           |
| `SL_Points` and `TP_Points`    | Fixed stop loss and take profit in points for breakout trades.                                      | 50, 100       |
| `Lookback_Candles`             | Number of candles to look back for breakout analysis.                                               | 3             |
| `Slippage`                     | Maximum allowable slippage for trade execution.                                                     | 3             |
| `EnablePartialClose`           | Enables partial closing of positions when a trigger condition is met.                                | false         |
| `PartialCloseLotFraction`      | Fraction of the position to close when the partial close condition is met.                          | 0.5           |
| `PartialCloseTriggerRatio`     | Profit ratio at which a partial close is triggered.                                                 | 0.5           |
| `PartialRiskRewardRatio`       | Risk to reward ratio used for partial close calculations.                                           | 3             |
| `RiskPercentage`               | Percentage of account balance risked on each trade.                                                 | 1.0           |
| `M30_SwingLookback`            | Number of M30 candles to review for swing high/low detection.                                       | 3             |
| `tradeSymbol`                  | Trading symbol on which the EA will operate.                                                        | "BTCUSD or BTCUSDm"      |

---

## Technical Details

- **Indicator Handles:**  
  The EA initializes handles for the ATR and SMA indicators on the M15 timeframe to determine market volatility and trend direction.

- **Trade Execution:**  
  Trades are executed using the built-in `CTrade` class, which supports both market orders and dynamic order modifications (e.g., trailing stops).

- **Risk Management:**  
  Lot size is dynamically calculated using the current account balance, a risk percentage, and the distance from entry to stop loss (based on ATR). This helps in controlling risk exposure on every trade.

- **Hedging Logic:**  
  When the account drawdown exceeds a specified percentage, a hedge trade is initiated to help mitigate further losses.

- **Multi-Timeframe Analysis:**  
  The EA uses M30 data for swing analysis (to identify key support/resistance levels) and M15 data to confirm liquidity sweeps around these levels.

---

## Debugging & Logs

- **Debug Logs:**  
  Throughout its operation, the EA prints detailed debug logs to the Experts log. These logs include:
  - ATR and SMA values.
  - Calculated lot sizes.
  - Trade execution details (entry price, stop loss, take profit).
  - Updates on trailing stops, partial closes, and hedge trades.
  
- **Monitoring:**  
  Users are encouraged to monitor the debug logs to ensure that the EA is operating as expected and to adjust input parameters based on observed behavior.

---



