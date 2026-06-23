//+------------------------------------------------------------------+
//|                                                  MultiMA_TooL.mq5 |
//|                                                       UnLimited.HK |
//|  5本MA同時表示 / SMA・EMA選択 / 個別色・期間 / パーフェクトオーダー  |
//|  背景ゾーン / MAタッチ検知 / MAクロス矢印 / レンジ帯               |
//+------------------------------------------------------------------+
#property copyright "UnLimited.HK"
#property version   "1.00"
#property description "Multi Moving Average tool: 5 MAs, Perfect Order zones, MA touch marks, MA cross arrows, range zones."
#property indicator_chart_window

//--- 9プロット = 9バッファ (MA線5本 + タッチ上下2 + クロス上下2)
#property indicator_buffers 9
#property indicator_plots   9

//--- プロット描画タイプ (実行時変更不可のため #property で宣言)
#property indicator_type1   DRAW_LINE
#property indicator_type2   DRAW_LINE
#property indicator_type3   DRAW_LINE
#property indicator_type4   DRAW_LINE
#property indicator_type5   DRAW_LINE
#property indicator_type6   DRAW_ARROW
#property indicator_type7   DRAW_ARROW
#property indicator_type8   DRAW_ARROW
#property indicator_type9   DRAW_ARROW

#include <MovingAverages.mqh>

//+------------------------------------------------------------------+
//| MAタイプ (要件②: SMA / EMA のみ)                                  |
//+------------------------------------------------------------------+
enum ENUM_MA_TYPE
  {
   MA_SMA = 0, // SMA (単純移動平均)
   MA_EMA = 1  // EMA (指数移動平均)
  };

//+------------------------------------------------------------------+
//| 入力パラメータ                                                    |
//+------------------------------------------------------------------+
input group "=== 共通設定 ==="
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; // 適用価格
input int                InpLineWidth    = 3;           // MA線の太さ

input group "=== MA1 ==="
input bool         MA1_Show   = true;     // MA1 表示
input int          MA1_Period = 25;       // MA1 期間
input ENUM_MA_TYPE MA1_Method = MA_SMA;   // MA1 タイプ
input color        MA1_Color  = clrRed;   // MA1 色

input group "=== MA2 ==="
input bool         MA2_Show   = true;     // MA2 表示
input int          MA2_Period = 45;       // MA2 期間
input ENUM_MA_TYPE MA2_Method = MA_SMA;   // MA2 タイプ
input color        MA2_Color  = clrOrange;// MA2 色

input group "=== MA3 ==="
input bool         MA3_Show   = true;     // MA3 表示
input int          MA3_Period = 75;       // MA3 期間
input ENUM_MA_TYPE MA3_Method = MA_SMA;   // MA3 タイプ
input color        MA3_Color  = clrGreen; // MA3 色

input group "=== MA4 ==="
input bool         MA4_Show   = true;     // MA4 表示
input int          MA4_Period = 200;      // MA4 期間
input ENUM_MA_TYPE MA4_Method = MA_SMA;   // MA4 タイプ
input color        MA4_Color  = clrBlue;  // MA4 色

input group "=== MA5 ==="
input bool         MA5_Show   = true;     // MA5 表示
input int          MA5_Period = 400;      // MA5 期間
input ENUM_MA_TYPE MA5_Method = MA_SMA;   // MA5 タイプ
input color        MA5_Color  = clrPurple;// MA5 色

input group "=== パーフェクトオーダー (背景ゾーン) ==="
input bool   PO_Enable    = true;                 // PO ゾーン表示
input bool   PO_UseMA1    = true;                 // 判定に MA1 を使う
input bool   PO_UseMA2    = false;                // 判定に MA2 を使う
input bool   PO_UseMA3    = true;                 // 判定に MA3 を使う
input bool   PO_UseMA4    = true;                 // 判定に MA4 を使う
input bool   PO_UseMA5    = false;                // 判定に MA5 を使う
input color  PO_BullColor = clrAliceBlue;         // PO 上昇ゾーン色
input color  PO_BearColor = clrSeashell;          // PO 下降ゾーン色

input group "=== MAタッチ検知 ==="
input bool   Touch_Enable    = false;    // タッチマーク表示
input bool   Touch_UseMA1    = false;    // MA1 へのタッチを検知
input bool   Touch_UseMA2    = false;    // MA2 へのタッチを検知
input bool   Touch_UseMA3    = true;     // MA3 へのタッチを検知
input bool   Touch_UseMA4    = true;     // MA4 へのタッチを検知
input bool   Touch_UseMA5    = false;    // MA5 へのタッチを検知
input int    Touch_UpCode    = 159;      // 支持タッチ記号 (Wingdings ●)
input int    Touch_DownCode  = 159;      // 抵抗タッチ記号 (Wingdings ●)
input color  Touch_UpColor   = clrDodgerBlue;  // 支持タッチ色
input color  Touch_DownColor = clrCrimson;     // 抵抗タッチ色

input group "=== MAクロス矢印 ==="
input bool   Cross_Enable    = false;    // クロス矢印表示
input int    Cross_FastIndex = 1;        // 短期MA番号 (1-5)
input int    Cross_SlowIndex = 3;        // 長期MA番号 (1-5)
input int    Cross_UpCode    = 159;      // ゴールデンクロス記号 (Wingdings ●)
input int    Cross_DownCode  = 159;      // デッドクロス記号 (Wingdings ●)
input color  Cross_UpColor   = clrLime;       // ゴールデンクロス色
input color  Cross_DownColor = clrMagenta;    // デッドクロス色

input group "=== レンジ帯 (MA収束) ==="
input bool   Range_Enable          = true;       // レンジ帯表示
input int    Range_ThresholdPoints = 150;        // 収束しきい値 (points)
input color  Range_Color           = clrKhaki;   // レンジ帯色

//+------------------------------------------------------------------+
//| バッファ                                                          |
//+------------------------------------------------------------------+
double ExtMA1[];
double ExtMA2[];
double ExtMA3[];
double ExtMA4[];
double ExtMA5[];
double ExtTouchUp[];
double ExtTouchDn[];
double ExtCrossUp[];
double ExtCrossDn[];

//--- 計算用 (非プロット)
double ExtPrice[];

//--- PO/レンジ判定に使う MA インデックス (期間昇順)
int    ExtOrder[];
int    ExtOrderCount = 0;
int    ExtMaxPeriod  = 1;
int    ExtRatesTotal = 0;   // 最新の rates_total (OnChartEvent から参照)

//--- ゾーンオブジェクト名プレフィックス
const string ZONE_PREFIX = "MMT_ZONE_";

//+------------------------------------------------------------------+
//| 配列ユーティリティ                                                |
//+------------------------------------------------------------------+
int    Periods(const int idx)
  {
   switch(idx)
     {
      case 1: return MA1_Period;
      case 2: return MA2_Period;
      case 3: return MA3_Period;
      case 4: return MA4_Period;
      case 5: return MA5_Period;
     }
   return 0;
  }

bool   ShowFlag(const int idx)
  {
   switch(idx)
     {
      case 1: return MA1_Show;
      case 2: return MA2_Show;
      case 3: return MA3_Show;
      case 4: return MA4_Show;
      case 5: return MA5_Show;
     }
   return false;
  }

color  ColorOf(const int idx)
  {
   switch(idx)
     {
      case 1: return MA1_Color;
      case 2: return MA2_Color;
      case 3: return MA3_Color;
      case 4: return MA4_Color;
      case 5: return MA5_Color;
     }
   return clrNONE;
  }

ENUM_MA_TYPE MethodOf(const int idx)
  {
   switch(idx)
     {
      case 1: return MA1_Method;
      case 2: return MA2_Method;
      case 3: return MA3_Method;
      case 4: return MA4_Method;
      case 5: return MA5_Method;
     }
   return MA_SMA;
  }

bool   PoUse(const int idx)
  {
   switch(idx)
     {
      case 1: return PO_UseMA1;
      case 2: return PO_UseMA2;
      case 3: return PO_UseMA3;
      case 4: return PO_UseMA4;
      case 5: return PO_UseMA5;
     }
   return false;
  }

bool   TouchUse(const int idx)
  {
   switch(idx)
     {
      case 1: return Touch_UseMA1;
      case 2: return Touch_UseMA2;
      case 3: return Touch_UseMA3;
      case 4: return Touch_UseMA4;
      case 5: return Touch_UseMA5;
     }
   return false;
  }

//--- idx番(1-5)のMA値を bar 位置で返す
double MAval(const int idx,const int bar)
  {
   switch(idx)
     {
      case 1: return ExtMA1[bar];
      case 2: return ExtMA2[bar];
      case 3: return ExtMA3[bar];
      case 4: return ExtMA4[bar];
      case 5: return ExtMA5[bar];
     }
   return 0.0;
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- バッファ束縛 (0始まり連番、すべて非時系列)
   SetIndexBuffer(0,ExtMA1,INDICATOR_DATA);
   SetIndexBuffer(1,ExtMA2,INDICATOR_DATA);
   SetIndexBuffer(2,ExtMA3,INDICATOR_DATA);
   SetIndexBuffer(3,ExtMA4,INDICATOR_DATA);
   SetIndexBuffer(4,ExtMA5,INDICATOR_DATA);
   SetIndexBuffer(5,ExtTouchUp,INDICATOR_DATA);
   SetIndexBuffer(6,ExtTouchDn,INDICATOR_DATA);
   SetIndexBuffer(7,ExtCrossUp,INDICATOR_DATA);
   SetIndexBuffer(8,ExtCrossDn,INDICATOR_DATA);

//--- MA線プロット設定 (色は実行時に PLOT_LINE_COLOR で指定)
   for(int idx=1; idx<=5; idx++)
     {
      int    plot   = idx-1;
      int    period = Periods(idx);
      color  c      = ShowFlag(idx) ? ColorOf(idx) : clrNONE; // 非表示は透明
      PlotIndexSetInteger(plot,PLOT_DRAW_TYPE,DRAW_LINE);
      PlotIndexSetInteger(plot,PLOT_LINE_COLOR,c);
      PlotIndexSetInteger(plot,PLOT_LINE_WIDTH,InpLineWidth);
      PlotIndexSetInteger(plot,PLOT_DRAW_BEGIN,period-1);
      PlotIndexSetDouble(plot,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      PlotIndexSetString(plot,PLOT_LABEL,StringFormat("MA%d(%d %s)",idx,period,
                         MethodOf(idx)==MA_EMA?"EMA":"SMA"));
     }

//--- 最大期間 (ウォームアップ用)
   ExtMaxPeriod = 1;
   for(int idx=1; idx<=5; idx++)
      ExtMaxPeriod = MathMax(ExtMaxPeriod,Periods(idx));

//--- 矢印プロット設定 (5:タッチ上 6:タッチ下 7:GC 8:DC)
   PlotIndexSetInteger(5,PLOT_ARROW,Touch_UpCode);
   PlotIndexSetInteger(5,PLOT_LINE_COLOR,Touch_UpColor);
   PlotIndexSetDouble (5,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(5,PLOT_DRAW_BEGIN,ExtMaxPeriod);
   PlotIndexSetString (5,PLOT_LABEL,"Touch Up");

   PlotIndexSetInteger(6,PLOT_ARROW,Touch_DownCode);
   PlotIndexSetInteger(6,PLOT_LINE_COLOR,Touch_DownColor);
   PlotIndexSetDouble (6,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(6,PLOT_DRAW_BEGIN,ExtMaxPeriod);
   PlotIndexSetString (6,PLOT_LABEL,"Touch Down");

   PlotIndexSetInteger(7,PLOT_ARROW,Cross_UpCode);
   PlotIndexSetInteger(7,PLOT_LINE_COLOR,Cross_UpColor);
   PlotIndexSetDouble (7,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(7,PLOT_DRAW_BEGIN,ExtMaxPeriod);
   PlotIndexSetString (7,PLOT_LABEL,"Golden Cross");

   PlotIndexSetInteger(8,PLOT_ARROW,Cross_DownCode);
   PlotIndexSetInteger(8,PLOT_LINE_COLOR,Cross_DownColor);
   PlotIndexSetDouble (8,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(8,PLOT_DRAW_BEGIN,ExtMaxPeriod);
   PlotIndexSetString (8,PLOT_LABEL,"Dead Cross");

//--- PO/レンジ判定に使う MA を期間昇順に並べる
   BuildOrder();

//--- クロス番号の妥当性チェック
   if(Cross_FastIndex<1 || Cross_FastIndex>5 ||
      Cross_SlowIndex<1 || Cross_SlowIndex>5 ||
      Cross_FastIndex==Cross_SlowIndex)
     {
      if(Cross_Enable)
         Print("MultiMA_TooL: Cross_FastIndex/Cross_SlowIndex が不正です (1-5 で異なる値を指定)。クロス矢印は無効化されます。");
     }

   IndicatorSetString(INDICATOR_SHORTNAME,"MultiMA_TooL");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| PO/レンジ判定対象MAを期間昇順に並べる                              |
//+------------------------------------------------------------------+
void BuildOrder()
  {
   ArrayResize(ExtOrder,0);
   ExtOrderCount = 0;
   int idxs[];
   for(int idx=1; idx<=5; idx++)
      if(PoUse(idx) && Periods(idx)>0)
        {
         int n = ArraySize(idxs);
         ArrayResize(idxs,n+1);
         idxs[n] = idx;
        }
//--- 期間で昇順ソート (単純な挿入ソート)
   int cnt = ArraySize(idxs);
   for(int a=1; a<cnt; a++)
     {
      int key = idxs[a];
      int b   = a-1;
      while(b>=0 && Periods(idxs[b])>Periods(key))
        {
         idxs[b+1] = idxs[b];
         b--;
        }
      idxs[b+1] = key;
     }
   ArrayResize(ExtOrder,cnt);
   for(int a=0; a<cnt; a++)
      ExtOrder[a] = idxs[a];
   ExtOrderCount = cnt;
  }

//+------------------------------------------------------------------+
//| 適用価格を計算                                                    |
//+------------------------------------------------------------------+
double AppliedPriceAt(const int i,const double &open[],const double &high[],
                      const double &low[],const double &close[])
  {
   switch(InpAppliedPrice)
     {
      case PRICE_OPEN:     return open[i];
      case PRICE_HIGH:     return high[i];
      case PRICE_LOW:      return low[i];
      case PRICE_MEDIAN:   return (high[i]+low[i])/2.0;
      case PRICE_TYPICAL:  return (high[i]+low[i]+close[i])/3.0;
      case PRICE_WEIGHTED: return (high[i]+low[i]+2.0*close[i])/4.0;
      case PRICE_CLOSE:
      default:             return close[i];
     }
  }

//+------------------------------------------------------------------+
//| 1本の MA をバッファへ計算                                          |
//+------------------------------------------------------------------+
void CalcMA(const ENUM_MA_TYPE method,const int period,const int rates_total,
            const int prev_calculated,const double &price[],double &buffer[])
  {
   if(method==MA_EMA)
      ExponentialMAOnBuffer(rates_total,prev_calculated,0,period,price,buffer);
   else
      SimpleMAOnBuffer(rates_total,prev_calculated,0,period,price,buffer);
  }

//+------------------------------------------------------------------+
//| バー i の状態: 0=なし 1=PO上昇 2=PO下降 3=レンジ                   |
//+------------------------------------------------------------------+
int BarState(const int i)
  {
   if(ExtOrderCount<2)
      return 0;

//--- パーフェクトオーダー (短期>中期>長期 = 上昇 / 逆 = 下降)
   if(PO_Enable)
     {
      bool bull = true, bear = true;
      for(int k=0; k+1<ExtOrderCount; k++)
        {
         double a = MAval(ExtOrder[k],i);
         double b = MAval(ExtOrder[k+1],i);
         if(!(a>b)) bull = false;
         if(!(a<b)) bear = false;
        }
      if(bull) return 1;
      if(bear) return 2;
     }

//--- レンジ (選択MAの値が収束)
   if(Range_Enable)
     {
      double mn = DBL_MAX, mx = -DBL_MAX;
      for(int k=0; k<ExtOrderCount; k++)
        {
         double v = MAval(ExtOrder[k],i);
         mn = MathMin(mn,v);
         mx = MathMax(mx,v);
        }
      if((mx-mn) <= Range_ThresholdPoints*_Point)
         return 3;
     }

   return 0;
  }

//+------------------------------------------------------------------+
//| ゾーン矩形を1個作成 (id連番、全高は現在のチャート表示範囲)         |
//+------------------------------------------------------------------+
void CreateZoneIdx(const int id,const int st,const datetime t1,const datetime t2,
                   const double pmax,const double pmin)
  {
   string nm = ZONE_PREFIX + (string)id;
   if(ObjectFind(0,nm)<0)
      ObjectCreate(0,nm,OBJ_RECTANGLE,0,t1,pmax,t2,pmin);
   else
     {
      ObjectMove(0,nm,0,t1,pmax);
      ObjectMove(0,nm,1,t2,pmin);
     }
   color c = (st==1) ? PO_BullColor : (st==2) ? PO_BearColor : Range_Color;
   ObjectSetInteger(0,nm,OBJPROP_COLOR,c);
   ObjectSetInteger(0,nm,OBJPROP_FILL,true);
   ObjectSetInteger(0,nm,OBJPROP_BACK,true);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
  }

//+------------------------------------------------------------------+
//| 背景ゾーンを「表示中のバー範囲だけ」描画                          |
//|  全履歴を描かないことで、過去スクロール/縮小時の重さと            |
//|  MA線が消える現象 (描画詰まり) を回避する                         |
//+------------------------------------------------------------------+
void RedrawVisibleZones()
  {
//--- 既存ゾーンを一旦すべて削除 (オブジェクト数を表示範囲分に抑える)
   ObjectsDeleteAll(0,ZONE_PREFIX,-1,OBJ_RECTANGLE);

   if((!PO_Enable && !Range_Enable) || ExtOrderCount<2 || ExtRatesTotal<ExtMaxPeriod+2)
     {
      ChartRedraw();
      return;
     }

   double pmax = ChartGetDouble(0,CHART_PRICE_MAX,0);
   double pmin = ChartGetDouble(0,CHART_PRICE_MIN,0);
   if(pmax<=pmin)
     {
      ChartRedraw();
      return;
     }

//--- 表示中バーの範囲を取得 (series index: 0=最新)
   int firstVis = (int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR,0); // 左端(最古)
   int visBars  = (int)ChartGetInteger(0,CHART_VISIBLE_BARS,0);
   if(visBars<=0)
     {
      ChartRedraw();
      return;
     }
   int leftSeries  = firstVis;                 // 最古側
   int rightSeries = firstVis - visBars + 1;   // 最新側
   if(rightSeries < 0)
      rightSeries = 0;

//--- series index → バッファ index (非時系列, 0=最古) に変換
   int loBuf = (ExtRatesTotal-1) - leftSeries;
   int hiBuf = (ExtRatesTotal-1) - rightSeries;
   int firstValid = ExtMaxPeriod;
   int lastClosed = ExtRatesTotal-2;
   if(loBuf < firstValid) loBuf = firstValid;
   if(hiBuf > lastClosed) hiBuf = lastClosed;
   if(loBuf > hiBuf)
     {
      ChartRedraw();
      return;
     }

   long secs = PeriodSeconds(_Period);
   int  id   = 0;
   int  i    = loBuf;
   while(i<=hiBuf)
     {
      int st = BarState(i);
      int j  = i;
      while(j+1<=hiBuf && BarState(j+1)==st)
         j++;
      if(st!=0)
        {
         int      sLeft  = (ExtRatesTotal-1) - i;          // 区間左端の series index
         int      sRight = (ExtRatesTotal-1) - j;          // 区間右端の series index
         datetime t1 = iTime(_Symbol,_Period,sLeft);
         datetime t2 = (sRight-1>=0) ? iTime(_Symbol,_Period,sRight-1)
                                     : (datetime)(iTime(_Symbol,_Period,sRight)+secs);
         if(t1>0 && t2>0)
            CreateZoneIdx(id++,st,t1,t2,pmax,pmin);
        }
      i = j+1;
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
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
   if(rates_total < ExtMaxPeriod+2)
      return(0);

//--- すべての配列を非時系列 (index 0 = 最古) に固定
   ArraySetAsSeries(time,false);
   ArraySetAsSeries(open,false);
   ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);
   ArraySetAsSeries(close,false);

//--- 適用価格バッファを用意 (増分)
   if(ArraySize(ExtPrice)!=rates_total)
      ArrayResize(ExtPrice,rates_total);
   int priceStart = (prev_calculated>0) ? prev_calculated-1 : 0;
   for(int i=priceStart; i<rates_total; i++)
      ExtPrice[i] = AppliedPriceAt(i,open,high,low,close);

//--- 5本の MA を計算 (非表示MAも PO/タッチ/クロス用に常に計算)
   CalcMA(MA1_Method,MA1_Period,rates_total,prev_calculated,ExtPrice,ExtMA1);
   CalcMA(MA2_Method,MA2_Period,rates_total,prev_calculated,ExtPrice,ExtMA2);
   CalcMA(MA3_Method,MA3_Period,rates_total,prev_calculated,ExtPrice,ExtMA3);
   CalcMA(MA4_Method,MA4_Period,rates_total,prev_calculated,ExtPrice,ExtMA4);
   CalcMA(MA5_Method,MA5_Period,rates_total,prev_calculated,ExtPrice,ExtMA5);

//--- 計算開始位置 (リペイント回避: prev_calculated 増分)
   int firstValid = ExtMaxPeriod;
   int start = (prev_calculated>0) ? prev_calculated-1 : firstValid;
   if(start < firstValid)
      start = firstValid;

//--- 初回はウォームアップ域の矢印バッファを EMPTY で初期化
   if(prev_calculated==0)
     {
      ArrayInitialize(ExtTouchUp,EMPTY_VALUE);
      ArrayInitialize(ExtTouchDn,EMPTY_VALUE);
      ArrayInitialize(ExtCrossUp,EMPTY_VALUE);
      ArrayInitialize(ExtCrossDn,EMPTY_VALUE);
     }

   bool crossValid = (Cross_Enable &&
                      Cross_FastIndex>=1 && Cross_FastIndex<=5 &&
                      Cross_SlowIndex>=1 && Cross_SlowIndex<=5 &&
                      Cross_FastIndex!=Cross_SlowIndex);

//--- 確定足のみ処理 (最終バー rates_total-1 は形成中なので除外)
   int lastClosed = rates_total-2;

   for(int i=start; i<rates_total; i++)
     {
      //--- まず当該バーの矢印を毎回クリア (再評価のたびに上書き)
      ExtTouchUp[i] = EMPTY_VALUE;
      ExtTouchDn[i] = EMPTY_VALUE;
      ExtCrossUp[i] = EMPTY_VALUE;
      ExtCrossDn[i] = EMPTY_VALUE;

      if(i>lastClosed)        // 形成中バーはシグナル判定しない
         continue;

      double rng = high[i]-low[i];
      double off = (rng>0.0) ? rng*0.4 : 10*_Point;

      //--- 機能⑨ MAタッチ検知 (low<=MA<=high)
      if(Touch_Enable)
        {
         for(int idx=1; idx<=5; idx++)
           {
            if(!TouchUse(idx))
               continue;
            double ma = MAval(idx,i);
            if(ma==EMPTY_VALUE || ma==0.0)
               continue;
            if(low[i]<=ma && ma<=high[i])
              {
               if(close[i]>=ma)
                  ExtTouchUp[i] = low[i]-off;   // 支持としてタッチ → 下に記号
               else
                  ExtTouchDn[i] = high[i]+off;  // 抵抗としてタッチ → 上に記号
               break;                            // 1バー1マーク
              }
           }
        }

      //--- 機能⑩ MAクロス
      if(crossValid && i>=firstValid+1)
        {
         double f0 = MAval(Cross_FastIndex,i);
         double s0 = MAval(Cross_SlowIndex,i);
         double f1 = MAval(Cross_FastIndex,i-1);
         double s1 = MAval(Cross_SlowIndex,i-1);
         if(f1<=s1 && f0>s0)
            ExtCrossUp[i] = low[i]-off*1.6;   // ゴールデンクロス ↑
         else if(f1>=s1 && f0<s0)
            ExtCrossDn[i] = high[i]+off*1.6;  // デッドクロス ↓
        }
     }

//--- 機能⑦⑧⑪ 背景ゾーン: 表示範囲のみ・新バー時/初回のみ再描画
//    (毎ティック描画と全履歴オブジェクト生成をやめて軽量化)
   ExtRatesTotal = rates_total;
   static datetime lastZoneBar = 0;
   datetime curBar = time[rates_total-1];
   if(prev_calculated==0 || curBar!=lastZoneBar)
     {
      RedrawVisibleZones();
      lastZoneBar = curBar;
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| OnChartEvent: スクロール/ズーム時に表示範囲のゾーンを描き直す      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,
                  const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
      RedrawVisibleZones();
  }

//+------------------------------------------------------------------+
//| OnDeinit: 作成したオブジェクトを削除                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,ZONE_PREFIX,-1,OBJ_RECTANGLE);
   ChartRedraw();
  }
//+------------------------------------------------------------------+
