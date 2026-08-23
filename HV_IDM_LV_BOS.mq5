//+------------------------------------------------------------------+
//|                                             HV_IDM_LV_BOS.mq5    |
//|  Market structure: Candidate -> IDM -> HV/LV -> BOS               |
//|  Supports both bullish and bearish bias (InpBias).                 |
//|                                                                    |
//|  Definitions, written for the BULLISH case (InpBias=Bullish). The  |
//|  BEARISH case is the exact mirror: swap every "high" for "low" and |
//|  vice versa; CH (Calon High) becomes CL (Calon Low); the point      |
//|  confirmed first is LV instead of HV, and the point confirmed        |
//|  second is HV instead of LV.                                        |
//|                                                                    |
//|   CH  (Calon High)   - a fractal swing-high candidate. It becomes  |
//|                         the active candidate whenever its price     |
//|                         is higher than the currently active one     |
//|                         (a lower fractal high is drawn as BCH).      |
//|   IDM (Inducement)   - the lowest fractal swing-low since the       |
//|                         active candidate's last update. It is       |
//|                         LOCKED IN (becomes the operative IDM,        |
//|                         replacing whatever was locked before) the   |
//|                         moment the candidate updates to a new,       |
//|                         higher high. Only the most recently locked  |
//|                         IDM is ever checked for a swap - older ones |
//|                         stop mattering the instant a newer one      |
//|                         locks in (a lower fractal low that never    |
//|                         gets locked is drawn as BIDM).               |
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
input int       InpSwingLength = 2;            // Fractal swing length (bars each side)
input int       InpMaxBars     = 3000;         // How many bars back to scan (used when InpStartTime=0)
input bool      InpShowRejected= true;         // Show rejected candidates (BCH/BCL & BIDM)
input color     InpColorCand   = clrSilver;    // Candidate (CH/CL) color
input color     InpColorBCand  = clrGray;      // Rejected candidate (BCH/BCL) color
input color     InpColorIDM    = clrOrange;    // IDM color
input color     InpColorBIDM   = clrDarkGray;  // Rejected IDM (BIDM) color
input color     InpColorFirst  = clrDodgerBlue;// First-confirmed point color (HV in bull, LV in bear)
input color     InpColorSecond = clrMagenta;   // Second-confirmed point color (LV in bull, HV in bear)
input color     InpColorBOS    = clrLime;      // BOS / reference line color
input int       InpFontSize    = 8;

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
   bool pivotCand[], pivotOpp[];
   ArrayResize(pivotCand, len);
   ArrayResize(pivotOpp, len);
   ArrayInitialize(pivotCand, false);
   ArrayInitialize(pivotOpp, false);
   for(int i = sl; i < len - sl; i++)
     {
      bool pc = true, po = true;
      for(int k = 1; k <= sl; k++)
        {
         if(!(Hi[i] > Hi[i - k] && Hi[i] > Hi[i + k])) pc = false;
         if(!(Lo[i] < Lo[i - k] && Lo[i] < Lo[i + k])) po = false;
        }
      pivotCand[i] = pc;
      pivotOpp[i]  = po;
     }

   ObjectsDeleteAll(0, PFX);

   string candLbl  = g_bull ? "CH"   : "CL";
   string bcandLbl = g_bull ? "BCH"  : "BCL";
   string firstLbl = g_bull ? "HV"   : "LV";
   string secondLbl= g_bull ? "LV"   : "HV";

   // find the very first confirmed pivot candidate to seed tracking
   int firstIdx = -1;
   for(int i = sl; i < len - sl; i++)
      if(pivotCand[i]) { firstIdx = i; break; }
   if(firstIdx < 0)
      return(rates_total);

   int candN = 0, idmN = 0, firstN = 0, secondN = 0, bcandN = 0, bidmN = 0;

   SExtreme candidate;    MakeExtreme(candidate, firstIdx, Hi[firstIdx]);
   candN++;
   DrawLabel(PFX + candLbl + IntegerToString(candN), T[candidate.idx], ToReal(candidate.value),
             candLbl + IntegerToString(candN), InpColorCand, g_bull);

   SExtreme shadow;       shadow.valid = false;
   SExtreme lockedOpp;    lockedOpp.valid = false;
   SExtreme secondPoint;  secondPoint.valid = false;
   SExtreme reference;    reference.valid = false;

   string phase = "seek_first";

   for(int i = firstIdx + 1; i < len - sl; i++)
     {
      if(phase == "seek_first")
        {
         if(pivotOpp[i] && (!shadow.valid || Lo[i] < shadow.value))
            MakeExtreme(shadow, i, Lo[i]);

         if(InpShowRejected && pivotOpp[i] && shadow.idx != i)
           {
            bidmN++;
            DrawLabel(PFX + "BIDM" + IntegerToString(bidmN), T[i], ToReal(Lo[i]),
                      "BIDM" + IntegerToString(bidmN), InpColorBIDM, !g_bull);
           }

         if(lockedOpp.valid && Lo[i] < lockedOpp.value)
           {
            firstN++;
            DrawLabel(PFX + firstLbl + IntegerToString(firstN), T[candidate.idx], ToReal(candidate.value),
                      firstLbl + IntegerToString(firstN), InpColorFirst, g_bull);
            phase = "seek_second";
            MakeExtreme(secondPoint, i, Lo[i]);
            MakeExtreme(reference, candidate.idx, candidate.value);
            continue;
           }

         if(pivotCand[i] && Hi[i] > candidate.value)
           {
            if(shadow.valid)
              {
               idmN++;
               DrawLabel(PFX + "IDM" + IntegerToString(idmN), T[shadow.idx], ToReal(shadow.value),
                         "IDM" + IntegerToString(idmN), InpColorIDM, !g_bull);
               lockedOpp = shadow;
              }
            MakeExtreme(candidate, i, Hi[i]);
            candN++;
            DrawLabel(PFX + candLbl + IntegerToString(candN), T[i], ToReal(Hi[i]),
                      candLbl + IntegerToString(candN), InpColorCand, g_bull);
            shadow.valid = false;
           }
         else if(InpShowRejected && pivotCand[i])
           {
            bcandN++;
            DrawLabel(PFX + bcandLbl + IntegerToString(bcandN), T[i], ToReal(Hi[i]),
                      bcandLbl + IntegerToString(bcandN), InpColorBCand, g_bull);
           }
        }
      else // seek_second
        {
         if(Lo[i] < secondPoint.value)
            MakeExtreme(secondPoint, i, Lo[i]);

         if(Cl[i] > reference.value)
           {
            secondN++;
            DrawLabel(PFX + secondLbl + IntegerToString(secondN), T[secondPoint.idx], ToReal(secondPoint.value),
                      secondLbl + IntegerToString(secondN), InpColorSecond, !g_bull);
            DrawRefLine(PFX + "BOSline" + IntegerToString(secondN), T[reference.idx], T[i],
                        ToReal(reference.value), InpColorBOS);
            DrawLabel(PFX + "BOS" + IntegerToString(secondN), T[i], ToReal(Cl[i]),
                      "BOS", InpColorBOS, g_bull);

            phase = "seek_first";
            MakeExtreme(candidate, i, Hi[i]);
            candN++;
            DrawLabel(PFX + candLbl + IntegerToString(candN), T[i], ToReal(Hi[i]),
                      candLbl + IntegerToString(candN), InpColorCand, g_bull);
            shadow.valid = false;
            lockedOpp.valid = false;
           }
         else if(Hi[i] > reference.value)
           {
            DrawRefLine(PFX + "swap" + IntegerToString(secondN) + "_" + IntegerToString(i),
                        T[reference.idx], T[i], ToReal(reference.value), InpColorBOS);
            MakeExtreme(reference, i, Hi[i]);
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
