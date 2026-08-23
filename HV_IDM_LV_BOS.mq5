//+------------------------------------------------------------------+
//|                                             HV_IDM_LV_BOS.mq5    |
//|  Market structure: Candidate -> IDM -> HV/LV -> BOS               |
//|  Supports both bullish and bearish bias (InpBias).                 |
//|  Only draws the LATEST state (live IDM, last HV, last LV, last     |
//|  BOS) - no historical clutter. CHoCH is not implemented yet.       |
//|                                                                    |
//|  Definitions, written for the BULLISH case (InpBias=Bullish). The  |
//|  BEARISH case is the exact mirror: swap every "high" for "low" and |
//|  vice versa; the point confirmed first is LV instead of HV, and     |
//|  the point confirmed second is HV instead of LV.                    |
//|                                                                    |
//|   candidate (internal, not drawn) - a fractal swing-high candidate.|
//|                         It becomes the active candidate whenever    |
//|                         its price is higher than the currently      |
//|                         active one.                                  |
//|   IDM (Inducement)   - the lowest fractal swing-low since the       |
//|                         active candidate's last update. Shown LIVE  |
//|                         as soon as a pullback forms, before knowing |
//|                         whether it will get swept. It is LOCKED IN  |
//|                         (becomes the operative IDM, replacing        |
//|                         whatever was locked before) the moment the  |
//|                         candidate updates to a new, higher high.    |
//|                         Only the most recently locked IDM is ever   |
//|                         checked for a swap - older ones stop         |
//|                         mattering the instant a newer one locks in. |
//|   HV  (High Valid)   - confirmed the instant any candle's LOW wicks |
//|                         below the currently locked IDM (wick only,  |
//|                         no close required). HV's price is the       |
//|                         active candidate's price at that moment.    |
//|   LV  (Low Valid)    - after HV, the running lowest LOW since HV is |
//|                         tracked; a reference level starts at HV's   |
//|                         price. A candle whose HIGH wicks above the  |
//|                         reference without closing above it raises   |
//|                         the reference to that wick's high (a false  |
//|                         break / swap). The first candle whose CLOSE |
//|                         closes above the (possibly raised)           |
//|                         reference confirms BOS; LV is the lowest    |
//|                         low reached since HV up to that point.      |
//|                                                                    |
//|  It has NOT been compiled/tested in a live MetaEditor - compile     |
//|  and verify on a chart before trusting it for anything that         |
//|  touches real trades.                                                |
//+------------------------------------------------------------------+
#property copyright "generated for fx-mt5-ai-onnx-ea"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#property strict

enum ENUM_BIAS
  {
   BIAS_BULLISH = 0,   // Bullish (HV confirmed first, then LV/BOS)
   BIAS_BEARISH = 1    // Bearish (LV confirmed first, then HV/BOS)
  };

input ENUM_BIAS InpBias        = BIAS_BULLISH; // Bias
input datetime  InpStartTime   = 0;            // Start time (0 = auto from InpMaxBars)
input int       InpSwingLength = 3;            // Fractal swing length (bars each side)
input int       InpMaxBars     = 3000;         // How many bars back to scan (used when InpStartTime=0)
input color     InpColorIDM    = clrOrange;    // IDM (live) color
input color     InpColorFirst  = clrDodgerBlue;// First-confirmed point color (HV in bull, LV in bear)
input color     InpColorSecond = clrMagenta;   // Second-confirmed point color (LV in bull, HV in bear)
input color     InpColorBOS    = clrLime;      // BOS / reference line color
input int       InpFontSize    = 9;

#define PFX "HVIDM_"

//--- one tracked extreme (a candidate, a shadow/locked opposite point, ...)
struct SExtreme
  {
   int      idx;     // bar index in the ascending (oldest->newest) arrays
   double   value;   // in TRANSFORMED space (see ToReal()); negate for bearish to get the real price
   bool     valid;
  };

bool g_bull; // true = bullish bias, false = bearish

//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME,
                       InpBias == BIAS_BULLISH ? "HV/IDM/LV/BOS (bull)" : "LV/IDM/HV/BOS (bear)");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
  }

//+------------------------------------------------------------------+
void MakeExtreme(SExtreme &e, int idx, double value)
  {
   e.idx = idx; e.value = value; e.valid = true;
  }

//+------------------------------------------------------------------+
double ToReal(double v) { return g_bull ? v : -v; }

//+------------------------------------------------------------------+
//| draw a small text label at (time[idx], realPrice)                 |
//+------------------------------------------------------------------+
void DrawLabel(string name, datetime t, double realPrice, string text,
               color clr, bool above)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, realPrice);
   else
      ObjectMove(0, name, 0, t, realPrice);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

//+------------------------------------------------------------------+
//| draw a horizontal dotted reference line from bar t1 to bar t2      |
//+------------------------------------------------------------------+
void DrawRefLine(string name, datetime t1, datetime t2, double realPrice, color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, realPrice, t2, realPrice);
   else
     {
      ObjectMove(0, name, 0, t1, realPrice);
      ObjectMove(0, name, 1, t2, realPrice);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
  }

//+------------------------------------------------------------------+
//| Is bar i a fractal high of Arr[], looking back/forward InpSwingLength
//| bars each way - but the backward side never looks earlier than
//| backLimit (the bar the current leg's tracking started from). Without
//| this clip, a pivot check can reach back across a leg boundary into
//| unrelated older price action (e.g. the deep low that started the
//| PREVIOUS leg) and get wrongly disqualified by it, or - the opposite
//| failure - let a real peak masquerade as "the" candidate because a
//| taller peak from the same old context sits just past a fixed window.
//+------------------------------------------------------------------+
bool IsPivotHighClipped(const double &Arr[], int i, int backLimit, int len, int sl)
  {
   if(i - sl < 0 || i + sl >= len)
      return false;
   int backStart = MathMax(backLimit, i - sl);
   for(int k = backStart; k < i; k++)
      if(Arr[k] >= Arr[i]) return false;
   for(int k = i + 1; k <= i + sl; k++)
      if(Arr[k] >= Arr[i]) return false;
   return true;
  }

bool IsPivotLowClipped(const double &Arr[], int i, int backLimit, int len, int sl)
  {
   if(i - sl < 0 || i + sl >= len)
      return false;
   int backStart = MathMax(backLimit, i - sl);
   for(int k = backStart; k < i; k++)
      if(Arr[k] <= Arr[i]) return false;
   for(int k = i + 1; k <= i + sl; k++)
      if(Arr[k] <= Arr[i]) return false;
   return true;
  }

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
   int n = rates_total;
   if(n < 2 * InpSwingLength + 5)
      return(rates_total);

   g_bull = (InpBias == BIAS_BULLISH);

   // work in ascending (oldest->newest) order regardless of the chart's
   // series direction, since OnCalculate already delivers arrays in
   // ascending (index 0 = oldest) order when the platform default is used.
   int start;
   if(InpStartTime > 0)
     {
      start = 0;
      for(int k = 0; k < n; k++)
         if(time[k] >= InpStartTime) { start = k; break; }
     }
   else
      start = MathMax(0, n - InpMaxBars);
   int len = n - start;
   if(len < 2 * InpSwingLength + 5)
      return(rates_total);

   // Hi[] / Lo[] are the transformed series: in bullish bias Hi=High, Lo=Low
   // (used directly); in bearish bias Hi=-Low, Lo=-High, so that "track the
   // running MAXIMUM of Hi" always means "find the candidate" (a real high
   // for bull, a real low for bear) and "track the running MINIMUM of Lo"
   // always means "find the opposite/IDM point" - the whole state machine
   // below is then bias-agnostic. Cl[] mirrors Close[] the same way.
   double Hi[], Lo[], Cl[];
   datetime T[];
   ArrayResize(Hi, len); ArrayResize(Lo, len);
   ArrayResize(Cl, len); ArrayResize(T, len);
   for(int k = 0; k < len; k++)
     {
      Hi[k] = g_bull ?  high[start + k] : -low[start + k];
      Lo[k] = g_bull ?  low[start + k]  : -high[start + k];
      Cl[k] = g_bull ?  close[start + k]: -close[start + k];
      T[k]  = time[start + k];
     }

   int sl = InpSwingLength;

   string firstLbl = g_bull ? "HV" : "LV";
   string secondLbl = g_bull ? "LV" : "HV";

   // seed the very first candidate from the very first pivot found, using
   // the scan window's own start as the back-limit (nothing before it exists).
   int firstIdx = -1;
   for(int i = sl; i < len - sl; i++)
      if(IsPivotHighClipped(Hi, i, 0, len, sl)) { firstIdx = i; break; }
   if(firstIdx < 0)
      return(rates_total);

   int legN = 0;

   SExtreme candidate;    MakeExtreme(candidate, firstIdx, Hi[firstIdx]);
   SExtreme shadow;       shadow.valid = false;
   SExtreme lockedOpp;    lockedOpp.valid = false;
   SExtreme secondPoint;  secondPoint.valid = false;
   SExtreme reference;    reference.valid = false;
   SExtreme pendingFirst; pendingFirst.valid = false; // HV confirmed, but its own LV/BOS hasn't happened yet
   string phase = "seek_first";

   // rolling "latest state" - only these get drawn, at the very end, so the
   // chart never shows more than one of each even across thousands of bars.
   // HV/LV/BOS are only ever updated TOGETHER, as one atomic triplet, exactly
   // when a leg's BOS confirms - so the chart never shows a mismatched pair
   // (a brand new HV that's still waiting on its own LV sitting next to a
   // stale LV left over from a completely different, earlier leg).
   bool     haveLiveIdm = false; SExtreme liveIdm;
   bool     haveLeg = false;     SExtreme lastFirst, lastSecond; int lastLegN = 0;
   bool     haveBos = false;     int bosFromIdx = -1, bosIdx = -1; double bosLevel = 0;

   for(int i = firstIdx + 1; i < len - sl; i++)
     {
      if(phase == "seek_first")
        {
         if(IsPivotLowClipped(Lo, i, candidate.idx, len, sl) && (!shadow.valid || Lo[i] < shadow.value))
           {
            MakeExtreme(shadow, i, Lo[i]);
            liveIdm = shadow; haveLiveIdm = true;
           }

         if(lockedOpp.valid && Lo[i] < lockedOpp.value)
           {
            MakeExtreme(pendingFirst, candidate.idx, candidate.value);
            phase = "seek_second";
            MakeExtreme(secondPoint, i, Lo[i]);
            MakeExtreme(reference, candidate.idx, candidate.value);
            continue;
           }

         if(IsPivotHighClipped(Hi, i, candidate.idx, len, sl) && Hi[i] > candidate.value)
           {
            if(shadow.valid)
              {
               lockedOpp = shadow;
               liveIdm = shadow; haveLiveIdm = true;
              }
            MakeExtreme(candidate, i, Hi[i]);
            shadow.valid = false;
           }
        }
      else // seek_second
        {
         if(Lo[i] < secondPoint.value)
            MakeExtreme(secondPoint, i, Lo[i]);

         if(Cl[i] > reference.value)
           {
            legN++;
            lastFirst = pendingFirst; lastSecond = secondPoint; lastLegN = legN; haveLeg = true;
            bosFromIdx = reference.idx; bosIdx = i; bosLevel = reference.value;
            haveBos = true;

            phase = "seek_first";
            MakeExtreme(candidate, i, Hi[i]);
            shadow.valid = false;
            lockedOpp.valid = false;
            haveLiveIdm = false; // fresh leg - no live IDM yet until a pullback forms
           }
         else if(Hi[i] > reference.value)
            MakeExtreme(reference, i, Hi[i]);
        }
     }

   ObjectsDeleteAll(0, PFX);

   if(haveLiveIdm)
      // no ordinal number here: this point is "live" and may still move to a
      // deeper pullback before it ever gets locked in, so a fixed "IDM9" would
      // misleadingly imply it's already the same thing as a specific locked IDM.
      DrawLabel(PFX + "IDM", T[liveIdm.idx], ToReal(liveIdm.value),
                "IDM", InpColorIDM, !g_bull);
   if(haveLeg)
     {
      DrawLabel(PFX + firstLbl, T[lastFirst.idx], ToReal(lastFirst.value),
                firstLbl + IntegerToString(lastLegN), InpColorFirst, g_bull);
      DrawLabel(PFX + secondLbl, T[lastSecond.idx], ToReal(lastSecond.value),
                secondLbl + IntegerToString(lastLegN), InpColorSecond, !g_bull);
     }
   if(haveBos)
     {
      DrawRefLine(PFX + "BOSline", T[bosFromIdx], T[bosIdx], ToReal(bosLevel), InpColorBOS);
      DrawLabel(PFX + "BOS", T[bosIdx], ToReal(bosLevel), "BOS", InpColorBOS, g_bull);
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
