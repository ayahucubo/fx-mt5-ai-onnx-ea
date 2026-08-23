//+------------------------------------------------------------------+
//|                                             HV_IDM_LV_BOS.mq5    |
//|  Bullish-bias market structure: Candidate High -> IDM -> HV/LV/BOS|
//|                                                                    |
//|  Definitions (bullish bias):                                      |
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
//|  This performs bullish-bias swing detection only (a mirrored        |
//|  bearish version would swap highs/lows throughout). It has NOT      |
//|  been compiled/tested in a live MetaEditor - compile and verify on  |
//|  a chart before trusting it for anything that touches real trades.  |
//+------------------------------------------------------------------+
#property copyright "generated for fx-mt5-ai-onnx-ea"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#property strict

input int   InpSwingLength   = 2;          // Fractal swing length (bars each side)
input int   InpMaxBars       = 3000;       // How many bars back to scan
input bool  InpShowRejected  = true;       // Show rejected candidates (BCH / BIDM)
input color InpColorCH       = clrSilver;
input color InpColorBCH      = clrGray;
input color InpColorIDM      = clrOrange;
input color InpColorBIDM     = clrDarkGray;
input color InpColorHV       = clrDodgerBlue;
input color InpColorLV       = clrMagenta;
input color InpColorBOS      = clrLime;
input int   InpFontSize      = 8;

#define PFX "HVIDM_"

//--- one tracked extreme (a candidate high, a shadow/locked low, ...)
struct SExtreme
  {
   int      idx;     // bar index in the ascending (oldest->newest) arrays
   double   price;
   bool     valid;
  };

//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME, "HV/IDM/LV/BOS (bull)");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
  }

//+------------------------------------------------------------------+
void MakeExtreme(SExtreme &e, int idx, double price)
  {
   e.idx = idx; e.price = price; e.valid = true;
  }

//+------------------------------------------------------------------+
//| draw a small text label at (time[idx], price)                     |
//+------------------------------------------------------------------+
void DrawLabel(string name, datetime t, double price, string text,
               color clr, bool above)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

//+------------------------------------------------------------------+
//| draw a horizontal dotted reference line from bar t1 to bar t2      |
//+------------------------------------------------------------------+
void DrawRefLine(string name, datetime t1, datetime t2, double price, color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
     {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
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

   int start = MathMax(0, n - InpMaxBars);
   int len   = n - start;

   // work in ascending (oldest->newest) order regardless of the chart's
   // series direction, since OnCalculate already delivers arrays in
   // ascending (index 0 = oldest) order when the platform default is used.
   double H[], L[], C[];
   datetime T[];
   ArrayResize(H, len); ArrayResize(L, len);
   ArrayResize(C, len); ArrayResize(T, len);
   for(int k = 0; k < len; k++)
     {
      H[k] = high[start + k];
      L[k] = low[start + k];
      C[k] = close[start + k];
      T[k] = time[start + k];
     }

   int sl = InpSwingLength;
   bool pivotHigh[], pivotLow[];
   ArrayResize(pivotHigh, len);
   ArrayResize(pivotLow, len);
   ArrayInitialize(pivotHigh, false);
   ArrayInitialize(pivotLow, false);
   for(int i = sl; i < len - sl; i++)
     {
      bool ph = true, pl = true;
      for(int k = 1; k <= sl; k++)
        {
         if(!(H[i] > H[i - k] && H[i] > H[i + k])) ph = false;
         if(!(L[i] < L[i - k] && L[i] < L[i + k])) pl = false;
        }
      pivotHigh[i] = ph;
      pivotLow[i]  = pl;
     }

   ObjectsDeleteAll(0, PFX);

   // find the very first confirmed pivot high to seed the first candidate
   int firstIdx = -1;
   for(int i = sl; i < len - sl; i++)
      if(pivotHigh[i]) { firstIdx = i; break; }
   if(firstIdx < 0)
      return(rates_total);

   int chN = 0, idmN = 0, hvN = 0, lvN = 0, bchN = 0, bidmN = 0;

   SExtreme candidate;    MakeExtreme(candidate, firstIdx, H[firstIdx]);
   chN++;
   DrawLabel(PFX + "CH" + IntegerToString(chN), T[candidate.idx], candidate.price,
             "CH" + IntegerToString(chN), InpColorCH, true);

   SExtreme shadowLow;    shadowLow.valid = false;
   SExtreme lockedIdm;    lockedIdm.valid = false;
   SExtreme candidateLow; candidateLow.valid = false;
   SExtreme reference;    reference.valid = false;

   string phase = "seek_hv";

   for(int i = firstIdx + 1; i < len - sl; i++)
     {
      if(phase == "seek_hv")
        {
         if(pivotLow[i] && (!shadowLow.valid || L[i] < shadowLow.price))
            MakeExtreme(shadowLow, i, L[i]);

         if(InpShowRejected && pivotLow[i] && shadowLow.idx != i)
           {
            bidmN++;
            DrawLabel(PFX + "BIDM" + IntegerToString(bidmN), T[i], L[i],
                      "BIDM" + IntegerToString(bidmN), InpColorBIDM, false);
           }

         if(lockedIdm.valid && L[i] < lockedIdm.price)
           {
            hvN++;
            DrawLabel(PFX + "HV" + IntegerToString(hvN), T[candidate.idx], candidate.price,
                      "HV" + IntegerToString(hvN), InpColorHV, true);
            phase = "seek_lv";
            MakeExtreme(candidateLow, i, L[i]);
            MakeExtreme(reference, candidate.idx, candidate.price);
            continue;
           }

         if(pivotHigh[i] && H[i] > candidate.price)
           {
            if(shadowLow.valid)
              {
               idmN++;
               DrawLabel(PFX + "IDM" + IntegerToString(idmN), T[shadowLow.idx], shadowLow.price,
                         "IDM" + IntegerToString(idmN), InpColorIDM, false);
               lockedIdm = shadowLow;
              }
            MakeExtreme(candidate, i, H[i]);
            chN++;
            DrawLabel(PFX + "CH" + IntegerToString(chN), T[i], H[i],
                      "CH" + IntegerToString(chN), InpColorCH, true);
            shadowLow.valid = false;
           }
         else if(InpShowRejected && pivotHigh[i])
           {
            bchN++;
            DrawLabel(PFX + "BCH" + IntegerToString(bchN), T[i], H[i],
                      "BCH" + IntegerToString(bchN), InpColorBCH, true);
           }
        }
      else // seek_lv
        {
         if(L[i] < candidateLow.price)
            MakeExtreme(candidateLow, i, L[i]);

         if(C[i] > reference.price)
           {
            lvN++;
            DrawLabel(PFX + "LV" + IntegerToString(lvN), T[candidateLow.idx], candidateLow.price,
                      "LV" + IntegerToString(lvN), InpColorLV, false);
            DrawRefLine(PFX + "BOSline" + IntegerToString(lvN), T[reference.idx], T[i],
                        reference.price, InpColorBOS);
            DrawLabel(PFX + "BOS" + IntegerToString(lvN), T[i], C[i],
                      "BOS", InpColorBOS, true);

            phase = "seek_hv";
            MakeExtreme(candidate, i, H[i]);
            chN++;
            DrawLabel(PFX + "CH" + IntegerToString(chN), T[i], H[i],
                      "CH" + IntegerToString(chN), InpColorCH, true);
            shadowLow.valid = false;
            lockedIdm.valid = false;
           }
         else if(H[i] > reference.price)
           {
            DrawRefLine(PFX + "swap" + IntegerToString(lvN) + "_" + IntegerToString(i),
                        T[reference.idx], T[i], reference.price, InpColorBOS);
            MakeExtreme(reference, i, H[i]);
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
