```markdown
# Phantom Edge EA
---

## Overview

Phantom Edge EA is an automated trading system (Expert Advisor) designed for the MetaTrader platform. It combines multiple technical indicators and advanced risk management features to make informed trading decisions. The EA is built to adapt to changing market conditions, offering both normal and breakout trade functionalities along with dynamic lot sizing, hedging, and partial trade closures.

---

## Key Features

- **Risk-Based Lot Sizing:**  
  Calculates lot sizes dynamically based on the account balance, user-defined risk percentage, and market volatility (ATR-based stop loss).

- **Multiple Trade Types:**  
  - **Normal Trades:** Uses market direction based on the Simple Moving Average (SMA) and recent price action on higher timeframes (M30 and M15) to trigger trades.
  - **Volatility Breakout Trades:** Identifies breakout opportunities when current ATR exceeds a multiple of its average value. Option to reverse breakout signals is available.

- **Advanced Risk Management:**  
  - **Hedging:** Automatically opens hedge trades when the account drawdown reaches a specified percentage.
  - **Trailing Stop and Trailing Take Profit (TP):** Adjusts stop loss and take profit levels dynamically based on the current ATR.
  - **Partial Trade Closure:** Optionally closes a fraction of a position when the profit reaches a predefined trigger level, locking in gains while keeping the trade open.

- **Trade Frequency & Limitations:**  
  Ensures a minimum time interval between trades and limits the maximum number of concurrent trades (both normal and breakout).

- **Market Direction & Trend Analysis:**  
  Determines the market bias using the price vs. SMA on the M15 timeframe, supported by swing high/low analysis on the M30 timeframe and liquidity sweeps on the M15 timeframe.

- **Debug Logging:**  
  Enhanced with detailed debug logs that provide insights into each step of the trading process (e.g., indicator values, trade execution details, and error messages).

---

## Trading Strategy

1. **Market Direction Determination:**  
   - The EA calculates the current SMA on the M15 timeframe.
   - Compares the current price to the SMA to decide whether to buy (price > SMA) or sell (price < SMA).
   - A reverse mode is available to invert the signal if needed.

2. **M30 Trend Break and M15 Liquidity Sweep:**  
   - On the M30 chart, the EA checks recent swing highs/lows to confirm trend strength.
   - The M15 candle is analyzed to verify if it has swept liquidity around the M30 swing level before confirming a trade signal.

3. **Risk Management & Lot Calculation:**  
   - The lot size is computed based on the account balance, a user-defined risk percentage, and the current market volatility (ATR).
   - A fallback lot value is used if the ATR or tick values are not valid.

4. **Breakout and Normal Trades:**  
   - For breakout trades, fixed stop loss (SL) and take profit (TP) points are used.
   - For normal trades, stop loss is set as an ATR multiple away from the entry, and take profit is defined in price units (if enabled).

5. **Hedging Mechanism:**  
   - Monitors the account drawdown and automatically initiates a hedge trade if losses exceed the predefined threshold.

6. **Trade Management:**  
   - Manages open positions by applying trailing stops and optionally trailing TPs.
   - Checks for conditions to perform a partial close of positions to secure profits while keeping exposure.

---
