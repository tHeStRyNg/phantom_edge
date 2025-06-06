//+------------------------------------------------------------------+
//| Expert Advisor Name: Phantom Edge EA                           |
//| Version: 0.11 (Enhanced profit protection & dynamic exits)       |
//| Author: Hamed Al Zakwani / Modified by [Your Name]                |
//| Copyright © 2025 Hamed Al Zakwani                                |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//|                           INPUTS                                 |
//+------------------------------------------------------------------+

//---- Trade Management Inputs [Group: Trade Settings]
input group "--- Trade Management Inputs ---"
input double   Lots                      = 0.1;         // Fallback lot size if risk-based calc fails [Trade Settings]
input bool     UseIncrementalLots        = true;        // Enable incremental lot sizing [Trade Settings]
input double   LotIncrement              = 0.2;         // Increment size for lot scaling [Trade Settings]
input int      MaxTrades                 = 1;           // Maximum number of normal trades allowed [Trade Settings]
input int      TradeFrequency            = 10;          // Minimum seconds between trades [Trade Settings]
input double   SLMultiplier              = 7.5;         // Stop-loss distance multiplier (e.g., ATR multiplier) [Trade Settings]
input double   TP                        = 1750;        // Fixed take profit offset (price units) for normal trades (0 to disable) [Trade Settings]

//---- Trailing Stop Inputs [Group: Trade Settings]
input group "--- Trailing Stop Inputs ---"
input bool     UseTrailingStop           = true;        // Enable trailing stop [Trade Settings]
input double   TrailingStopMultiplier    = 3.5;         // Trailing stop distance = ATR * multiplier [Trade Settings]
input bool     UseTrailingTP             = true;        // Enable trailing take profit [Trade Settings]

//---- Hedging & Recovery Inputs [Group: Risk Management]
input group "--- Hedging & Recovery Inputs ---"
input bool     EnableHedging             = true;        // Enable hedging on drawdown [Risk Management]
input double   MaxDrawdownPercent        = 10.0;        // Drawdown percentage to trigger hedging [Risk Management]
input double   HedgeLotMultiplier        = 1.5;         // Hedge trade lot multiplier [Risk Management]
input bool     EnableRecoveryMode        = true;        // Enable recovery mode [Risk Management]
input bool     ReverseMode               = false;       // Invert trade signals if enabled [Risk Management]
input bool     ReverseBreakoutTrades     = false;       // Reverse breakout trade signals if enabled [Risk Management]
input int      MaxVolatilityTrades       = 2;           // Maximum breakout trades allowed [Risk Management]

//---- New Profit Protection & Exit Inputs [Group: Profit Protection]
input group "--- New Profit Protection & Exit Inputs ---"
input bool     UseProfitLock             = true;        // Enable profit lock mechanism [Profit Protection]
input double   ProfitLockPercent         = 2.0;         // Equity must increase by this % from trade entry to trigger profit lock [Profit Protection]
input bool     UseDynamicTP              = true;        // Use ATR-based dynamic take profit [Profit Protection]
input double   DynamicTPMultiplier       = 2.0;         // Multiplier for ATR to set dynamic TP [Profit Protection]
input bool     UseDynamicSLAdjustment    = true;        // Enable dynamic SL tightening for fast profit moves [Profit Protection]
input double   SLAdjustmentThreshold     = 0.5;         // If price moves > this multiple of ATR in one candle, adjust SL [Profit Protection]
input double   SLTightenMultiplier       = 0.5;         // New SL distance = ATR * this multiplier (from current price) [Profit Protection]
input bool     UseTimeBasedExit          = false;       // Enable time-based trade exit [Profit Protection]
input int      TradeMaxDurationMinutes   = 120;         // Maximum allowed trade duration in minutes [Profit Protection]
input bool     UseCurrencyBasedTP        = false;       // Enable fixed-dollar TP instead of pip-based [Profit Protection]
input double   CurrencyTP                = 50.0;        // Fixed dollar profit target per trade [Profit Protection]

//---- Indicator Settings Inputs [Group: Indicators]
input group "--- Indicator Settings Inputs ---"
input int      RSI_Period                = 14;          // Period for RSI indicator [Indicators]
input int      MA_Period                 = 50;          // Period for the SMA (for trend detection) [Indicators]
input int      MACD_Fast                 = 12;          // MACD fast period [Indicators]
input int      MACD_Slow                 = 26;          // MACD slow period [Indicators]
input int      MACD_Signal               = 9;           // MACD signal period [Indicators]
input int      ATR_Period                = 14;          // ATR period [Indicators]
input int      ATR_Average_Period        = 14;          // ATR average period (for breakout validation) [Indicators]

//---- Volatility Breakout Inputs [Group: Volatility Breakout]
input group "--- Volatility Breakout Inputs ---"
input bool     EnableVolatilityBreakout  = false;       // Enable breakout trades based on volatility [Volatility Breakout]
input double   ATR_Multiplier            = 2.0;         // Breakout condition: ATR > (average ATR * multiplier) [Volatility Breakout]
input int      SL_Points                 = 50;          // Fixed SL in points for breakout trades [Volatility Breakout]
input int      TP_Points                 = 100;         // Fixed TP in points for breakout trades [Volatility Breakout]
input int      Lookback_Candles          = 3;           // Number of candles to look back for breakout [Volatility Breakout]
input int      Slippage                  = 3;           // Maximum allowable slippage [Volatility Breakout]

//---- Partial Close Inputs [Group: Partial Close]
input group "--- Partial Close Inputs ---"
input bool     EnablePartialClose        = false;       // Enable partial closing of positions [Partial Close]
input double   PartialCloseLotFraction   = 0.5;         // Fraction of position to close partially [Partial Close]
input double   PartialCloseTriggerRatio  = 0.5;         // Profit ratio trigger for partial close (50% of target distance) [Partial Close]
input int      PartialRiskRewardRatio    = 3;           // Risk-reward ratio for partial close calculation [Partial Close]

//---- Risk Management Input [Group: Risk Management]
input group "--- Risk Management Input ---"
input double   RiskPercentage            = 1.0;         // Percentage of account balance to risk per trade [Risk Management]

//---- Multi-Timeframe Analysis Inputs [Group: Multi-Timeframe Analysis]
input group "--- Multi-Timeframe Analysis Inputs ---"
input int      M30_SwingLookback         = 3;           // Lookback period on M30 for swing high/low detection [Multi-Timeframe Analysis]

//---- Other Inputs [Group: General]
input group "--- Trading Asset ---"
input string   tradeSymbol               = "BTCUSD";    // Trading symbol [General]

//+------------------------------------------------------------------+
//|                        GLOBAL VARIABLES                          |
//+------------------------------------------------------------------+
datetime lastTradeTime = 0;
int normalTradeCount   = 0;
int volatilityTradeCount = 0;
bool hedged = false;
int lastTradeDay = -1;        // day-of-year of last trade
double lastTradeEquity = 0.0; // equity at time of last trade (for profit lock)

// Array for tracking partially closed ticket IDs.
ulong gPartialClosedTickets[];

// Initial account balance when EA starts.
double initialBalance = 0;

// Indicator handles and buffers.
int atrHandle = INVALID_HANDLE;
double atrBuffer[];
int maHandle = INVALID_HANDLE;
double maBuffer[];

//+------------------------------------------------------------------+
//| Helper: ArrayFindTicket                                          |
//+------------------------------------------------------------------+
int ArrayFindTicket(ulong &arr[], ulong ticket)
{
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == ticket)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| CalculateRiskBasedLotSize                                        |
//+------------------------------------------------------------------+
double CalculateRiskBasedLotSize(ENUM_ORDER_TYPE type, double entryPrice)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskDollars = accountBalance * (RiskPercentage / 100.0);
   double atrVal = GetATR();
   if(atrVal <= 0)
      return Lots;
   double stopLossDistance = SLMultiplier * atrVal;
   double tickValue = SymbolInfoDouble(tradeSymbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0)
      return Lots;
   double stopLossPoints = stopLossDistance / _Point;
   double riskPerLot = stopLossPoints * tickValue;
   double calcLots = riskDollars / riskPerLot;
   double minLot = SymbolInfoDouble(tradeSymbol, SYMBOL_VOLUME_MIN);
   if(calcLots < minLot)
      calcLots = minLot;
   return NormalizeDouble(calcLots, 2);
}

//+------------------------------------------------------------------+
//| CheckM30TrendBreak                                               |
//+------------------------------------------------------------------+
bool CheckM30TrendBreak(ENUM_ORDER_TYPE tradeSignal, double &m30_level)
{
   int lookback = M30_SwingLookback;
   double swingHigh = -DBL_MAX, swingLow = DBL_MAX;
   for (int i = 1; i <= lookback; i++)
   {
      double high = iHigh(tradeSymbol, PERIOD_M30, i);
      double low  = iLow(tradeSymbol, PERIOD_M30, i);
      if(high > swingHigh) swingHigh = high;
      if(low < swingLow)   swingLow = low;
   }
   double lastClose = iClose(tradeSymbol, PERIOD_M30, 1);
   if(tradeSignal == ORDER_TYPE_SELL)
   {
      if(lastClose < swingHigh)
      {
         m30_level = swingHigh;
         return true;
      }
   }
   else if(tradeSignal == ORDER_TYPE_BUY)
   {
      if(lastClose > swingLow)
      {
         m30_level = swingLow;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| CheckM15LiquiditySweep                                           |
//+------------------------------------------------------------------+
bool CheckM15LiquiditySweep(ENUM_ORDER_TYPE tradeSignal, double m30_level)
{
   double candleHigh  = iHigh(tradeSymbol, PERIOD_M15, 1);
   double candleLow   = iLow(tradeSymbol, PERIOD_M15, 1);
   double candleClose = iClose(tradeSymbol, PERIOD_M15, 1);
   if(tradeSignal == ORDER_TYPE_SELL)
      return (candleHigh > m30_level && candleClose < m30_level);
   else if(tradeSignal == ORDER_TYPE_BUY)
      return (candleLow < m30_level && candleClose > m30_level);
   return false;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(tradeSymbol, PERIOD_M15, ATR_Period);
   if(atrHandle == INVALID_HANDLE)
      return INIT_FAILED;
   maHandle = iMA(tradeSymbol, PERIOD_M15, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE)
      return INIT_FAILED;
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   ArrayInitialize(gPartialClosedTickets, 0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
   if(maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
}

//+------------------------------------------------------------------+
//| GetATR                                                           |
//+------------------------------------------------------------------+
double GetATR()
{
   double atrVal = 0;
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
      atrVal = atrBuffer[0];
   return atrVal;
}

//+------------------------------------------------------------------+
//| GetSMA                                                           |
//+------------------------------------------------------------------+
double GetSMA()
{
   double smaVal = 0;
   if(CopyBuffer(maHandle, 0, 0, 1, maBuffer) > 0)
      smaVal = maBuffer[0];
   return smaVal;
}

//+------------------------------------------------------------------+
//| CountTrades                                                      |
//+------------------------------------------------------------------+
void CountTrades()
{
   normalTradeCount = 0;
   volatilityTradeCount = 0;
   int total = PositionsTotal();
   for (int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string comment = PositionGetString(POSITION_COMMENT);
         if(StringFind(comment, "ATR Breakout") != -1)
            volatilityTradeCount++;
         else
            normalTradeCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| ManageHedging                                                    |
//+------------------------------------------------------------------+
void ManageHedging()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = ((balance - equity) / balance) * 100;
   if(drawdown >= MaxDrawdownPercent && !hedged && EnableHedging)
   {
      OpenHedgeTrade();
      hedged = true;
   }
   else if(drawdown < MaxDrawdownPercent * 0.5)
      hedged = false;
}

//+------------------------------------------------------------------+
//| OpenHedgeTrade                                                   |
//+------------------------------------------------------------------+
void OpenHedgeTrade()
{
   ENUM_ORDER_TYPE hedgeType = (ReverseMode) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (hedgeType == ORDER_TYPE_BUY) ? SymbolInfoDouble(tradeSymbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(tradeSymbol, SYMBOL_BID);
   double stopLoss = 0, takeProfit = 0;
   double atrVal = GetATR();
   if(atrVal <= 0)
      return;
   if(hedgeType == ORDER_TYPE_BUY)
   {
      stopLoss = price - SLMultiplier * atrVal;
      if(TP > 0)
         takeProfit = price + TP;
   }
   else
   {
      stopLoss = price + SLMultiplier * atrVal;
      if(TP > 0)
         takeProfit = price - TP;
   }
   if(hedgeType == ORDER_TYPE_BUY)
      trade.Buy(Lots * HedgeLotMultiplier, tradeSymbol, price, stopLoss, takeProfit, "Hedge Trade");
   else
      trade.Sell(Lots * HedgeLotMultiplier, tradeSymbol, price, stopLoss, takeProfit, "Hedge Trade");
}

//+------------------------------------------------------------------+
//| DetermineMarketDirection                                           |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE DetermineMarketDirection()
{
   double currentPrice = SymbolInfoDouble(tradeSymbol, SYMBOL_BID);
   double sma = GetSMA();
   return (currentPrice > sma) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
}

//+------------------------------------------------------------------+
//| GetAverageATR                                                    |
//+------------------------------------------------------------------+
double GetAverageATR(int period)
{
   double sum = 0;
   double atrValues[];
   if(CopyBuffer(atrHandle, 0, 0, period, atrValues) > 0)
   {
      for(int i = 0; i < period; i++)
         sum += atrValues[i];
      return sum / period;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| CheckBreakout                                                    |
//+------------------------------------------------------------------+
bool CheckBreakout(bool isBuy)
{
   double atr    = GetATR();
   double avgATR = GetAverageATR(ATR_Average_Period);
   if(atr <= 0 || avgATR <= 0)
      return false;
   return (atr > ATR_Multiplier * avgATR);
}

//+------------------------------------------------------------------+
//| OpenTrade                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, string comment)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(tradeSymbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(tradeSymbol, SYMBOL_BID);
   double stopLoss = 0, takeProfit = 0;
   double atrVal = GetATR();
   if(atrVal <= 0)
      return;
   // For breakout trades, use fixed points.
   if(StringFind(comment, "ATR Breakout") != -1)
   {
      if(type == ORDER_TYPE_BUY)
      {
         stopLoss = price - SL_Points * _Point;
         takeProfit = price + TP_Points * _Point;
      }
      else
      {
         stopLoss = price + SL_Points * _Point;
         takeProfit = price - TP_Points * _Point;
      }
   }
   else
   {
      double riskBasedLots = CalculateRiskBasedLotSize(type, price);
      double riskPriceDistance = SLMultiplier * atrVal;
      stopLoss = (type == ORDER_TYPE_BUY) ? price - riskPriceDistance : price + riskPriceDistance;
      
      // Determine TP using one of several methods:
      if(UseCurrencyBasedTP)
      {
         // Calculate required price move to gain the fixed dollar target.
         double tickValue = SymbolInfoDouble(tradeSymbol, SYMBOL_TRADE_TICK_VALUE);
         double priceMove = CurrencyTP / (riskBasedLots * tickValue);
         takeProfit = (type == ORDER_TYPE_BUY) ? price + priceMove : price - priceMove;
      }
      else if(UseDynamicTP)
      {
         // Dynamic TP based on ATR.
         takeProfit = (type == ORDER_TYPE_BUY) ? price + (atrVal * DynamicTPMultiplier) : price - (atrVal * DynamicTPMultiplier);
      }
      else if(TP > 0)
      {
         takeProfit = (type == ORDER_TYPE_BUY) ? price + TP : price - TP;
      }
      
      // Execute the trade.
      if(type == ORDER_TYPE_BUY)
      {
         if(trade.Buy(riskBasedLots, tradeSymbol, price, stopLoss, takeProfit, comment))
         {
            lastTradeTime = TimeCurrent();
            MqlDateTime dt;
            TimeToStruct(TimeCurrent(), dt);
            lastTradeDay = dt.day_of_year;
            lastTradeEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         }
      }
      else
      {
         if(trade.Sell(riskBasedLots, tradeSymbol, price, stopLoss, takeProfit, comment))
         {
            lastTradeTime = TimeCurrent();
            MqlDateTime dt;
            TimeToStruct(TimeCurrent(), dt);
            lastTradeDay = dt.day_of_year;
            lastTradeEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         }
      }
      return;
   }
   // For breakout trade fallback.
   if(type == ORDER_TYPE_BUY)
   {
      if(trade.Buy(Lots, tradeSymbol, price, stopLoss, takeProfit, comment))
      {
         lastTradeTime = TimeCurrent();
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         lastTradeDay = dt.day_of_year;
         lastTradeEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      }
   }
   else
   {
      if(trade.Sell(Lots, tradeSymbol, price, stopLoss, takeProfit, comment))
      {
         lastTradeTime = TimeCurrent();
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         lastTradeDay = dt.day_of_year;
         lastTradeEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      }
   }
}

//+------------------------------------------------------------------+
//| ApplyTrailingStop                                                |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   if(!UseTrailingStop && !UseTrailingTP)
      return;
      
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double price = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(tradeSymbol, SYMBOL_BID)
                                                       : SymbolInfoDouble(tradeSymbol, SYMBOL_ASK);
         double atrVal = GetATR();
         if(atrVal <= 0)
            continue;
         double trailingDistance = atrVal * TrailingStopMultiplier;
         if(UseTrailingStop)
         {
            if(posType == POSITION_TYPE_BUY)
            {
               double newSL = price - trailingDistance;
               if(newSL > currentSL)
                  currentSL = newSL;
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               double newSL = price + trailingDistance;
               if(currentSL == 0 || newSL < currentSL)
                  currentSL = newSL;
            }
         }
         if(UseTrailingTP && currentTP != 0)
         {
            if(posType == POSITION_TYPE_BUY)
            {
               double newTP = price + trailingDistance;
               if(newTP > currentTP)
                  currentTP = newTP;
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               double newTP = price - trailingDistance;
               if(newTP < currentTP)
                  currentTP = newTP;
            }
         }
         // Position modification can be enabled if desired:
         // trade.PositionModify(ticket, currentSL, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
//| CheckAndTakePartialClose                                         |
//+------------------------------------------------------------------+
void CheckAndTakePartialClose()
{
   if(!EnablePartialClose)
      return;
      
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ArrayFindTicket(gPartialClosedTickets, ticket) >= 0)
         continue;
         
      if(PositionSelectByTicket(ticket))
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL  = PositionGetDouble(POSITION_SL);
         double volume     = PositionGetDouble(POSITION_VOLUME);
         if(volume <= 0)
            continue;
         double riskDistance = MathAbs(entryPrice - currentSL);
         if(riskDistance <= 0)
            continue;
         double fullTPDistance = riskDistance * PartialRiskRewardRatio;
         double triggerPrice;
         if(posType == POSITION_TYPE_BUY)
         {
            triggerPrice = entryPrice + fullTPDistance * PartialCloseTriggerRatio;
            double currentPrice = SymbolInfoDouble(tradeSymbol, SYMBOL_BID);
            if(currentPrice >= triggerPrice)
            {
               double closeVolume = volume * PartialCloseLotFraction;
               if(closeVolume >= SymbolInfoDouble(tradeSymbol, SYMBOL_VOLUME_MIN))
               {
                  if(trade.PositionClosePartial(ticket, closeVolume))
                  {
                     ArrayResize(gPartialClosedTickets, ArraySize(gPartialClosedTickets)+1);
                     gPartialClosedTickets[ArraySize(gPartialClosedTickets)-1] = ticket;
                  }
               }
            }
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            triggerPrice = entryPrice - fullTPDistance * PartialCloseTriggerRatio;
            double currentPrice = SymbolInfoDouble(tradeSymbol, SYMBOL_ASK);
            if(currentPrice <= triggerPrice)
            {
               double closeVolume = volume * PartialCloseLotFraction;
               if(closeVolume >= SymbolInfoDouble(tradeSymbol, SYMBOL_VOLUME_MIN))
               {
                  if(trade.PositionClosePartial(ticket, closeVolume))
                  {
                     ArrayResize(gPartialClosedTickets, ArraySize(gPartialClosedTickets)+1);
                     gPartialClosedTickets[ArraySize(gPartialClosedTickets)-1] = ticket;
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ForceCloseTrades                                                 |
//+------------------------------------------------------------------+
//| - Force close profitable trades at/after 21:00 (non-Friday)        |
//| - Force close all trades on Fridays at/after 20:00                 |
//+------------------------------------------------------------------+
void ForceCloseTrades()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   bool forceCloseAll = false;
   bool forceCloseProfitable = false;
   if(dt.day_of_week == 5 && dt.hour >= 20)
      forceCloseAll = true;
   else if(dt.hour >= 21)
      forceCloseProfitable = true;
   if(forceCloseAll || forceCloseProfitable)
   {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(forceCloseAll || (forceCloseProfitable && profit > 0))
               trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ProfitLockMechanism: Adjust SL when equity has increased         |
//+------------------------------------------------------------------+
void ProfitLockMechanism()
{
   if(!UseProfitLock)
      return;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   // If equity increased by ProfitLockPercent from trade entry equity, tighten SL
   if(currentEquity >= lastTradeEquity * (1 + ProfitLockPercent/100.0))
   {
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double price = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(tradeSymbol, SYMBOL_BID)
                                                          : SymbolInfoDouble(tradeSymbol, SYMBOL_ASK);
            double atrVal = GetATR();
            if(atrVal <= 0)
               continue;
            double newSL;
            if(posType == POSITION_TYPE_BUY)
               newSL = price - (atrVal * SLTightenMultiplier);
            else
               newSL = price + (atrVal * SLTightenMultiplier);
            // Adjust the SL of the position to secure profits.
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DynamicSLAdjustment: Tighten SL for fast profit moves            |
//+------------------------------------------------------------------+
void DynamicSLAdjustment()
{
   if(!UseDynamicSLAdjustment)
      return;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(tradeSymbol, SYMBOL_BID)
                                                             : SymbolInfoDouble(tradeSymbol, SYMBOL_ASK);
         double atrVal = GetATR();
         if(atrVal <= 0)
            continue;
         // Check if price moved more than the threshold (in ATR multiples)
         if(posType == POSITION_TYPE_BUY && (currentPrice - entryPrice) > (atrVal * SLAdjustmentThreshold))
         {
            double newSL = currentPrice - (atrVal * SLTightenMultiplier);
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
         else if(posType == POSITION_TYPE_SELL && (entryPrice - currentPrice) > (atrVal * SLAdjustmentThreshold))
         {
            double newSL = currentPrice + (atrVal * SLTightenMultiplier);
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TimeBasedExit: Close trades that have been open too long          |
//+------------------------------------------------------------------+
void TimeBasedExit()
{
   if(!UseTimeBasedExit)
      return;
   int total = PositionsTotal();
   datetime now = TimeCurrent();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         // POSITION_TIME returns the trade open time.
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         if((now - openTime) >= TradeMaxDurationMinutes * 60)
         {
            trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction                                               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      lastTradeTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Force-close positions if needed.
   ForceCloseTrades();
   // Apply time-based exit.
   TimeBasedExit();
   // Adjust SL dynamically for fast profit moves.
   DynamicSLAdjustment();
   // Apply profit lock mechanism if equity increased.
   ProfitLockMechanism();
   
   CountTrades();
   ManageHedging();
   ApplyTrailingStop();
   CheckAndTakePartialClose();
   
   if(TimeCurrent() - lastTradeTime < TradeFrequency)
      return;
      
   // Limit to one trade per day.
   MqlDateTime nowStruct;
   TimeToStruct(TimeCurrent(), nowStruct);
   if(nowStruct.day_of_year == lastTradeDay)
      return;
      
   // Check multi-timeframe conditions.
   ENUM_ORDER_TYPE marketSignal = DetermineMarketDirection();
   if(ReverseMode)
      marketSignal = (marketSignal == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      
   double m30_level = 0;
   if(!CheckM30TrendBreak(marketSignal, m30_level))
      return;
      
   if(!CheckM15LiquiditySweep(marketSignal, m30_level))
      return;
      
   // Check volatility breakout conditions if enabled.
   if(EnableVolatilityBreakout && volatilityTradeCount < MaxVolatilityTrades)
   {
      if(CheckBreakout(true))
      {
         if(ReverseBreakoutTrades)
            OpenTrade(ORDER_TYPE_SELL, "ATR Breakout (Reversed)");
         else
            OpenTrade(ORDER_TYPE_BUY, "ATR Breakout");
         return;
      }
      if(CheckBreakout(false))
      {
         if(ReverseBreakoutTrades)
            OpenTrade(ORDER_TYPE_BUY, "ATR Breakout (Reversed)");
         else
            OpenTrade(ORDER_TYPE_SELL, "ATR Breakout");
         return;
      }
   }
   
   if(normalTradeCount >= MaxTrades)
      return;
      
   OpenTrade(marketSignal, "Normal Trade");
}
