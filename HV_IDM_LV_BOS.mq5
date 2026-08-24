//+------------------------------------------------------------------+
//|                                             HV_IDM_LV_BOS.mq5    |
//|  Market structure: Candidate -> IDM -> HV/LV -> BOS / CHoC       |
//|  Supports both bullish and bearish bias with auto CHoC detection.|
//|  Displays: live IDM, latest HV/LV, BOS, CHoC lines.              |
//+------------------------------------------------------------------+
#property copyright "generated for fx-mt5-ai-onnx-ea"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#property strict

enum ENUM_BIAS
  {
   BIAS_BULLISH = 0,   // Bullish
   BIAS_BEARISH = 1    // Bearish
  };

input ENUM_BIAS InpBias        = BIAS_BULLISH; // Initial Bias
input bool      InpAutoBias    = false;        // Auto-detect CHoC and flip bias dynamically (UNVERIFIED - see note below)
input bool      InpUseDateRange= false;        // Use Custom Date Range Filter (true/false)
input datetime  InpStartTime   = D'2026.01.01';// Start Time (when InpUseDateRange=true)
input datetime  InpEndTime     = D'2026.12.31';// End Time (when InpUseDateRange=true)
input int       InpSwingLength = 3;            // Fractal swing length (bars each side)
input int       InpMaxBars     = 3000;         // How many bars back to scan (when InpUseDateRange=false)
input color     InpColorIDM    = clrOrange;    // IDM (live) color
input color     InpColorFirst  = clrDodgerBlue;// First-confirmed point color (HV in bull, LV in bear)
input color     InpColorSecond = clrMagenta;   // Second-confirmed point color (LV in bull, HV in bear)
input color     InpColorBOS    = clrLime;      // BOS line color
input color     InpColorCHoC   = clrWhite;     // CHoC line and label color
input color     InpColorPending= clrAqua;      // Pending point color
input color     InpColorRangeLine = clrGray;   // Start/End vertical line color
input int       InpFontSize    = 9;

// NOTE on InpAutoBias: the CHoC/auto-bias-flip path has NOT been verified
// against real reversal data - the XAUUSD M5 reference dataset this
// indicator's core logic was validated against (test-data/ in the repo)
// never leaves bullish bias, so the bearish-flip branch and the
// CHoC-triggered-inducement-sweep branch (see the "seek_first" CHoC swap
// case in OnCalculate) are UNTESTED. Left off by default until validated
// against a real reversal. The non-CHoC core (candidate/IDM/HV/LV/BOS)
// IS verified end-to-end against that dataset.

#define PFX "HVIDM_"
#define MAX_LEGS 256
#define MAX_CHOCS 64

//--- one tracked extreme
struct SExtreme
  {
   int      idx;        // bar index in [0..len-1]
   double   value;      // transformed value (for internal state machine)
   double   realPrice;  // actual price
   bool     valid;
  };

//--- one completed leg (HV+LV confirmed together at BOS)
struct SLeg
  {
   int      firstIdx;
   double   firstPrice;
   string   firstLbl;
   int      secondIdx;
   double   secondPrice;
   string   secondLbl;
   int      legN;
   int      bosBreakIdx;
   bool     isBull;
  };

//--- one CHoC event
struct SCHoC
  {
   int      fromIdx;
   int      breakIdx;
   double   levelPrice;
   bool     toBull;
  };

SLeg   g_legs[MAX_LEGS];
int    g_nLegs;
SCHoC  g_chocs[MAX_CHOCS];
int    g_nChocs;

//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME, "HV_IDM_LV_BOS (SMC)");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
  }

//+------------------------------------------------------------------+
void MakeExtreme(SExtreme &e, int idx, double value, double realPrice)
  {
   e.idx = idx; e.value = value; e.realPrice = realPrice; e.valid = true;
  }

string g_activeObjs[];
int    g_nActiveObjs = 0;

void ResetActiveObjects()
  {
   g_nActiveObjs = 0;
   ArrayResize(g_activeObjs, 0);
  }

void RegisterActiveObject(string name)
  {
   g_nActiveObjs++;
   ArrayResize(g_activeObjs, g_nActiveObjs);
   g_activeObjs[g_nActiveObjs - 1] = name;
  }

bool IsActiveObject(string name)
  {
   for(int i = 0; i < g_nActiveObjs; i++)
      if(g_activeObjs[i] == name)
         return true;
   return false;
  }

void PurgeInactiveObjects()
  {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PFX) == 0)
        {
         if(!IsActiveObject(name))
            ObjectDelete(0, name);
        }
     }
  }

//+------------------------------------------------------------------+
//| draw a small text label at (time, realPrice)                     |
//+------------------------------------------------------------------+
void DrawLabel(string name, datetime t, double realPrice, string text,
               color clr, bool above)
  {
   RegisterActiveObject(name);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, realPrice);
   else
      ObjectMove(0, name, 0, t, realPrice);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| draw a horizontal reference line from bar t1 to bar t2           |
//+------------------------------------------------------------------+
void DrawRefLine(string name, datetime t1, datetime t2, double realPrice, color clr,
                 ENUM_LINE_STYLE style = STYLE_DOT, int width = 1)
  {
   RegisterActiveObject(name);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, realPrice, t2, realPrice);
   else
     {
      ObjectMove(0, name, 0, t1, realPrice);
      ObjectMove(0, name, 1, t2, realPrice);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| draw a vertical reference line at time t                         |
//+------------------------------------------------------------------+
void DrawVLine(string name, datetime t, color clr,
               ENUM_LINE_STYLE style = STYLE_DOT, int width = 1)
  {
   RegisterActiveObject(name);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
   else
      ObjectMove(0, name, 0, t, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Pivot check looking back/forward InpSwingLength bars             |
//+------------------------------------------------------------------+
bool IsPivotClipped(const double &high[], const double &low[], int i, int backLimit, int len, int sl, bool bull)
  {
   if(i - sl < 0 || i + sl >= len)
      return false;
   int backStart = MathMax(backLimit, i - sl);
   if(bull)
     {
      double v = low[i];
      for(int k = backStart; k < i; k++)
         if(low[k] <= v) return false;
      for(int k = i + 1; k <= i + sl; k++)
         if(low[k] <= v) return false;
     }
   else
     {
      double v = high[i];
      for(int k = backStart; k < i; k++)
         if(high[k] >= v) return false;
      for(int k = i + 1; k <= i + sl; k++)
         if(high[k] >= v) return false;
     }
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

   // determine calculation window [start .. end]
   int start = 0;
   int end   = n - 1;

   if(InpUseDateRange)
     {
      if(InpEndTime > 0)
        {
         for(int k = n - 1; k >= 0; k--)
           {
            if(time[k] <= InpEndTime)
              {
               end = k;
               break;
              }
           }
        }

      if(InpStartTime > 0)
        {
         for(int k = 0; k <= end; k++)
           {
            if(time[k] >= InpStartTime)
              {
               start = k;
               break;
              }
           }
        }
     }
   else
     {
      start = MathMax(0, end - InpMaxBars + 1);
     }

   if(end < start)
      return(rates_total);

   int len = end - start + 1;
   if(len < 2 * InpSwingLength + 5)
      return(rates_total);

   int sl = InpSwingLength;

   // State machine initialization
   bool curBull = (InpBias == BIAS_BULLISH);
   int  hvCount = 0;
   int  lvCount = 0;
   g_nLegs  = 0;
   g_nChocs = 0;

   SExtreme candidate;
   MakeExtreme(candidate, 0, curBull ? high[start] : -low[start], curBull ? high[start] : low[start]);

   SExtreme shadow;                 shadow.valid = false;
   SExtreme lockedOpp;              lockedOpp.valid = false;
   SExtreme secondPoint;            secondPoint.valid = false;
   SExtreme pendingFirst;           pendingFirst.valid = false;
   SExtreme lastStructuralSecond;   lastStructuralSecond.valid = false;
   double   chocRefPrice = 0;
   int      chocRefIdx   = -1;

   bool     haveLiveIdm = false;
   SExtreme liveIdm;                liveIdm.valid = false;

   bool     haveSweptIdm     = false;
   int      sweptIdmIdx      = -1;
   double   sweptIdmPrice    = 0;
   int      sweptIdmBreakIdx = -1;

   bool   haveBos     = false;
   int    bosHVIdx    = -1;
   double bosHVPrice  = 0;
   int    bosBreakIdx = -1;
   bool   bosIsBull   = curBull;
   double bosRefPrice = 0;

   string phase = "seek_first";

   for(int i = 1; i < len; i++)
     {
      double h = high[start + i];
      double l = low[start + i];
      double c = close[start + i];

      // 1. Check CHoC (Change of Character) & Dynamic Bias Flipping with SWAP
      if(InpAutoBias && lastStructuralSecond.valid)
        {
         bool chocTriggered = false;
         bool newBull = curBull;
         if(curBull)
           {
            if(l < chocRefPrice)
              {
               if(c < chocRefPrice)
                 {
                  // Body Break! Valid CHoC
                  chocTriggered = true;
                  newBull = false; // Bullish broken -> Flip to Bearish
                 }
               else
                 {
                  // SWAP / Wick sweep: reference is lowered to this wick low
                  chocRefPrice = l;
                  chocRefIdx   = i;

                  // If in seek_first, sweeping the previous structural level acts as an inducement sweep,
                  // confirming candidate as Valid High (HV)
                  if(phase == "seek_first")
                    {
                     hvCount++;
                     MakeExtreme(pendingFirst, candidate.idx, candidate.value, candidate.realPrice);
                     bosRefPrice = candidate.realPrice;
                     if(g_nLegs < MAX_LEGS)
                       {
                        g_legs[g_nLegs].firstIdx    = candidate.idx;
                        g_legs[g_nLegs].firstPrice  = candidate.realPrice;
                        g_legs[g_nLegs].firstLbl    = "HV" + IntegerToString(hvCount);
                        g_legs[g_nLegs].secondIdx   = -1;
                        g_legs[g_nLegs].secondPrice = 0;
                        g_legs[g_nLegs].secondLbl   = "";
                        g_legs[g_nLegs].bosBreakIdx = i;
                        g_legs[g_nLegs].isBull      = true;
                        g_nLegs++;
                       }
                     phase = "seek_second";
                     MakeExtreme(secondPoint, i, l, l);
                     continue;
                    }
                 }
              }
           }
         else // !curBull (Bearish)
           {
            if(h > chocRefPrice)
              {
               if(c > chocRefPrice)
                 {
                  // Body Break! Valid CHoC
                  chocTriggered = true;
                  newBull = true;  // Bearish broken -> Flip to Bullish
                 }
               else
                 {
                  // SWAP / Wick sweep: reference is raised to this wick high
                  chocRefPrice = h;
                  chocRefIdx   = i;

                  // If in seek_first, sweeping the previous structural level acts as an inducement sweep,
                  // confirming candidate as Valid Low (LV)
                  if(phase == "seek_first")
                    {
                     lvCount++;
                     MakeExtreme(pendingFirst, candidate.idx, candidate.value, candidate.realPrice);
                     bosRefPrice = candidate.realPrice;
                     if(g_nLegs < MAX_LEGS)
                       {
                        g_legs[g_nLegs].firstIdx    = candidate.idx;
                        g_legs[g_nLegs].firstPrice  = candidate.realPrice;
                        g_legs[g_nLegs].firstLbl    = "LV" + IntegerToString(lvCount);
                        g_legs[g_nLegs].secondIdx   = -1;
                        g_legs[g_nLegs].secondPrice = 0;
                        g_legs[g_nLegs].secondLbl   = "";
                        g_legs[g_nLegs].bosBreakIdx = i;
                        g_legs[g_nLegs].isBull      = false;
                        g_nLegs++;
                       }
                     phase = "seek_second";
                     MakeExtreme(secondPoint, i, -h, h);
                     continue;
                    }
                 }
              }
           }

         if(chocTriggered)
           {
            if(g_nChocs < MAX_CHOCS)
              {
               g_chocs[g_nChocs].fromIdx    = lastStructuralSecond.idx;
               g_chocs[g_nChocs].breakIdx   = i;
               g_chocs[g_nChocs].levelPrice = lastStructuralSecond.realPrice;
               g_chocs[g_nChocs].toBull     = newBull;
               g_nChocs++;
              }

            curBull = newBull;
            // Find extreme point between broken level and break candle
            if(!curBull)
              {
               // Flipped from Bullish to Bearish:
               // The highest high of the bullish move is confirmed as Valid High (HV)
               int mIdx = lastStructuralSecond.idx;
               for(int k = lastStructuralSecond.idx; k <= i; k++)
                  if(high[start + k] > high[start + mIdx])
                     mIdx = k;

               hvCount++;
               if(g_nLegs < MAX_LEGS)
                 {
                  g_legs[g_nLegs].firstIdx    = mIdx;
                  g_legs[g_nLegs].firstPrice  = high[start + mIdx];
                  g_legs[g_nLegs].firstLbl    = "HV" + IntegerToString(hvCount);
                  g_legs[g_nLegs].secondIdx   = -1;
                  g_legs[g_nLegs].secondPrice = 0;
                  g_legs[g_nLegs].secondLbl   = "";
                  g_legs[g_nLegs].bosBreakIdx = i;
                  g_legs[g_nLegs].isBull      = false;
                  g_nLegs++;
                 }

               MakeExtreme(lastStructuralSecond, mIdx, -high[start + mIdx], high[start + mIdx]);
               MakeExtreme(candidate, i, -low[start + i], low[start + i]);
              }
            else
              {
               // Flipped from Bearish to Bullish:
               // The lowest low of the bearish move is confirmed as Valid Low (LV)
               int mIdx = lastStructuralSecond.idx;
               for(int k = lastStructuralSecond.idx; k <= i; k++)
                  if(low[start + k] < low[start + mIdx])
                     mIdx = k;

               lvCount++;
               if(g_nLegs < MAX_LEGS)
                 {
                  g_legs[g_nLegs].firstIdx    = mIdx;
                  g_legs[g_nLegs].firstPrice  = low[start + mIdx];
                  g_legs[g_nLegs].firstLbl    = "LV" + IntegerToString(lvCount);
                  g_legs[g_nLegs].secondIdx   = -1;
                  g_legs[g_nLegs].secondPrice = 0;
                  g_legs[g_nLegs].secondLbl   = "";
                  g_legs[g_nLegs].bosBreakIdx = i;
                  g_legs[g_nLegs].isBull      = true;
                  g_nLegs++;
                 }

               MakeExtreme(lastStructuralSecond, mIdx, low[start + mIdx], low[start + mIdx]);
               MakeExtreme(candidate, i, high[start + i], high[start + i]);
              }

            chocRefPrice       = lastStructuralSecond.realPrice;
            chocRefIdx         = lastStructuralSecond.idx;
            shadow.valid       = false;
            lockedOpp.valid    = false;
            pendingFirst.valid = false;
            secondPoint.valid  = false;
            haveLiveIdm        = false;
            liveIdm.valid      = false;
            haveSweptIdm       = false;
            sweptIdmIdx        = -1;
            sweptIdmBreakIdx   = -1;
            phase              = "seek_first";
            continue;
           }
        }

      // 2. Normal Structure Processing in Current Bias
      double currHi = curBull ? h : -l;
      double currLo = curBull ? l : -h;
      double currCl = curBull ? c : -c;
      double realLo = curBull ? l : h;
      double realHi = curBull ? h : l;

      if(phase == "seek_first")
        {
         // IDM shadow tracking
         if(IsPivotClipped(high, low, start + i, start + candidate.idx, n, sl, curBull))
           {
            if(!shadow.valid || currLo < shadow.value)
               MakeExtreme(shadow, i, currLo, realLo);
           }

         // HV / LV Confirmation (IDM Sweep)
         if(lockedOpp.valid && currLo < lockedOpp.value)
           {
            MakeExtreme(pendingFirst, candidate.idx, candidate.value, candidate.realPrice);
            bosRefPrice = candidate.realPrice;
            phase = "seek_second";
            MakeExtreme(secondPoint, i, currLo, realLo);

            sweptIdmIdx      = lockedOpp.idx;
            sweptIdmPrice    = lockedOpp.realPrice;
            sweptIdmBreakIdx = i;
            haveSweptIdm     = true;
            haveLiveIdm      = false;
            liveIdm.valid    = false;
            continue;
           }

         // Candidate update
         if(currHi > candidate.value)
           {
            if(shadow.valid)
              {
               lockedOpp   = shadow;
               liveIdm     = shadow;
               haveLiveIdm = true;
              }
            MakeExtreme(candidate, i, currHi, realHi);
            shadow.valid = false;
           }
        }
      else // seek_second
        {
         // Track second point (running extreme after confirmed point)
         if(!secondPoint.valid || currLo < secondPoint.value)
            MakeExtreme(secondPoint, i, currLo, realLo);

         // BOS Confirmation with SWAP Ratcheting
         bool bosTriggered = false;
         if(curBull)
           {
            if(h > bosRefPrice)
              {
               if(c > bosRefPrice)
                  bosTriggered = true;
               else
                  bosRefPrice = h; // BOS SWAP: Ratchet reference higher!
              }
           }
         else // Bearish
           {
            if(l < bosRefPrice)
              {
               if(c < bosRefPrice)
                  bosTriggered = true;
               else
                  bosRefPrice = l; // BOS SWAP: Ratchet reference lower!
              }
           }

         if(bosTriggered)
           {
            if(curBull)
              {
               hvCount++;
               lvCount++;
               if(g_nLegs < MAX_LEGS)
                 {
                  g_legs[g_nLegs].firstIdx    = pendingFirst.idx;
                  g_legs[g_nLegs].firstPrice  = pendingFirst.realPrice;
                  g_legs[g_nLegs].firstLbl    = "HV" + IntegerToString(hvCount);
                  g_legs[g_nLegs].secondIdx   = secondPoint.idx;
                  g_legs[g_nLegs].secondPrice = secondPoint.realPrice;
                  g_legs[g_nLegs].secondLbl   = "LV" + IntegerToString(lvCount);
                  g_legs[g_nLegs].bosBreakIdx = i;
                  g_legs[g_nLegs].isBull      = curBull;
                  g_nLegs++;
                 }
              }
            else
              {
               lvCount++;
               hvCount++;
               if(g_nLegs < MAX_LEGS)
                 {
                  g_legs[g_nLegs].firstIdx    = pendingFirst.idx;
                  g_legs[g_nLegs].firstPrice  = pendingFirst.realPrice;
                  g_legs[g_nLegs].firstLbl    = "LV" + IntegerToString(lvCount);
                  g_legs[g_nLegs].secondIdx   = secondPoint.idx;
                  g_legs[g_nLegs].secondPrice = secondPoint.realPrice;
                  g_legs[g_nLegs].secondLbl   = "HV" + IntegerToString(hvCount);
                  g_legs[g_nLegs].bosBreakIdx = i;
                  g_legs[g_nLegs].isBull      = curBull;
                  g_nLegs++;
                 }
              }

            lastStructuralSecond = secondPoint;
            chocRefPrice         = secondPoint.realPrice;
            chocRefIdx           = secondPoint.idx;
            bosHVIdx    = pendingFirst.idx;
            bosHVPrice  = pendingFirst.realPrice;
            bosBreakIdx = i;
            bosIsBull   = curBull;
            haveBos     = true;
            phase = "seek_first";

            // Set candidate to the true extreme (maximum high / minimum low) across the impulse wave
            int    candIdx  = i;
            double candVal  = currHi;
            double candReal = realHi;
            for(int k = secondPoint.idx + 1; k <= i; k++)
              {
               double kVal  = curBull ? high[start + k] : -low[start + k];
               double kReal = curBull ? high[start + k] : low[start + k];
               if(kVal > candVal)
                 {
                  candVal  = kVal;
                  candReal = kReal;
                  candIdx  = k;
                 }
              }
            MakeExtreme(candidate, candIdx, candVal, candReal);
            shadow.valid       = false;
            lockedOpp.valid    = false;
            pendingFirst.valid = false;
            haveLiveIdm        = false;
            liveIdm.valid      = false;

            // Scan impulse wave from secondPoint.idx to i (BOS break) for pullbacks
            for(int k = secondPoint.idx + 1; k < i; k++)
              {
               if(IsPivotClipped(high, low, start + k, start + secondPoint.idx, n, sl, curBull))
                 {
                  double kVal  = curBull ? low[start + k] : -high[start + k];
                  double kReal = curBull ? low[start + k] : high[start + k];
                  if(!shadow.valid || kVal < shadow.value)
                     MakeExtreme(shadow, k, kVal, kReal);
                 }
              }

            if(shadow.valid)
              {
               lockedOpp    = shadow;
               liveIdm      = shadow;
               haveLiveIdm  = true;
               shadow.valid = false;
              }
           }
        }
     }

   // ----------------------------------------------------------------
   // Draw Section (Anti-Flicker in-place updates)
   // ----------------------------------------------------------------
   ResetActiveObjects();

   datetime tNow = time[start + len - 1];

   // 0. Draw Start / End Time Vertical Boundaries
   if(InpUseDateRange)
     {
      if(InpStartTime > 0)
         DrawVLine(PFX + "StartVLine", time[start], InpColorRangeLine, STYLE_DOT, 1);
      if(InpEndTime > 0)
         DrawVLine(PFX + "EndVLine", time[end], InpColorRangeLine, STYLE_DOT, 1);
     }

   // 1. Draw CHoC Lines & Labels
   for(int c = 0; c < g_nChocs; c++)
     {
      int fromIdx  = g_chocs[c].fromIdx;
      int breakIdx = g_chocs[c].breakIdx;
      int midIdx   = fromIdx + (breakIdx - fromIdx) / 2;

      datetime tStart = time[start + fromIdx];
      datetime tEnd   = time[start + breakIdx];
      datetime tMid   = time[start + midIdx];
      DrawRefLine(PFX + "CHoC_L_" + IntegerToString(c), tStart, tEnd, g_chocs[c].levelPrice, InpColorCHoC, STYLE_SOLID, 2);
      DrawLabel(PFX + "CHoC_" + IntegerToString(c), tMid, g_chocs[c].levelPrice, "CHoC", InpColorCHoC, g_chocs[c].toBull);
     }

   // 2. Completed Legs (Last up-to 10 legs)
   int drawFrom = MathMax(0, g_nLegs - 10);
   for(int k = drawFrom; k < g_nLegs; k++)
     {
      int scanFrom = g_legs[k].bosBreakIdx + 1;

      // First Point Label (HV is always Blue above candle, LV is always Magenta below candle)
      if(StringFind(g_legs[k].firstLbl, "HV") >= 0)
         DrawLabel(PFX + g_legs[k].firstLbl, time[start + g_legs[k].firstIdx], g_legs[k].firstPrice,
                   g_legs[k].firstLbl, InpColorFirst, true);
      else
         DrawLabel(PFX + g_legs[k].firstLbl, time[start + g_legs[k].firstIdx], g_legs[k].firstPrice,
                   g_legs[k].firstLbl, InpColorSecond, false);

      // Second Point Label & Line (only if valid second point exists)
      if(g_legs[k].secondIdx >= 0 && g_legs[k].secondLbl != "")
        {
         if(StringFind(g_legs[k].secondLbl, "HV") >= 0)
            DrawLabel(PFX + g_legs[k].secondLbl, time[start + g_legs[k].secondIdx], g_legs[k].secondPrice,
                      g_legs[k].secondLbl, InpColorFirst, true);
         else
            DrawLabel(PFX + g_legs[k].secondLbl, time[start + g_legs[k].secondIdx], g_legs[k].secondPrice,
                      g_legs[k].secondLbl, InpColorSecond, false);

         // Mitigation Check
         bool lvMitigated = false;
         for(int j = scanFrom; j < len && !lvMitigated; j++)
           {
            if(StringFind(g_legs[k].secondLbl, "LV") >= 0 && close[start + j] < g_legs[k].secondPrice)
               lvMitigated = true;
            else if(StringFind(g_legs[k].secondLbl, "HV") >= 0 && close[start + j] > g_legs[k].secondPrice)
               lvMitigated = true;
           }

         // Second Point Line (if unmitigated)
         if(!lvMitigated)
           {
            color lineClr = (StringFind(g_legs[k].secondLbl, "LV") >= 0) ? InpColorSecond : InpColorFirst;
            DrawRefLine(PFX + g_legs[k].secondLbl + "L", time[start + g_legs[k].secondIdx], tNow,
                        g_legs[k].secondPrice, lineClr, STYLE_DOT, 1);
           }
        }
     }

   // 3. Latest BOS Line & Label
   if(haveBos && bosHVIdx >= 0 && bosBreakIdx >= 0 && bosBreakIdx < len)
     {
      int midIdx = bosHVIdx + (bosBreakIdx - bosHVIdx) / 2;
      datetime tBosStart = time[start + bosHVIdx];
      datetime tBosEnd   = time[start + bosBreakIdx];
      datetime tBosMid   = time[start + midIdx];
      DrawRefLine(PFX + "BOSline", tBosStart, tBosEnd, bosHVPrice, InpColorBOS, STYLE_DOT, 1);
      DrawLabel(PFX + "BOS", tBosMid, bosHVPrice, "BOS", InpColorBOS, bosIsBull);
     }

   // 4. IDM Line & Label
   if(haveLiveIdm && liveIdm.valid)
     {
      // Live IDM waiting to be swept -> extends to right edge (tNow)
      DrawRefLine(PFX + "IDMline", time[start + liveIdm.idx], tNow, liveIdm.realPrice, InpColorIDM, STYLE_DOT, 1);
      DrawLabel(PFX + "IDM", time[start + liveIdm.idx], liveIdm.realPrice,
                "IDM", InpColorIDM, !curBull);
     }
   else if(haveSweptIdm && sweptIdmIdx >= 0 && sweptIdmBreakIdx >= 0 && sweptIdmBreakIdx < len)
     {
      // Swept IDM -> stops at the sweep/break candle
      datetime tIdmStart = time[start + sweptIdmIdx];
      datetime tIdmEnd   = time[start + sweptIdmBreakIdx];
      DrawRefLine(PFX + "IDMline", tIdmStart, tIdmEnd, sweptIdmPrice, InpColorIDM, STYLE_DOT, 1);
      DrawLabel(PFX + "IDM", tIdmStart, sweptIdmPrice,
                "IDM", InpColorIDM, !curBull);
     }

   // 5. Pending Point (HV pending in bull, LV pending in bear)
   if(phase == "seek_second" && pendingFirst.valid)
     {
      string pLbl = curBull ? "HV (pending)" : "LV (pending)";
      DrawRefLine(PFX + "PendLine", time[start + pendingFirst.idx], tNow,
                  pendingFirst.realPrice, InpColorPending, STYLE_DOT, 1);
      DrawLabel(PFX + "PendLbl", time[start + pendingFirst.idx], pendingFirst.realPrice,
                pLbl, InpColorPending, curBull);
     }

   PurgeInactiveObjects();
   ChartRedraw(0);
   return(rates_total);
  }
//+------------------------------------------------------------------+
