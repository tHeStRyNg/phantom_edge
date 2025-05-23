//+------------------------------------------------------------------+
//| Expert Advisor Name: Phantom Edge EA                           |
//| Version: 1.9.2_debug (Enhanced with Debug Logs)                  |
//| Author: Hamed Al Zakwani / Modified by [Your Name]                |
//| Copyright © 2025 Hamed Al Zakwani                                |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
CTrade trade;

//--- Input parameters for flexibility
input double   Lots                      = 0.1;        // Fallback value if risk-based calc fails
input bool     UseIncrementalLots        = true;
input double   LotIncrement              = 0.2;
input int      MaxTrades                 = 1;          // Maximum number of normal trades allowed
input int      TradeFrequency            = 10;         // Minimum seconds between trades
input double   SLMultiplier              = 5.0;        // Used to define the SL distance (e.g. ATR multiplier)
input double   TP                        = 750;        // Take profit offset (price units) for normal trades (0 to disable)
input bool     PreventExceedingMaxTrades = true;
input bool     UseTrailingStop           = false;      // Enable trailing stop
input double   TrailingStopMultiplier    = 2.0;        // Trailing stop distance = ATR * multiplier

//--- New input for trailing TP
input bool     UseTrailingTP             = true;       // Enable trailing TP

//-------------------------------------------------
input bool     EnableHedging             = true;
input double   MaxDrawdownPercent        = 10.0;
input double   HedgeLotMultiplier        = 1.5;
input bool     EnableRecoveryMode        = true;
input bool     ReverseMode               = false;      // If enabled, invert trade signals
input bool     ReverseBreakoutTrades     = false;
input int      MaxVolatilityTrades       = 2;          // Maximum number of breakout trades allowed

//--- Indicator settings
input int      RSI_Period                = 14;
input int      MA_Period                 = 50;         // Period for the price SMA (used for trend detection)
input int      MACD_Fast                 = 12;
input int      MACD_Slow                 = 26;
input int      MACD_Signal               = 9;
input int      ATR_Period                = 14;
input int      ATR_Average_Period        = 14;

//--- Volatility Breakout Feature
input bool     EnableVolatilityBreakout  = false;
input double   ATR_Multiplier            = 2.0;        // Breakout if ATR > (average ATR * multiplier)
input int      SL_Points                 = 50;         // For breakout trades, fixed SL points
input int      TP_Points                 = 100;        // For breakout trades, fixed TP points
input int      Lookback_Candles          = 3;
input int      Slippage                  = 3;

//--- Partial Close Inputs (optional)
input bool     EnablePartialClose        = false;
input double   PartialCloseLotFraction   = 0.5;
input double   PartialCloseTriggerRatio  = 0.5;        // Partial close when profit reaches 50% of full target distance
input int      PartialRiskRewardRatio    = 3;

//--- New risk management input:
// RiskPercentage defines the % of the account balance to risk on each trade.
input double   RiskPercentage            = 1.0;        

//--- NEW: M30 Trend & M15 Liquidity Sweep Inputs
input int      M30_SwingLookback         = 3;          // Lookback period on M30 for swing high/low

//--- Global variables
input string tradeSymbol = "BTCUSD";
datetime lastTradeTime = 0;
int normalTradeCount = 0;
int volatilityTradeCount = 0;
bool hedged = false;

//--- Global array to track tickets that have been partially closed already
ulong gPartialClosedTickets[];

//--- To store the initial balance at the time the EA is started.
double initialBalance = 0;

//--- Indicator handles and buffers
int atrHandle = INVALID_HANDLE;
double atrBuffer[];
int maHandle = INVALID_HANDLE;
double maBuffer[];

//+------------------------------------------------------------------+
//| Helper function: Search an array of ulong for a given ticket       |
//| Returns the index if found, or -1 if not found.                    |
//+------------------------------------------------------------------+
int ArrayFindTicket(ulong &arr[], ulong ticket)
{
   for(int i = 0; i < ArraySize(arr); i++)
   {
      if(arr[i] == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Function: CalculateRiskBasedLotSize                              |
//| Description: Calculates the lot size based on the current account  |
//| balance, the user-defined risk percentage, and the stop-loss       |
//| distance (SLMultiplier * ATR).                                    |
//+------------------------------------------------------------------+
double CalculateRiskBasedLotSize(ENUM_ORDER_TYPE type, double entryPrice)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskDollars = accountBalance * (RiskPercentage / 100.0);
   
   double atrVal = GetATR();
   if(atrVal <= 0)
   {
      Print("DEBUG: Invalid ATR value for lot calculation. Using fallback Lots.");
      return Lots;
   }
   
   double stopLossDistance = SLMultiplier * atrVal;
   double tickValue = SymbolInfoDouble(tradeSymbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0)
   {
      Print("DEBUG: Invalid tick value for lot calculation. Using fallback Lots.");
      return Lots;
   }
   
   double stopLossPoints = stopLossDistance / _Point;
   double riskPerLot = stopLossPoints * tickValue;
   
   double calcLots = riskDollars / riskPerLot;
   double minLot = SymbolInfoDouble(tradeSymbol, SYMBOL_VOLUME_MIN);
   if(calcLots < minLot)
      calcLots = minLot;
      
   calcLots = NormalizeDouble(calcLots, 2);
   
   Print("DEBUG: Calculated lot size = ", calcLots,
         " (riskDollars=", riskDollars,
         ", stopLossDistance=", stopLossDistance,
         ", riskPerLot=", riskPerLot, ")");
   return calcLots;
}

//+------------------------------------------------------------------+
//| Function: CheckM30TrendBreak                                     |
//| Description: On the M30 timeframe, this function scans the last    |
//| 'M30_SwingLookback' candles to determine the swing high and swing  |
//| low. For a SELL reversal trade it now requires that the last closed |
//| candle's close is below the swing high (indicating a failure at      |
//| resistance), and for a BUY reversal trade the close must be above    |
//| the swing low. If the condition is met, it returns true and sets     |
//| 'm30_level' to the swing level.                                    |
//+------------------------------------------------------------------+
bool CheckM30TrendBreak(ENUM_ORDER_TYPE tradeSignal, double &m30_level)
{
   int lookback = M30_SwingLookback;
   double swingHigh = -DBL_MAX, swingLow = DBL_MAX;
   
   // Scan the last "lookback" fully closed M30 candles (indexes 1..lookback)
   for (int i = 1; i <= lookback; i++)
   {
      double high = iHigh(tradeSymbol, PERIOD_M30, i);
      double low  = iLow(tradeSymbol, PERIOD_M30, i);
      if(high > swingHigh) swingHigh = high;
      if(low < swingLow)   swingLow = low;
   }
   
   double lastClose = iClose(tradeSymbol, PERIOD_M30, 1);
   Print("DEBUG: M30 - swingHigh=", swingHigh, ", swingLow=", swingLow, ", lastClose=", lastClose);
   
   if(tradeSignal == ORDER_TYPE_SELL)
   {
      // For SELL reversal trades, require that the last M30 close is below the previous swing high.
      if(lastClose < swingHigh)
      {
         m30_level = swingHigh;  // use the swing high as the reference level (resistance)
         Print("DEBUG: M30 Trend Break confirmed for SELL (reversal) at level=", m30_level);
         return true;
      }
   }
   else if(tradeSignal == ORDER_TYPE_BUY)
   {
      // For BUY reversal trades, require that the last M30 close is above the previous swing low.
      if(lastClose > swingLow)
      {
         m30_level = swingLow;  // use the swing low as the reference level (support)
         Print("DEBUG: M30 Trend Break confirmed for BUY (reversal) at level=", m30_level);
         return true;
      }
   }
   Print("DEBUG: M30 Trend Break NOT confirmed.");
   return false;
}

//+------------------------------------------------------------------+
//| Function: CheckM15LiquiditySweep                                 |
//| Description: Checks if the last M15 candle has swept liquidity     |
//| around the M30 swing level.                                          |
//+------------------------------------------------------------------+
bool CheckM15LiquiditySweep(ENUM_ORDER_TYPE tradeSignal, double m30_level)
{
   double candleHigh  = iHigh(tradeSymbol, PERIOD_M15, 1);
   double candleLow   = iLow(tradeSymbol, PERIOD_M15, 1);
   double candleClose = iClose(tradeSymbol, PERIOD_M15, 1);
   Print("DEBUG: M15 - candleHigh=", candleHigh, ", candleLow=", candleLow, ", candleClose=", candleClose, ", m30_level=", m30_level);
   
   if(tradeSignal == ORDER_TYPE_SELL)
   {
      if(candleHigh > m30_level && candleClose < m30_level)
      {
         Print("DEBUG: M15 Liquidity Sweep confirmed for SELL.");
         return true;
      }
   }
   else if(tradeSignal == ORDER_TYPE_BUY)
   {
      if(candleLow < m30_level && candleClose > m30_level)
      {
         Print("DEBUG: M15 Liquidity Sweep confirmed for BUY.");
         return true;
      }
   }
   Print("DEBUG: M15 Liquidity Sweep NOT confirmed.");
   return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(tradeSymbol, PERIOD_M15, ATR_Period);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("DEBUG: Failed to initialize ATR indicator for ", tradeSymbol);
      return INIT_FAILED;
   }
   maHandle = iMA(tradeSymbol, PERIOD_M15, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE)
   {
      Print("DEBUG: Failed to initialize SMA indicator for ", tradeSymbol);
      return INIT_FAILED;
   }
   
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("DEBUG: Initial Balance = ", initialBalance);
   
   ArrayInitialize(gPartialClosedTickets, 0);
   Print("DEBUG: Phantom Edge EA Initialized for symbol ", tradeSymbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
   if(maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
}

//+------------------------------------------------------------------+
//| Get current ATR value                                            |
//+------------------------------------------------------------------+
double GetATR()
{
   double atrVal = 0;
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
      atrVal = atrBuffer[0];
   else
      Print("DEBUG: Failed to copy ATR data.");
   return atrVal;
}

//+------------------------------------------------------------------+
//| Get current SMA (price moving average) value                     |
//+------------------------------------------------------------------+
double GetSMA()
{
   double smaVal = 0;
   if(CopyBuffer(maHandle, 0, 0, 1, maBuffer) > 0)
      smaVal = maBuffer[0];
   else
      Print("DEBUG: Failed to copy SMA data.");
   return smaVal;
}

//+------------------------------------------------------------------+
//| Count currently open trades                                      |
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
   Print("DEBUG: Trade counts - Normal:", normalTradeCount, ", Volatility:", volatilityTradeCount);
}

//+------------------------------------------------------------------+
//| Manage Hedging based on Drawdown                                 |
//+------------------------------------------------------------------+
void ManageHedging()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = ((balance - equity) / balance) * 100;
   
   if(drawdown >= MaxDrawdownPercent && !hedged && EnableHedging)
   {
      Print("DEBUG: Drawdown triggered hedging. Drawdown=", drawdown);
      OpenHedgeTrade();
      hedged = true;
   }
   else if(drawdown < MaxDrawdownPercent * 0.5)
   {
      hedged = false;
   }
}

//+------------------------------------------------------------------+
//| Open Hedge Trade                                                 |
//+------------------------------------------------------------------+
void OpenHedgeTrade()
{
   ENUM_ORDER_TYPE hedgeType = (ReverseMode) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (hedgeType == ORDER_TYPE_BUY) ? SymbolInfoDouble(tradeSymbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(tradeSymbol, SYMBOL_BID);
   double stopLoss = 0, takeProfit = 0;
   double atrVal = GetATR();
   if(atrVal <= 0)
   {
      Print("DEBUG: Invalid ATR for hedge trade.");
      return;
   }
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
   bool res;
   if(hedgeType == ORDER_TYPE_BUY)
      res = trade.Buy(Lots * HedgeLotMultiplier, tradeSymbol, price, stopLoss, takeProfit, "Hedge Trade");
   else
      res = trade.Sell(Lots * HedgeLotMultiplier, tradeSymbol, price, stopLoss, takeProfit, "Hedge Trade");

   if(res)
      Print("DEBUG: Hedge Trade placed at price ", price);
   else
      Print("DEBUG: Hedge Trade failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Determine Market Direction Based on Price vs. SMA                |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE DetermineMarketDirection()
{
   double currentPrice = SymbolInfoDouble(tradeSymbol, SYMBOL_BID);
   double sma = GetSMA();
   Print("DEBUG: Current Price=", currentPrice, ", SMA=", sma);
   if(currentPrice > sma)
      return ORDER_TYPE_BUY;
   else
      return ORDER_TYPE_SELL;
}

//+------------------------------------------------------------------+
//| Calculate the average ATR over a given period                    |
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
//| Check if current volatility qualifies as a breakout trade        |
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
//| Open a Trade (normal or breakout)                                |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, string comment)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(tradeSymbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(tradeSymbol, SYMBOL_BID);
   double stopLoss = 0, takeProfit = 0;
   double atrVal = GetATR();
   if(atrVal <= 0)
   {
      Print("DEBUG: Invalid ATR value. Order not sent.");
      return;
   }
   
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
      // Normal trade: calculate risk-based lot size.
      double riskBasedLots = CalculateRiskBasedLotSize(type, price);
      double riskPriceDistance = SLMultiplier * atrVal;
      if(type == ORDER_TYPE_BUY)
         stopLoss = price - riskPriceDistance;
      else
         stopLoss = price + riskPriceDistance;
      
      if(TP > 0)
      {
         if(type == ORDER_TYPE_BUY)
            takeProfit = price + TP;
         else
            takeProfit = price - TP;
      }
      
      Print("DEBUG: Using calculated lot size: ", riskBasedLots);
      
      if(type == ORDER_TYPE_BUY)
      {
         if(trade.Buy(riskBasedLots, tradeSymbol, price, stopLoss, takeProfit, comment))
         {
            lastTradeTime = TimeCurrent();
            Print("DEBUG: ", comment, " Trade opened on ", tradeSymbol, " at price ", price,
                  " with SL=", stopLoss, " TP=", takeProfit, " and lots=", riskBasedLots);
         }
         else
         {
            Print("DEBUG: ", comment, " Trade failed: ", trade.ResultRetcodeDescription());
         }
         return;
      }
      else
      {
         if(trade.Sell(riskBasedLots, tradeSymbol, price, stopLoss, takeProfit, comment))
         {
            lastTradeTime = TimeCurrent();
            Print("DEBUG: ", comment, " Trade opened on ", tradeSymbol, " at price ", price,
                  " with SL=", stopLoss, " TP=", takeProfit, " and lots=", riskBasedLots);
         }
         else
         {
            Print("DEBUG: ", comment, " Trade failed: ", trade.ResultRetcodeDescription());
         }
         return;
      }
   }
   
   // For breakout trades fallback:
   bool res;
   if(type == ORDER_TYPE_BUY)
      res = trade.Buy(Lots, tradeSymbol, price, stopLoss, takeProfit, comment);
   else
      res = trade.Sell(Lots, tradeSymbol, price, stopLoss, takeProfit, comment);
   
   if(res)
   {
      lastTradeTime = TimeCurrent();
      Print("DEBUG: ", comment, " Trade opened on ", tradeSymbol, " at price ", price,
            " with SL=", stopLoss, " TP=", takeProfit, " and lots=", Lots);
   }
   else
   {
      Print("DEBUG: ", comment, " Trade failed: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Apply Trailing Stop (and optionally trailing TP)                 |
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
         bool modified = false;
         
         if(UseTrailingStop)
         {
            if(posType == POSITION_TYPE_BUY)
            {
               double newSL = price - trailingDistance;
               if(newSL > currentSL)
               {
                  currentSL = newSL;
                  modified = true;
                  Print("DEBUG: Trailing Stop updated (BUY): Ticket=", ticket, " New SL=", newSL);
               }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               double newSL = price + trailingDistance;
               if(currentSL == 0 || newSL < currentSL)
               {
                  currentSL = newSL;
                  modified = true;
                  Print("DEBUG: Trailing Stop updated (SELL): Ticket=", ticket, " New SL=", newSL);
               }
            }
         }
         
         if(UseTrailingTP && currentTP != 0)
         {
            if(posType == POSITION_TYPE_BUY)
            {
               double newTP = price + trailingDistance;
               if(newTP > currentTP)
               {
                  currentTP = newTP;
                  modified = true;
                  Print("DEBUG: Trailing TP updated (BUY): Ticket=", ticket, " New TP=", newTP);
               }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               double newTP = price - trailingDistance;
               if(newTP < currentTP)
               {
                  currentTP = newTP;
                  modified = true;
                  Print("DEBUG: Trailing TP updated (SELL): Ticket=", ticket, " New TP=", newTP);
               }
            }
         }
         
         if(modified)
         {
            if(!trade.PositionModify(ticket, currentSL, currentTP))
               Print("DEBUG: Failed to modify trailing levels for Ticket=", ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check and perform Partial Close on open positions                |
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
               if(closeVolume < SymbolInfoDouble(tradeSymbol, SYMBOL_VOLUME_MIN))
                  continue;
               if(trade.PositionClosePartial(ticket, closeVolume))
               {
                  Print("DEBUG: Partial close executed on Ticket=", ticket, " Volume closed=", closeVolume);
                  ArrayResize(gPartialClosedTickets, ArraySize(gPartialClosedTickets)+1);
                  gPartialClosedTickets[ArraySize(gPartialClosedTickets)-1] = ticket;
               }
               else
                  Print("DEBUG: Partial close failed on Ticket=", ticket, ". Error: ", trade.ResultRetcodeDescription());
            }
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            triggerPrice = entryPrice - fullTPDistance * PartialCloseTriggerRatio;
            double currentPrice = SymbolInfoDouble(tradeSymbol, SYMBOL_ASK);
            if(currentPrice <= triggerPrice)
            {
               double closeVolume = volume * PartialCloseLotFraction;
               if(closeVolume < SymbolInfoDouble(tradeSymbol, SYMBOL_VOLUME_MIN))
                  continue;
               if(trade.PositionClosePartial(ticket, closeVolume))
               {
                  Print("DEBUG: Partial close executed on Ticket=", ticket, " Volume closed=", closeVolume);
                  ArrayResize(gPartialClosedTickets, ArraySize(gPartialClosedTickets)+1);
                  gPartialClosedTickets[ArraySize(gPartialClosedTickets)-1] = ticket;
               }
               else
                  Print("DEBUG: Partial close failed on Ticket=", ticket, ". Error: ", trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction: Detect trade closures                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      Print("DEBUG: Trade with ticket ", trans.order, " closed. EA waiting for new conditions.");
      lastTradeTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   Print("DEBUG: OnTick executed at ", TimeToString(TimeCurrent(), TIME_SECONDS));
   CountTrades();
   ManageHedging();
   ApplyTrailingStop();
   CheckAndTakePartialClose();
   
   if(TimeCurrent() - lastTradeTime < TradeFrequency)
   {
      Print("DEBUG: TradeFrequency not reached. Time since last trade: ", TimeCurrent() - lastTradeTime);
      return;
   }
      
   // Check M30 and M15 conditions.
   ENUM_ORDER_TYPE marketSignal = DetermineMarketDirection();
   Print("DEBUG: Market signal determined as ", EnumToString(marketSignal));
   
   if(ReverseMode)
      marketSignal = (marketSignal == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      
   double m30_level = 0;
   if(!CheckM30TrendBreak(marketSignal, m30_level))
   {
      Print("DEBUG: M30 trend condition not met. No trade.");
      return;
   }
      
   if(!CheckM15LiquiditySweep(marketSignal, m30_level))
   {
      Print("DEBUG: M15 liquidity sweep condition not met. No trade.");
      return;
   }
      
   // Check for volatility breakout trades if enabled.
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
   {
      Print("DEBUG: Maximum normal trade count reached: ", normalTradeCount);
      return;
   }
      
   OpenTrade(marketSignal, "Normal Trade");
}
