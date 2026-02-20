#property strict

#include <Trade/Trade.mqh>

input int InpTimerSeconds = 1;
input int InpDeviationPoints = 20;
input double InpMinSLPoints = 30;

CTrade trade;
long g_lastExternalCommandId = 0;

string Prefix()
{
   return StringFormat("RR.%I64d.", AccountInfoInteger(ACCOUNT_LOGIN));
}

bool GVRead(const string key, double &value)
{
   if(!GlobalVariableCheck(key))
      return false;
   value = GlobalVariableGet(key);
   return true;
}

string BaseKeyFromName(const string name)
{
   int pos = StringFind(name, ".entry");
   if(pos < 0)
      return "";
   return StringSubstr(name, 0, pos);
}

bool EnsureUnique(string &arr[], const string value)
{
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == value)
         return false;

   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = value;
   return true;
}

double RoundLots(const string symbol, double lots)
{
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0)
      step = 0.01;
   if(step < 0.01)
      step = 0.01;

   double rounded = MathFloor(lots / step) * step;
   rounded = MathMax(minLot, rounded);
   rounded = MathMin(maxLot, rounded);
   return rounded;
}

double CalcLotsByRisk(const string symbol, const double entry, const double sl, const double riskPct, const int riskBase)
{
   double baseMoney = 0.0;
   if(riskBase == 0)
      baseMoney = AccountInfoDouble(ACCOUNT_BALANCE);
   else if(riskBase == 1)
      baseMoney = AccountInfoDouble(ACCOUNT_EQUITY);
   else
      baseMoney = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   double riskMoney = baseMoney * riskPct / 100.0;
   double slDist = MathAbs(entry - sl);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(slDist <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double lossPerLot = (slDist / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   return RoundLots(symbol, riskMoney / lossPerLot);
}

bool MarginAllowed(const string symbol, const ENUM_ORDER_TYPE type, const double volume, const double price)
{
   double margin = 0.0;
   if(!OrderCalcMargin(type, symbol, volume, price, margin))
      return false;
   return margin <= AccountInfoDouble(ACCOUNT_MARGIN_FREE);
}

bool ExecuteBase(const string base, const bool requireExecRequest)
{
   double entry, sl, tp, side, riskPct, riskBase, armed, execReq;
   if(!GVRead(base + ".entry", entry)) return false;
   if(!GVRead(base + ".sl", sl)) return false;
   if(!GVRead(base + ".tp", tp)) return false;
   if(!GVRead(base + ".side", side)) return false;
   if(!GVRead(base + ".riskPct", riskPct)) return false;
   if(!GVRead(base + ".riskBase", riskBase)) return false;
   if(!GVRead(base + ".armed", armed)) return false;

   if(armed < 0.5)
      return false;

   if(requireExecRequest)
   {
      if(!GVRead(base + ".execReq", execReq))
         return false;
      if(execReq < 0.5)
         return false;
   }

   string parts[];
   int count = StringSplit(base, '.', parts);
   if(count < 5)
      return false;

   string symbol = parts[2];
   int sideInt = (side >= 0.0 ? 1 : -1);

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return false;

   double slPoints = MathAbs(entry - sl) / point;
   if(slPoints < InpMinSLPoints)
   {
      Print("Skip exec: SL too tight for ", base);
      return false;
   }

   double lots = CalcLotsByRisk(symbol, entry, sl, riskPct, (int)riskBase);
   if(lots <= 0.0)
   {
      Print("Skip exec: lots <= 0 for ", base);
      return false;
   }

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double price = sideInt > 0 ? ask : bid;

   ENUM_ORDER_TYPE orderType = sideInt > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!MarginAllowed(symbol, orderType, lots, price))
   {
      Print("Skip exec: margin not enough for ", base);
      return false;
   }

   trade.SetExpertMagicNumber(880051);
   trade.SetDeviationInPoints(InpDeviationPoints);

   bool ok = false;
   if(sideInt > 0)
      ok = trade.Buy(lots, symbol, 0.0, sl, tp, "RR exec");
   else
      ok = trade.Sell(lots, symbol, 0.0, sl, tp, "RR exec");

   if(!ok)
   {
      Print("Order failed for ", base, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
   }

   GlobalVariableSet(base + ".execReq", 0.0);
   GlobalVariableSet(base + ".armed", 0.0);
   GlobalVariableSet(base + ".executedAt", (double)TimeCurrent());
   Print("Executed: ", base, " lots=", DoubleToString(lots, 2));
   return true;
}

void CollectBases(string &bases[])
{
   ArrayResize(bases, 0);
   string prefix = Prefix();
   int total = GlobalVariablesTotal();
   for(int i = 0; i < total; i++)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) != 0)
         continue;
      string base = BaseKeyFromName(name);
      if(base == "")
         continue;
      EnsureUnique(bases, base);
   }
}

bool FindArmedBaseBySymbol(const string symbol, string &selectedBase)
{
   string bases[];
   CollectBases(bases);

   double bestUpdated = -1.0;
   selectedBase = "";

   for(int i = 0; i < ArraySize(bases); i++)
   {
      string parts[];
      if(StringSplit(bases[i], '.', parts) < 5)
         continue;
      if(parts[2] != symbol)
         continue;

      double armed = 0.0;
      if(!GVRead(bases[i] + ".armed", armed) || armed < 0.5)
         continue;

      double updated = 0.0;
      GVRead(bases[i] + ".updatedAt", updated);
      if(updated > bestUpdated)
      {
         bestUpdated = updated;
         selectedBase = bases[i];
      }
   }

   return selectedBase != "";
}

void AppendResult(const long commandId, const string symbol, const string status, const string message)
{
   int handle = FileOpen("RRExternalResults.csv", FILE_COMMON | FILE_CSV | FILE_READ | FILE_WRITE | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, commandId, symbol, status, message, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   FileClose(handle);
}

void ExportAvailableSetups()
{
   int handle = FileOpen("RRAvailableSetups.csv", FILE_COMMON | FILE_CSV | FILE_WRITE | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   FileWrite(handle, "base", "symbol", "armed", "updatedAt");

   string bases[];
   CollectBases(bases);
   for(int i = 0; i < ArraySize(bases); i++)
   {
      string parts[];
      if(StringSplit(bases[i], '.', parts) < 5)
         continue;

      double armed = 0.0, updatedAt = 0.0;
      GVRead(bases[i] + ".armed", armed);
      GVRead(bases[i] + ".updatedAt", updatedAt);
      FileWrite(handle, bases[i], parts[2], armed, updatedAt);
   }

   FileClose(handle);
}

void ProcessInternalRequests()
{
   string bases[];
   CollectBases(bases);
   for(int i = 0; i < ArraySize(bases); i++)
      ExecuteBase(bases[i], true);
}

void ProcessExternalCommands()
{
   int handle = FileOpen("RRExternalCommands.csv", FILE_COMMON | FILE_CSV | FILE_READ | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   while(!FileIsEnding(handle))
   {
      long commandId = (long)FileReadNumber(handle);
      string symbol = FileReadString(handle);
      string action = FileReadString(handle);
      if(commandId <= g_lastExternalCommandId)
         continue;

      g_lastExternalCommandId = commandId;

      if(action != "EXEC_MARKET")
      {
         AppendResult(commandId, symbol, "ERROR", "Unsupported action");
         continue;
      }

      string base;
      if(!FindArmedBaseBySymbol(symbol, base))
      {
         AppendResult(commandId, symbol, "ERROR", "RR setup not found or not ARMED on target symbol");
         continue;
      }

      if(ExecuteBase(base, false))
         AppendResult(commandId, symbol, "OK", "Order executed");
      else
         AppendResult(commandId, symbol, "ERROR", "Execution failed by safety checks or order reject");
   }

   FileClose(handle);
}

int OnInit()
{
   EventSetTimer(InpTimerSeconds);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   ProcessInternalRequests();
   ProcessExternalCommands();
   ExportAvailableSetups();
}
