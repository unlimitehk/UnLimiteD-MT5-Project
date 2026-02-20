#property strict
#property indicator_chart_window
#property indicator_plots 0

input double InpRiskPercent = 1.0;
input int    InpDefaultSLPoints = 300;
input double InpDefaultRR = 2.0;
input bool   InpLockRR = true;
input int    InpVisualBarsWidth = 40;
input color  InpEntryColor = clrDodgerBlue;
input color  InpSLColor = clrTomato;
input color  InpTPColor = clrLimeGreen;
input int    InpPanelX = 8;
input int    InpPanelY = 8;
input int    InpSnapSearchBars = 8;
input bool   InpUseExternalPanel = true;
input bool   InpSyncLinesEnabled = false;

enum ENUM_RISK_BASE
{
   RISK_BALANCE = 0,
   RISK_EQUITY = 1,
   RISK_FREE_MARGIN = 2
};
input ENUM_RISK_BASE InpRiskBase = RISK_EQUITY;

string   g_setupId = "";
int      g_side = 1;
bool     g_armed = false;
int      g_pendingSide = 0;
bool     g_skipNextChartClick = false;
datetime g_anchorTime = 0;

enum ENUM_PENDING_TOOL
{
   TOOL_NONE = 0,
   TOOL_EW_12345 = 1,
   TOOL_EW_ABC = 2,
   TOOL_EW_ABCDE = 3,
   TOOL_EW_WXY = 4,
   TOOL_EW_WXYXZ = 5
};

int g_pendingTool = TOOL_NONE;
int g_waveTargetPoints = 0;
int g_wavePointCount = 0;
string g_wavePrefix = "";
string g_waveLabels[6];
datetime g_waveTimes[6];
double g_wavePrices[6];
bool g_waveIsHigh[6];

bool   g_syncEnabled = false;
double g_lastSyncUpdatedAt = 0.0;

string Prefix() { return "RR_" + g_setupId + "_"; }
string ObjEntry() { return Prefix() + "ENTRY"; }
string ObjSL() { return Prefix() + "SL"; }
string ObjTP() { return Prefix() + "TP"; }
string ObjRiskRect() { return Prefix() + "RISKRECT"; }
string ObjRewardRect() { return Prefix() + "REWARDRECT"; }
string ObjLabel() { return Prefix() + "LABEL"; }
string ObjWidthHandle() { return Prefix() + "WIDTH"; }
string ObjDeleteBtn() { return Prefix() + "DELBTN"; }

string KeyBase()
{
   return StringFormat("RR.%I64d.%s.%I64d.%s", AccountInfoInteger(ACCOUNT_LOGIN), _Symbol, ChartID(), g_setupId);
}

string Key(const string suffix) { return KeyBase() + "." + suffix; }


string SyncKeyBase()
{
   return StringFormat("RR.SYNC.%I64d.%s", AccountInfoInteger(ACCOUNT_LOGIN), _Symbol);
}

string SyncKey(const string suffix)
{
   return SyncKeyBase() + "." + suffix;
}

void UpdateSyncButtonLabel()
{
   if(ObjectFind(0, "RR_BTN_SYNC") < 0)
      return;
   ObjectSetString(0, "RR_BTN_SYNC", OBJPROP_TEXT, g_syncEnabled ? "ライン同期: ON" : "ライン同期: OFF");
}

void PublishSyncValues(const double entry, const double sl, const double tp)
{
   if(!g_syncEnabled)
      return;

   GlobalVariableSet(SyncKey("entry"), entry);
   GlobalVariableSet(SyncKey("sl"), sl);
   GlobalVariableSet(SyncKey("tp"), tp);
   GlobalVariableSet(SyncKey("side"), g_side);
   GlobalVariableSet(SyncKey("clear"), 0.0);
   GlobalVariableSet(SyncKey("updatedAt"), (double)TimeCurrent());
}

void PublishSyncClear()
{
   if(!g_syncEnabled)
      return;
   GlobalVariableSet(SyncKey("clear"), 1.0);
   GlobalVariableSet(SyncKey("updatedAt"), (double)TimeCurrent());
}

void EnsureSetupFromPrices(const int side, const double entry, const double sl, const double tp)
{
   if(g_setupId == "")
   {
      g_setupId = IntegerToString((int)TimeCurrent());
      g_side = side;
      g_armed = false;

      datetime anchor = TimeCurrent();
      datetime t1 = ShiftBarTime(anchor, InpVisualBarsWidth);
      datetime t2 = ShiftBarTime(anchor, -MathMax(4, InpVisualBarsWidth / 5));
      if(t2 <= t1)
         t2 = anchor + (datetime)(PeriodSeconds() * MathMax(4, InpVisualBarsWidth / 5));

      EnsurePriceLine(ObjEntry(), t1, entry, t2, InpEntryColor, 2);
      EnsurePriceLine(ObjSL(), t1, sl, t2, InpSLColor, 2);
      EnsurePriceLine(ObjTP(), t1, tp, t2, InpTPColor, 2);
   }
   else
   {
      g_side = side;
      ObjectSetDouble(0, ObjEntry(), OBJPROP_PRICE, 0, entry);
      ObjectSetDouble(0, ObjEntry(), OBJPROP_PRICE, 1, entry);
      ObjectSetDouble(0, ObjSL(), OBJPROP_PRICE, 0, sl);
      ObjectSetDouble(0, ObjSL(), OBJPROP_PRICE, 1, sl);
      ObjectSetDouble(0, ObjTP(), OBJPROP_PRICE, 0, tp);
      ObjectSetDouble(0, ObjTP(), OBJPROP_PRICE, 1, tp);
   }

   SyncVisuals();
   UpdateLabel();
}

void ApplySyncedSetupIfNeeded()
{
   if(!g_syncEnabled)
      return;

   string updatedKey = SyncKey("updatedAt");
   if(!GlobalVariableCheck(updatedKey))
      return;

   double updatedAt = GlobalVariableGet(updatedKey);
   if(updatedAt <= g_lastSyncUpdatedAt)
      return;

   double clear = GlobalVariableCheck(SyncKey("clear")) ? GlobalVariableGet(SyncKey("clear")) : 0.0;
   if(clear > 0.5)
   {
      DeleteSetup();
      g_lastSyncUpdatedAt = updatedAt;
      return;
   }

   if(!GlobalVariableCheck(SyncKey("entry")) || !GlobalVariableCheck(SyncKey("sl")) || !GlobalVariableCheck(SyncKey("tp")) || !GlobalVariableCheck(SyncKey("side")))
      return;

   double entry = GlobalVariableGet(SyncKey("entry"));
   double sl = GlobalVariableGet(SyncKey("sl"));
   double tp = GlobalVariableGet(SyncKey("tp"));
   int side = (int)GlobalVariableGet(SyncKey("side"));

   EnsureSetupFromPrices(side, entry, sl, tp);
   g_lastSyncUpdatedAt = updatedAt;
}

void DeleteSetup();
void CancelWaveDrawing(const bool removeObjects = true);
void RefreshWaveBackButton();
void ApplySyncedSetupIfNeeded();

bool ReadLinePrice(const string obj, double &value)
{
   if(ObjectFind(0, obj) < 0)
      return false;

   value = ObjectGetDouble(0, obj, OBJPROP_PRICE, 0);
   return true;
}

void Publish(bool execReq = false)
{
   if(g_setupId == "")
      return;

   double entry, sl, tp;
   if(!ReadLinePrice(ObjEntry(), entry) || !ReadLinePrice(ObjSL(), sl) || !ReadLinePrice(ObjTP(), tp))
      return;

   GlobalVariableSet(Key("entry"), entry);
   GlobalVariableSet(Key("sl"), sl);
   GlobalVariableSet(Key("tp"), tp);
   GlobalVariableSet(Key("side"), g_side);
   GlobalVariableSet(Key("riskPct"), InpRiskPercent);
   GlobalVariableSet(Key("riskBase"), (double)InpRiskBase);
   GlobalVariableSet(Key("armed"), g_armed ? 1.0 : 0.0);
   GlobalVariableSet(Key("execReq"), execReq ? 1.0 : 0.0);
   GlobalVariableSet(Key("updatedAt"), (double)TimeCurrent());

   PublishSyncValues(entry, sl, tp);
}

double CalcLots(const double entry, const double sl)
{
   double baseMoney = 0.0;
   if(InpRiskBase == RISK_BALANCE)
      baseMoney = AccountInfoDouble(ACCOUNT_BALANCE);
   else if(InpRiskBase == RISK_EQUITY)
      baseMoney = AccountInfoDouble(ACCOUNT_EQUITY);
   else
      baseMoney = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   double riskMoney = baseMoney * InpRiskPercent / 100.0;
   double slDist = MathAbs(entry - sl);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(slDist <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double lossPerLot = (slDist / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   double lotsRaw = riskMoney / lossPerLot;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = 0.01;
   if(step < 0.01)
      step = 0.01;

   double lots = MathFloor(lotsRaw / step) * step;
   lots = MathMax(minLot, lots);
   lots = MathMin(maxLot, lots);
   return lots;
}

void EnsurePriceLine(const string name,
                     const datetime t1,
                     const double p,
                     const datetime t2,
                     const color clr,
                     const int width)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p, t2, p);

   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);

   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p);
}

void EnsureRect(const string name,
                const datetime t1,
                const datetime t2,
                const double p1,
                const double p2,
                const color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);

   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);

   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
}

void EnsureWidthHandle(const datetime t2, const double entry, const double sl, const double tp)
{
   double hi = MathMax(entry, MathMax(sl, tp));
   double lo = MathMin(entry, MathMin(sl, tp));
   if(ObjectFind(0, ObjWidthHandle()) < 0)
      ObjectCreate(0, ObjWidthHandle(), OBJ_TREND, 0, t2, hi, t2, lo);

   ObjectSetInteger(0, ObjWidthHandle(), OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, ObjWidthHandle(), OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, ObjWidthHandle(), OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, ObjWidthHandle(), OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, ObjWidthHandle(), OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, ObjWidthHandle(), OBJPROP_RAY_RIGHT, false);

   ObjectSetInteger(0, ObjWidthHandle(), OBJPROP_TIME, 0, t2);
   ObjectSetDouble(0, ObjWidthHandle(), OBJPROP_PRICE, 0, hi);
   ObjectSetInteger(0, ObjWidthHandle(), OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, ObjWidthHandle(), OBJPROP_PRICE, 1, lo);
}

void EnsureDeleteButton()
{
   if(InpUseExternalPanel || g_setupId == "")
      return;

   if(ObjectFind(0, ObjDeleteBtn()) < 0)
      ObjectCreate(0, ObjDeleteBtn(), OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, ObjDeleteBtn(), OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, ObjDeleteBtn(), OBJPROP_XDISTANCE, InpPanelX + 196);
   ObjectSetInteger(0, ObjDeleteBtn(), OBJPROP_YDISTANCE, InpPanelY + 82);
   ObjectSetInteger(0, ObjDeleteBtn(), OBJPROP_XSIZE, 92);
   ObjectSetInteger(0, ObjDeleteBtn(), OBJPROP_YSIZE, 22);
   ObjectSetString(0, ObjDeleteBtn(), OBJPROP_TEXT, "RR削除");
}

void SyncVisuals()
{
   if(g_setupId == "")
      return;

   double entry, sl, tp;
   if(!ReadLinePrice(ObjEntry(), entry) || !ReadLinePrice(ObjSL(), sl) || !ReadLinePrice(ObjTP(), tp))
      return;

   datetime t1 = (datetime)ObjectGetInteger(0, ObjEntry(), OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, ObjEntry(), OBJPROP_TIME, 1);

   EnsurePriceLine(ObjEntry(), t1, entry, t2, InpEntryColor, 2);
   EnsurePriceLine(ObjSL(), t1, sl, t2, InpSLColor, 2);
   EnsurePriceLine(ObjTP(), t1, tp, t2, InpTPColor, 2);

   EnsureRect(ObjRiskRect(), t1, t2, entry, sl, clrTomato);
   EnsureRect(ObjRewardRect(), t1, t2, entry, tp, clrSeaGreen);
   EnsureWidthHandle(t2, entry, sl, tp);
   EnsureDeleteButton();
}

void UpdateLabel()
{
   if(g_setupId == "")
      return;

   double entry, sl, tp;
   if(!ReadLinePrice(ObjEntry(), entry) || !ReadLinePrice(ObjSL(), sl) || !ReadLinePrice(ObjTP(), tp))
      return;

   double risk = MathAbs(entry - sl);
   double reward = MathAbs(tp - entry);
   double rr = (risk > 0.0) ? (reward / risk) : 0.0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double points = (point > 0.0) ? (risk / point) : 0.0;
   double lots = CalcLots(entry, sl);

   string txt = StringFormat("ID:%s | %s | RR: %.2f | Risk: %.1f pt | Lots: %.2f | Armed:%s",
                             g_setupId,
                             (g_side > 0 ? "LONG" : "SHORT"),
                             rr,
                             points,
                             lots,
                             (g_armed ? "ON" : "OFF"));

   if(ObjectFind(0, ObjLabel()) < 0)
      ObjectCreate(0, ObjLabel(), OBJ_TEXT, 0, TimeCurrent(), entry);

   datetime labelTime = (datetime)ObjectGetInteger(0, ObjEntry(), OBJPROP_TIME, 1);
   ObjectSetInteger(0, ObjLabel(), OBJPROP_TIME, 0, labelTime);
   ObjectSetDouble(0, ObjLabel(), OBJPROP_PRICE, 0, entry);
   ObjectSetInteger(0, ObjLabel(), OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, ObjLabel(), OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetString(0, ObjLabel(), OBJPROP_TEXT, txt);
}

void CreateToolNote(const string name, const string text, const int y)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX + 8);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrSilver);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void SetButtons()
{
   if(ObjectFind(0, "RR_PANEL_BG") < 0)
      ObjectCreate(0, "RR_PANEL_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_XSIZE, 292);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_YSIZE, 356);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_BGCOLOR, C'20,22,30');
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_COLOR, C'60,65,90');
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);

   CreateToolNote("RR_TITLE", "⚡ UnLimiteD 操作パネル", 14);
   ObjectSetInteger(0, "RR_TITLE", OBJPROP_COLOR, clrWhite);

   CreateToolNote("RR_SEC_RR", "【RRセクション】", 36);
   ObjectSetInteger(0, "RR_SEC_RR", OBJPROP_COLOR, clrAqua);

   string rrNames[6] = {"RR_BTN_LONG", "RR_BTN_SHORT", "RR_BTN_ARM", "RR_BTN_EXEC", "RR_BTN_CANCEL", "RR_BTN_SYNC"};
   string rrTexts[6] = {"ロングポジションRR +LONG", "ショートポジションRR +SHORT", "ARM", "EXEC", "CANCEL", "ライン同期: OFF"};
   int rrX[6] = {16, 16, 16, 106, 196, 16};
   int rrY[6] = {56, 82, 108, 108, 108, 134};
   int rrW[6] = {272, 272, 82, 82, 82, 272};

   for(int i = 0; i < 6; i++)
   {
      if(ObjectFind(0, rrNames[i]) < 0)
         ObjectCreate(0, rrNames[i], OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, rrNames[i], OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, rrNames[i], OBJPROP_XDISTANCE, InpPanelX + rrX[i] - 8);
      ObjectSetInteger(0, rrNames[i], OBJPROP_YDISTANCE, InpPanelY + rrY[i] - 8);
      ObjectSetInteger(0, rrNames[i], OBJPROP_XSIZE, rrW[i]);
      ObjectSetInteger(0, rrNames[i], OBJPROP_YSIZE, 22);
      ObjectSetString(0, rrNames[i], OBJPROP_TEXT, rrTexts[i]);
      ObjectSetInteger(0, rrNames[i], OBJPROP_BGCOLOR, C'35,40,60');
      ObjectSetInteger(0, rrNames[i], OBJPROP_COLOR, clrWhite);
   }

   CreateToolNote("RR_SEC_EW", "【エリオットセクション】", 138);
   ObjectSetInteger(0, "RR_SEC_EW", OBJPROP_COLOR, clrGold);

   string ewNames[5] = {"RR_BTN_EW_12345", "RR_BTN_EW_ABC", "RR_BTN_EW_ABCDE", "RR_BTN_EW_WXY", "RR_BTN_EW_WXYXZ"};
   string ewTexts[5] = {"エリオット波動推進波（12345）", "エリオット波動調整波（ABC）", "エリオット波動トライアングル（ABCDE）", "エリオット波動ダブルコンボ（WXY）", "エリオット波動トリプルコンボ（WXYXZ）"};

   for(int j = 0; j < 5; j++)
   {
      if(ObjectFind(0, ewNames[j]) < 0)
         ObjectCreate(0, ewNames[j], OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, ewNames[j], OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, ewNames[j], OBJPROP_XDISTANCE, InpPanelX + 8);
      ObjectSetInteger(0, ewNames[j], OBJPROP_YDISTANCE, InpPanelY + 150 + j * 24);
      ObjectSetInteger(0, ewNames[j], OBJPROP_XSIZE, 272);
      ObjectSetInteger(0, ewNames[j], OBJPROP_YSIZE, 22);
      ObjectSetString(0, ewNames[j], OBJPROP_TEXT, ewTexts[j]);
      ObjectSetInteger(0, ewNames[j], OBJPROP_BGCOLOR, C'50,42,22');
      ObjectSetInteger(0, ewNames[j], OBJPROP_COLOR, clrWhite);
   }

   if(ObjectFind(0, "RR_BTN_CLEAR_ALL") < 0)
      ObjectCreate(0, "RR_BTN_CLEAR_ALL", OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, "RR_BTN_CLEAR_ALL", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "RR_BTN_CLEAR_ALL", OBJPROP_XDISTANCE, InpPanelX + 8);
   ObjectSetInteger(0, "RR_BTN_CLEAR_ALL", OBJPROP_YDISTANCE, InpPanelY + 324);
   ObjectSetInteger(0, "RR_BTN_CLEAR_ALL", OBJPROP_XSIZE, 272);
   ObjectSetInteger(0, "RR_BTN_CLEAR_ALL", OBJPROP_YSIZE, 22);
   ObjectSetString(0, "RR_BTN_CLEAR_ALL", OBJPROP_TEXT, "全描画削除");
   ObjectSetInteger(0, "RR_BTN_CLEAR_ALL", OBJPROP_BGCOLOR, C'85,20,20');
   ObjectSetInteger(0, "RR_BTN_CLEAR_ALL", OBJPROP_COLOR, clrWhite);

   UpdateSyncButtonLabel();
}

datetime ShiftBarTime(const datetime anchor, const int barsShift)
{
   int idx = iBarShift(_Symbol, _Period, anchor, false);
   if(idx < 0)
      return anchor;

   int shifted = idx - barsShift;
   if(shifted < 0)
      shifted = 0;

   datetime t = iTime(_Symbol, _Period, shifted);
   return (t > 0 ? t : anchor);
}

void CreateSetupAt(const int side, const datetime anchorTime, const double anchorPrice)
{
   DeleteSetup();

   g_setupId = IntegerToString((int)TimeCurrent());
   g_side = side;
   g_armed = false;
   g_anchorTime = anchorTime;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double entry = anchorPrice;
   double sl = entry + (side > 0 ? -1 : 1) * InpDefaultSLPoints * point;
   double tp = entry + (side > 0 ? 1 : -1) * (InpDefaultSLPoints * InpDefaultRR) * point;

   datetime t1 = ShiftBarTime(anchorTime, InpVisualBarsWidth);
   datetime t2 = ShiftBarTime(anchorTime, -MathMax(4, InpVisualBarsWidth / 5));
   if(t2 <= t1)
      t2 = anchorTime + (datetime)(PeriodSeconds() * MathMax(4, InpVisualBarsWidth / 5));

   EnsurePriceLine(ObjEntry(), t1, entry, t2, InpEntryColor, 2);
   EnsurePriceLine(ObjSL(), t1, sl, t2, InpSLColor, 2);
   EnsurePriceLine(ObjTP(), t1, tp, t2, InpTPColor, 2);

   SyncVisuals();
   UpdateLabel();
   Publish(false);
}

void DeleteSetup()
{
   if(g_setupId == "")
      return;

   PublishSyncClear();

   ObjectDelete(0, ObjEntry());
   ObjectDelete(0, ObjSL());
   ObjectDelete(0, ObjTP());
   ObjectDelete(0, ObjRiskRect());
   ObjectDelete(0, ObjRewardRect());
   ObjectDelete(0, ObjLabel());
   ObjectDelete(0, ObjWidthHandle());
   ObjectDelete(0, ObjDeleteBtn());

   GlobalVariableDel(Key("entry"));
   GlobalVariableDel(Key("sl"));
   GlobalVariableDel(Key("tp"));
   GlobalVariableDel(Key("side"));
   GlobalVariableDel(Key("riskPct"));
   GlobalVariableDel(Key("riskBase"));
   GlobalVariableDel(Key("armed"));
   GlobalVariableDel(Key("execReq"));
   GlobalVariableDel(Key("updatedAt"));

   g_setupId = "";
   g_armed = false;
}


int WavePointTarget(const int pattern)
{
   if(pattern == TOOL_EW_ABC || pattern == TOOL_EW_WXY)
      return 4; // 始点 + 3点
   return 6;    // 始点 + 5点
}

color WaveColor(const int pattern)
{
   if(pattern == TOOL_EW_12345) return clrOrange;
   if(pattern == TOOL_EW_ABC) return clrViolet;
   if(pattern == TOOL_EW_ABCDE) return clrGold;
   if(pattern == TOOL_EW_WXY) return clrDeepSkyBlue;
   return clrPaleGreen;
}

void SetupWaveLabels(const int pattern)
{
   for(int i = 0; i < 6; i++)
      g_waveLabels[i] = "";

   g_waveLabels[0] = "始点";

   if(pattern == TOOL_EW_12345)
   {
      g_waveLabels[1] = "1"; g_waveLabels[2] = "2"; g_waveLabels[3] = "3"; g_waveLabels[4] = "4"; g_waveLabels[5] = "5";
   }
   else if(pattern == TOOL_EW_ABC)
   {
      g_waveLabels[1] = "A"; g_waveLabels[2] = "B"; g_waveLabels[3] = "C";
   }
   else if(pattern == TOOL_EW_ABCDE)
   {
      g_waveLabels[1] = "A"; g_waveLabels[2] = "B"; g_waveLabels[3] = "C"; g_waveLabels[4] = "D"; g_waveLabels[5] = "E";
   }
   else if(pattern == TOOL_EW_WXY)
   {
      g_waveLabels[1] = "W"; g_waveLabels[2] = "X"; g_waveLabels[3] = "Y";
   }
   else if(pattern == TOOL_EW_WXYXZ)
   {
      g_waveLabels[1] = "W"; g_waveLabels[2] = "X"; g_waveLabels[3] = "Y"; g_waveLabels[4] = "X"; g_waveLabels[5] = "Z";
   }
}

void DeleteWaveObjectsByPrefix(const string prefix)
{
   if(prefix == "")
      return;

   for(int i = 0; i < 6; i++)
   {
      ObjectDelete(0, prefix + "_SEG_" + IntegerToString(i + 1));
      ObjectDelete(0, prefix + "_LBL_" + IntegerToString(i + 1));
   }
}

void RefreshWaveBackButton()
{
   if(ObjectFind(0, "RR_BTN_WAVE_BACK") < 0)
      ObjectCreate(0, "RR_BTN_WAVE_BACK", OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, "RR_BTN_WAVE_BACK", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "RR_BTN_WAVE_BACK", OBJPROP_XDISTANCE, InpPanelX + 8);
   ObjectSetInteger(0, "RR_BTN_WAVE_BACK", OBJPROP_YDISTANCE, InpPanelY + 272);
   ObjectSetInteger(0, "RR_BTN_WAVE_BACK", OBJPROP_XSIZE, 272);
   ObjectSetInteger(0, "RR_BTN_WAVE_BACK", OBJPROP_YSIZE, 22);
   ObjectSetString(0, "RR_BTN_WAVE_BACK", OBJPROP_TEXT, "戻る");

   bool visible = (g_pendingTool != TOOL_NONE && g_wavePointCount > 0);
   ObjectSetInteger(0, "RR_BTN_WAVE_BACK", OBJPROP_HIDDEN, !visible);
   ObjectSetInteger(0, "RR_BTN_WAVE_BACK", OBJPROP_STATE, false);
   ObjectSetInteger(0, "RR_BTN_WAVE_BACK", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "RR_BTN_WAVE_BACK", OBJPROP_BGCOLOR, C'70,30,30');
}

void RedrawCurrentWave()
{
   if(g_pendingTool == TOOL_NONE || g_wavePrefix == "")
      return;

   DeleteWaveObjectsByPrefix(g_wavePrefix);
   color clr = WaveColor(g_pendingTool);

   for(int i = 0; i < g_wavePointCount; i++)
   {
      string lbl = g_wavePrefix + "_LBL_" + IntegerToString(i + 1);
      ObjectCreate(0, lbl, OBJ_TEXT, 0, g_waveTimes[i], g_wavePrices[i]);
      ObjectSetString(0, lbl, OBJPROP_TEXT, g_waveLabels[i]);
      ObjectSetInteger(0, lbl, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 10);

      if(i > 0)
      {
         string seg = g_wavePrefix + "_SEG_" + IntegerToString(i);
         ObjectCreate(0, seg, OBJ_TREND, 0, g_waveTimes[i - 1], g_wavePrices[i - 1], g_waveTimes[i], g_wavePrices[i]);
         ObjectSetInteger(0, seg, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, seg, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, seg, OBJPROP_SELECTABLE, true);
      }
   }

   RefreshWaveBackButton();
}

void CancelWaveDrawing(const bool removeObjects)
{
   if(removeObjects)
      DeleteWaveObjectsByPrefix(g_wavePrefix);

   g_pendingTool = TOOL_NONE;
   g_waveTargetPoints = 0;
   g_wavePointCount = 0;
   g_wavePrefix = "";
   for(int i = 0; i < 6; i++) g_waveIsHigh[i] = false;
   RefreshWaveBackButton();
}

bool SnapToNearestCandlePivot(const datetime t, const double clickPrice, datetime &snapTime, double &snapPrice, bool &isHigh)
{
   int center = iBarShift(_Symbol, _Period, t, false);
   if(center < 0)
      return false;

   int bars = Bars(_Symbol, _Period);
   if(bars <= 0)
      return false;

   int range = MathMax(1, InpSnapSearchBars);
   int start = MathMax(0, center - range);
   int end = MathMin(bars - 1, center + range);

   double bestScore = DBL_MAX;
   bool found = false;

   for(int i = start; i <= end; i++)
   {
      datetime bt = iTime(_Symbol, _Period, i);
      double hi = iHigh(_Symbol, _Period, i);
      double lo = iLow(_Symbol, _Period, i);
      if(bt <= 0)
         continue;

      double scoreHi = MathAbs(clickPrice - hi);
      if(scoreHi < bestScore)
      {
         bestScore = scoreHi;
         snapTime = bt;
         snapPrice = hi;
         isHigh = true;
         found = true;
      }

      double scoreLo = MathAbs(clickPrice - lo);
      if(scoreLo < bestScore)
      {
         bestScore = scoreLo;
         snapTime = bt;
         snapPrice = lo;
         isHigh = false;
         found = true;
      }
   }

   return found;
}

void ToggleWaveMode(const int tool)
{
   if(g_pendingTool == tool)
   {
      CancelWaveDrawing(true);
      CreateToolNote("RR_NOTE_ELLIOTT", "エリオット描画モード解除", 310);
      return;
   }

   CancelWaveDrawing(true);
   g_pendingSide = 0;
   g_pendingTool = tool;
   g_waveTargetPoints = WavePointTarget(tool);
   g_wavePointCount = 0;
   g_wavePrefix = StringFormat("RR_EW_%d_%I64d", tool, TimeCurrent());
   SetupWaveLabels(tool);
   g_skipNextChartClick = true;
   RefreshWaveBackButton();
   CreateToolNote("RR_NOTE_ELLIOTT", "エリオット描画モード: 始点→1→2…の順にクリック", 310);
}

void DeleteAllDrawings()
{
   CancelWaveDrawing(true);
   DeleteSetup();

   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(name == "")
         continue;

      if(StringFind(name, "RR_EW_") == 0)
         ObjectDelete(0, name);
   }
}

void SetPlacementMode(const int side)
{
   CancelWaveDrawing(true);
   g_pendingSide = side;
   g_skipNextChartClick = true;
   string msg = (side > 0)
                ? "RR LONG: チャート上の任意位置をクリックして配置"
                : "RR SHORT: チャート上の任意位置をクリックして配置";
   CreateToolNote("RR_NOTE_PLACE", msg, 292);
}

int OnInit()
{
   g_syncEnabled = InpSyncLinesEnabled;

   if(!InpUseExternalPanel)
   {
      SetButtons();
      CreateToolNote("RR_NOTE_PLACE", "ARM=発注待機 / EXEC=即実行要求 / CANCEL=RR削除", 292);
      CreateToolNote("RR_NOTE_ELLIOTT", "エリオット: 始点→1→2…の順でクリックして描画", 310);
      RefreshWaveBackButton();
   }
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   ApplySyncedSetupIfNeeded();

   if(g_setupId != "")
      UpdateLabel();
   return(rates_total);
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(InpUseExternalPanel && id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, "RR_BTN_") == 0)
      return;

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(StringFind(sparam, "RR_BTN_") == 0)
         g_skipNextChartClick = true;

      if(sparam == "RR_BTN_LONG") SetPlacementMode(1);
      if(sparam == "RR_BTN_SHORT") SetPlacementMode(-1);

      if(sparam == "RR_BTN_ARM" && g_setupId != "")
      {
         g_armed = !g_armed;
         Publish(false);
         UpdateLabel();
      }

      if(sparam == "RR_BTN_EXEC" && g_setupId != "")
      {
         g_armed = true;
         Publish(true);
         UpdateLabel();
      }

      if(g_setupId != "" && sparam == ObjDeleteBtn())
      {
         g_pendingSide = 0;
         CancelWaveDrawing(true);
         DeleteSetup();
      }

      if(sparam == "RR_BTN_CANCEL")
      {
         g_pendingSide = 0;
         CancelWaveDrawing(true);
         DeleteSetup();
      }

      if(sparam == "RR_BTN_CLEAR_ALL")
      {
         g_pendingSide = 0;
         DeleteAllDrawings();
      }

      if(sparam == "RR_BTN_SYNC")
      {
         g_syncEnabled = !g_syncEnabled;
         UpdateSyncButtonLabel();
         if(g_syncEnabled && g_setupId != "")
            Publish(false);
      }

      if(sparam == "RR_BTN_EW_12345") ToggleWaveMode(TOOL_EW_12345);
      if(sparam == "RR_BTN_EW_ABC")   ToggleWaveMode(TOOL_EW_ABC);
      if(sparam == "RR_BTN_EW_ABCDE") ToggleWaveMode(TOOL_EW_ABCDE);
      if(sparam == "RR_BTN_EW_WXY")   ToggleWaveMode(TOOL_EW_WXY);
      if(sparam == "RR_BTN_EW_WXYXZ") ToggleWaveMode(TOOL_EW_WXYXZ);

      if(sparam == "RR_BTN_WAVE_BACK" && g_pendingTool != TOOL_NONE && g_wavePointCount > 0)
      {
         g_skipNextChartClick = true;
         g_wavePointCount--;
         RedrawCurrentWave();
         if(g_wavePointCount == 0)
            CreateToolNote("RR_NOTE_ELLIOTT", "エリオット描画モード: 始点→1→2…の順にクリック", 310);
      }
   }

   if(id == CHARTEVENT_CLICK && (g_pendingSide != 0 || g_pendingTool != TOOL_NONE))
   {
      if(g_skipNextChartClick)
      {
         g_skipNextChartClick = false;
         return;
      }

      int x = (int)lparam;
      int y = (int)dparam;
      datetime t;
      double p;
      int subwin = 0;
      if(ChartXYToTimePrice(0, x, y, subwin, t, p))
      {
         if(g_pendingSide != 0)
         {
            CreateSetupAt(g_pendingSide, t, p);
            g_pendingSide = 0;
            CreateToolNote("RR_NOTE_PLACE", "ARM=発注待機 / EXEC=即実行要求 / CANCEL=RR削除", 292);
         }
         else if(g_pendingTool != TOOL_NONE)
         {
            datetime snapTime;
            double snapPrice;
            bool isHigh = false;
            if(SnapToNearestCandlePivot(t, p, snapTime, snapPrice, isHigh))
            {
               if(g_wavePointCount < g_waveTargetPoints)
               {
                  g_waveTimes[g_wavePointCount] = snapTime;
                  g_waveIsHigh[g_wavePointCount] = isHigh;
                  double drawPrice = snapPrice;
                  if(g_pendingTool == TOOL_EW_12345 || g_pendingTool == TOOL_EW_ABC)
                     drawPrice = snapPrice + (isHigh ? 3.0 * _Point : -3.0 * _Point);
                  g_wavePrices[g_wavePointCount] = drawPrice;
                  g_wavePointCount++;
                  RedrawCurrentWave();
                  CreateToolNote("RR_NOTE_ELLIOTT", StringFormat("エリオット描画: %d/%d 点", g_wavePointCount, g_waveTargetPoints), 310);
               }

               if(g_wavePointCount >= g_waveTargetPoints)
               {
                  CreateToolNote("RR_NOTE_ELLIOTT", "エリオット描画完了", 310);
                  CancelWaveDrawing(false);
               }
            }
         }
      }
   }

   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      if(g_setupId == "")
         return;

      if(sparam == ObjEntry() || sparam == ObjSL() || sparam == ObjTP() || sparam == ObjWidthHandle())
      {
         datetime t1 = (datetime)ObjectGetInteger(0, ObjEntry(), OBJPROP_TIME, 0);
         datetime t2 = (datetime)ObjectGetInteger(0, ObjEntry(), OBJPROP_TIME, 1);

         if(sparam == ObjWidthHandle())
         {
            t2 = (datetime)ObjectGetInteger(0, ObjWidthHandle(), OBJPROP_TIME, 0);
            if(t2 <= t1)
               t2 = t1 + (datetime)MathMax(PeriodSeconds(), 60);
         }
         else
         {
            t1 = (datetime)ObjectGetInteger(0, sparam, OBJPROP_TIME, 0);
            t2 = (datetime)ObjectGetInteger(0, sparam, OBJPROP_TIME, 1);
         }

         if(sparam != ObjEntry() && sparam != ObjWidthHandle())
         {
            ObjectSetInteger(0, ObjEntry(), OBJPROP_TIME, 0, t1);
            ObjectSetInteger(0, ObjEntry(), OBJPROP_TIME, 1, t2);
         }
         ObjectSetInteger(0, ObjSL(), OBJPROP_TIME, 0, t1);
         ObjectSetInteger(0, ObjSL(), OBJPROP_TIME, 1, t2);
         ObjectSetInteger(0, ObjTP(), OBJPROP_TIME, 0, t1);
         ObjectSetInteger(0, ObjTP(), OBJPROP_TIME, 1, t2);

         if(sparam == ObjSL() && InpLockRR)
         {
            double entry, sl;
            if(ReadLinePrice(ObjEntry(), entry) && ReadLinePrice(ObjSL(), sl))
            {
               double risk = MathAbs(entry - sl);
               double tp = entry + (g_side > 0 ? 1 : -1) * risk * InpDefaultRR;
               ObjectSetDouble(0, ObjTP(), OBJPROP_PRICE, 0, tp);
               ObjectSetDouble(0, ObjTP(), OBJPROP_PRICE, 1, tp);
            }
         }

         SyncVisuals();
         UpdateLabel();
         Publish(false);
      }
   }
}

void OnDeinit(const int reason)
{
   DeleteSetup();

   if(!InpUseExternalPanel)
   {
      string names[19] = {"RR_PANEL_BG", "RR_TITLE", "RR_SEC_RR", "RR_SEC_EW", "RR_BTN_LONG", "RR_BTN_SHORT", "RR_BTN_ARM", "RR_BTN_EXEC", "RR_BTN_CANCEL", "RR_BTN_SYNC", "RR_BTN_EW_12345", "RR_BTN_EW_ABC", "RR_BTN_EW_ABCDE", "RR_BTN_EW_WXY", "RR_BTN_EW_WXYXZ", "RR_BTN_WAVE_BACK", "RR_BTN_CLEAR_ALL", "RR_NOTE_PLACE", "RR_NOTE_ELLIOTT"};
      for(int i = 0; i < 19; i++)
         ObjectDelete(0, names[i]);
   }
}
