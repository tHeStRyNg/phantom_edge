//+------------------------------------------------------------------+
//| Expert Advisor Name: Phantom Edge EA                           |
//| Version: 1.9 (Enhanced with Max Trade Count Check)               |
//| Author: Hamed Al Zakwani / Modified by [Your Name]                 |
//| Copyright © 2025 Hamed Al Zakwani                                |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
CTrade trade;

//--- Input parameters for flexibility
input double   Lots                      = 0.1;
input bool     UseIncrementalLots        = true;
input double   LotIncrement              = 0.2;
input int      MaxTrades                 = 1;        // Maximum number of normal trades allowed
input int      TradeFrequency            = 10;       // Minimum seconds between trades
input double   SLMultiplier              = 5.0;      // SL = ATR * SLMultiplier
input double   TP                        = 750;      // Take profit offset (price units) for normal trades (0 to disable)
input bool     PreventExceedingMaxTrades = true;
input bool     UseTrailingStop           = false;    // Enable trailing stop
input double   TrailingStopMultiplier    = 2.0;      // Trailing stop distance = ATR * multiplier

//--- New input for trailing TP
input bool     UseTrailingTP             = true;     // Enable trailing TP
//-------------------------------------------------
input bool     EnableHedging             = true;
input double   MaxDrawdownPercent        = 10.0;
input double   HedgeLotMultiplier        = 1.5;
input bool     EnableRecoveryMode        = true;
input bool     ReverseMode               = false;    // If enabled, invert trade signals
input bool     ReverseBreakoutTrades     = false;
input int      MaxVolatilityTrades       = 2;        // Maximum number of breakout trades allowed

//--- Indicator settings
input int      RSI_Period                = 14;
input int      MA_Period                 = 50;       // Period for the price SMA (used for trend detection)
input int      MACD_Fast                 = 12;
input int      MACD_Slow                 = 26;
input int      MACD_Signal               = 9;
input int      ATR_Period                = 14;

//--- Volatility Breakout Feature
input bool     EnableVolatilityBreakout  = false;
input double   ATR_Multiplier            = 2.0;      // Breakout if ATR > (average ATR * multiplier)
input int      SL_Points                 = 50;       // For breakout trades, fixed SL points
input int      TP_Points                 = 100;      // For breakout trades, fixed TP points
input int      Lookback_Candles          = 3;
input int      Slippage                  = 3;

//--- Partial Close Inputs (optional)
input bool     EnablePartialClose        = false;
input double   PartialCloseLotFraction   = 0.5;
input double   PartialCloseTriggerRatio  = 0.5;      // Partial close when profit reaches 50% of full target distance
input int      PartialRiskRewardRatio    = 3;

//--- Global variables
input string tradeSymbol = "BTCUSD";
datetime lastTradeTime = 0;
int normalTradeCount = 0;
int volatilityTradeCount = 0;
bool hedged = false;

//--- Global array to track tickets that have been partially closed already
ulong gPartialClosedTickets[];

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
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Create ATR indicator handle using ATR_Period
   atrHandle = iATR(tradeSymbol, PERIOD_M15, ATR_Period);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("Failed to initialize ATR indicator for ", tradeSymbol);
      return INIT_FAILED;
   }
   // Create SMA indicator handle for price using MA_Period (for trend detection)
   maHandle = iMA(tradeSymbol, PERIOD_M15, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE)
   {
      Print("Failed to initialize SMA indicator for ", tradeSymbol);
      return INIT_FAILED;
   }
   
   ArrayInitialize(gPartialClosedTickets, 0);
   Print("Phantom Edge EA Initialized for symbol ", tradeSymbol);
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
      Print("Failed to copy ATR data.");
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
      Print("Failed to copy SMA data.");
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
   // For hedging, open an opposite trade based on ReverseMode.
   ENUM_ORDER_TYPE hedgeType = (ReverseMode) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (hedgeType == ORDER_TYPE_BUY) ? SymbolInfoDouble(tradeSymbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(tradeSymbol, SYMBOL_BID);
   double stopLoss = 0, takeProfit = 0;
   double atrVal = GetATR();
   if(atrVal <= 0)
   {
      Print("Invalid ATR value for hedge trade. Order not sent.");
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
      Print("Hedge Trade Placed on ", tradeSymbol, " at price ", price);
   else
      Print("Hedge Trade failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Determine Market Direction Based on Price vs. SMA                |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE DetermineMarketDirection()
{
   double currentPrice = SymbolInfoDouble(tradeSymbol, SYMBOL_BID);
   double sma = GetSMA();
   // If current price is above the SMA, consider the market bullish (Buy signal)
   if(currentPrice > sma)
      return ORDER_TYPE_BUY;
   else
      return ORDER_TYPE_SELL;
}

//+------------------------------------------------------------------+
//| Check if current volatility qualifies as a breakout trade        |
//+------------------------------------------------------------------+
bool CheckBreakout(bool isBuy)
{
   double atr    = GetATR();
   double avgATR = GetSMA(); // Using SMA for a simple average reference
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
      Print("Invalid ATR value. Order not sent.");
      return;
   }
   
   // Determine trade type based on comment.
   if(StringFind(comment, "ATR Breakout") != -1)
   {
      // For breakout trades, use fixed points converted to price units.
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
      // For normal trades, set SL based on ATR and a fixed TP offset (if enabled).
      if(type == ORDER_TYPE_BUY)
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
   }
   
   // Validate stopLoss.
   if(stopLoss <= 0 || MathAbs(price - stopLoss) < _Point)
   {
      Print("Calculated stopLoss (", stopLoss, ") is invalid. Order not sent.");
      return;
   }
   
   bool res;
   if(type == ORDER_TYPE_BUY)
      res = trade.Buy(Lots, tradeSymbol, price, stopLoss, takeProfit, comment);
   else
      res = trade.Sell(Lots, tradeSymbol, price, stopLoss, takeProfit, comment);
   
   if(res)
   {
      lastTradeTime = TimeCurrent();
      Print(comment, " Trade opened on ", tradeSymbol, " at price ", price, 
            " with SL=", stopLoss, " TP=", takeProfit);
   }
   else
   {
      Print(comment, " Trade failed: ", trade.ResultRetcodeDescription());
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
         
         // Update SL if trailing is enabled.
         if(UseTrailingStop)
         {
            if(posType == POSITION_TYPE_BUY)
            {
               double newSL = price - trailingDistance;
               if(newSL > currentSL)
               {
                  currentSL = newSL;
                  modified = true;
                  Print("Trailing Stop updated (BUY): Ticket=", ticket, " New SL=", newSL);
               }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               double newSL = price + trailingDistance;
               if(currentSL == 0 || newSL < currentSL)
               {
                  currentSL = newSL;
                  modified = true;
                  Print("Trailing Stop updated (SELL): Ticket=", ticket, " New SL=", newSL);
               }
            }
         }
         
         // Update trailing TP if enabled.
         if(UseTrailingTP && currentTP != 0)
         {
            if(posType == POSITION_TYPE_BUY)
            {
               double newTP = price + trailingDistance;
               if(newTP > currentTP)
               {
                  currentTP = newTP;
                  modified = true;
                  Print("Trailing TP updated (BUY): Ticket=", ticket, " New TP=", newTP);
               }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               double newTP = price - trailingDistance;
               if(newTP < currentTP)
               {
                  currentTP = newTP;
                  modified = true;
                  Print("Trailing TP updated (SELL): Ticket=", ticket, " New TP=", newTP);
               }
            }
         }
         
         if(modified)
         {
            if(!trade.PositionModify(ticket, currentSL, currentTP))
               Print("Failed to modify trailing levels for Ticket=", ticket);
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
      
      // Skip if already partially closed.
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
                  Print("Partial Taken on Ticket=", ticket, " Volume closed=", closeVolume);
                  ArrayResize(gPartialClosedTickets, ArraySize(gPartialClosedTickets)+1);
                  gPartialClosedTickets[ArraySize(gPartialClosedTickets)-1] = ticket;
               }
               else
                  Print("Failed to execute partial close on Ticket=", ticket, ". Error: ", trade.ResultRetcodeDescription());
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
                  Print("Partial Taken on Ticket=", ticket, " Volume closed=", closeVolume);
                  ArrayResize(gPartialClosedTickets, ArraySize(gPartialClosedTickets)+1);
                  gPartialClosedTickets[ArraySize(gPartialClosedTickets)-1] = ticket;
               }
               else
                  Print("Failed to execute partial close on Ticket=", ticket, ". Error: ", trade.ResultRetcodeDescription());
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
      Print("Trade with ticket ", trans.order, " closed. EA will wait for new conditions.");
      lastTradeTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   CountTrades();
   ManageHedging();
   ApplyTrailingStop();
   CheckAndTakePartialClose();
   
   // Only consider new trades if the trade frequency condition is met.
   if(TimeCurrent() - lastTradeTime < TradeFrequency)
      return;
      
   // If breakout trades are enabled and within limit, handle them first.
   if(EnableVolatilityBreakout && volatilityTradeCount < MaxVolatilityTrades)
   {
      if(CheckBreakout(true))
      {
         if(ReverseBreakoutTrades)
            OpenTrade(ORDER_TYPE_SELL, "ATR Breakout (Reversed)");
         else
            OpenTrade(ORDER_TYPE_BUY, "ATR Breakout");
      }
      if(CheckBreakout(false))
      {
         if(ReverseBreakoutTrades)
            OpenTrade(ORDER_TYPE_BUY, "ATR Breakout (Reversed)");
         else
            OpenTrade(ORDER_TYPE_SELL, "ATR Breakout");
      }
      return;
   }
   
   // Only open a new normal trade if the maximum number of normal trades is not exceeded.
   if(normalTradeCount >= MaxTrades)
      return;
      
   // Determine the natural market direction based on price vs. SMA.
   ENUM_ORDER_TYPE marketSignal = DetermineMarketDirection();
   
   // Apply ReverseMode if enabled.
   if(ReverseMode)
      marketSignal = (marketSignal == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      
   // Open a normal trade based on the dynamic market signal.
   OpenTrade(marketSignal, "Normal Trade");
}
