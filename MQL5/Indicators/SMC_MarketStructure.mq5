//+------------------------------------------------------------------+
//| SMC_MarketStructure.mq5                                          |
//|                                                                  |
//| Menandai struktur market ala SMC/ICT: HH/LH/HL/LL yang VALID,    |
//| inducement (internal liquidity sweep), dan BOS (Break of         |
//| Structure) terakhir.                                             |
//|                                                                  |
//| Rule yang di-encode (bullish; bearish adalah cerminnya):          |
//|  1. Swing high/low dideteksi via fractal N-bar (kiri & kanan).   |
//|  2. "High valid"  = swing high yang inducement (internal low     |
//|     setelahnya) berhasil di-sweep oleh wick (low candle > later  |
//|     menembus di bawah level inducement).                        |
//|  3. "Low valid"   = low terendah antara bar sweep sampai bar     |
//|     BOS (body close di atas high valid). Kalau tidak ada         |
//|     pullback tambahan, ini sama dengan titik inducement itu      |
//|     sendiri.                                                    |
//|  4. HH/LH dan HL/LL ditentukan relatif terhadap high/low valid   |
//|     tervalidasi SEBELUMNYA.                                     |
//|  5. Hanya bar yang sudah close yang diproses (hindari repaint    |
//|     akibat harga intrabar); indikator full-recompute tiap        |
//|     panggilan OnCalculate demi correctness, bukan performa.      |
//|  6. Order Block (POI) = candle berlawanan warna TERAKHIR di      |
//|     dalam leg impulsif (dari titik inducement sampai bar BOS)    |
//|     sebelum leg itu menutup dengan BOS. Zona = high-low candle   |
//|     tsb (bukan cuma body). Fallback ke titik low/high valid      |
//|     kalau tidak ada candle berlawanan warna di leg itu.          |
//|  7. FVG = imbalance 3-candle standar di dalam leg yang sama      |
//|     (low candle-3 > high candle-1 untuk bullish, kebalikannya    |
//|     untuk bearish).                                              |
//|  8. Mitigasi = begitu ada candle SETELAHNYA yang wick-nya balik  |
//|     masuk ke zona (OB/FVG) tsb -- tidak perlu body close.        |
//|     Zona termitigasi digambar abu-abu, yang masih aktif diberi   |
//|     warna solid.                                                 |
//+------------------------------------------------------------------+
#property copyright "fx-mt5-ai-onnx-ea"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 11
#property indicator_plots   11
#property indicator_label1  "HH"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "LH"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "HL"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "LL"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "Inducement"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "BOSDirection"
#property indicator_type6   DRAW_NONE
#property indicator_label7  "BOSLevel"
#property indicator_type7   DRAW_NONE
#property indicator_label8  "OBTop"
#property indicator_type8   DRAW_NONE
#property indicator_label9  "OBBottom"
#property indicator_type9   DRAW_NONE
#property indicator_label10 "FVGTop"
#property indicator_type10  DRAW_NONE
#property indicator_label11 "FVGBottom"
#property indicator_type11  DRAW_NONE

input int   InpSwingBars        = 2;     // Jumlah bar kiri/kanan untuk deteksi fractal swing
input bool  InpUseOnlyClosedBars = true;  // Hanya proses bar yang sudah close (hindari repaint)
input bool  InpShowOB            = true;  // Tampilkan Order Block (POI)
input bool  InpShowFVG           = true;  // Tampilkan Fair Value Gap
input bool  InpCompactMode       = true;  // Mode simpel: simbol/huruf tunggal, tanpa teks panjang
input int   InpLabelFontSize     = 7;     // Ukuran font label
input color InpColorHH          = clrLime;
input color InpColorLH           = clrOrange;
input color InpColorHL           = clrDeepSkyBlue;
input color InpColorLL           = clrRed;
input color InpColorIDM          = clrYellow;
input color InpColorBOSUp        = clrLime;
input color InpColorBOSDown      = clrRed;
input color InpColorOBBull       = clrDeepSkyBlue;
input color InpColorOBBear       = clrOrange;
input color InpColorFVGBull      = clrAqua;
input color InpColorFVGBear      = clrMagenta;
input color InpColorMitigated    = clrGray;

double bufHH[];
double bufLH[];
double bufHL[];
double bufLL[];
double bufIDM[];
double bufBOSDir[];
double bufBOSLevel[];
double bufOBTop[];
double bufOBBottom[];
double bufFVGTop[];
double bufFVGBottom[];

#define OBJ_PREFIX "SMCMS_"

struct SPivot
{
   bool   isHigh;
   double price;
   int    idx;
};

int OnInit()
{
   SetIndexBuffer(0, bufHH,      INDICATOR_DATA);
   SetIndexBuffer(1, bufLH,      INDICATOR_DATA);
   SetIndexBuffer(2, bufHL,      INDICATOR_DATA);
   SetIndexBuffer(3, bufLL,      INDICATOR_DATA);
   SetIndexBuffer(4, bufIDM,     INDICATOR_DATA);
   SetIndexBuffer(5, bufBOSDir,  INDICATOR_DATA);
   SetIndexBuffer(6, bufBOSLevel,INDICATOR_DATA);
   SetIndexBuffer(7, bufOBTop,     INDICATOR_DATA);
   SetIndexBuffer(8, bufOBBottom,  INDICATOR_DATA);
   SetIndexBuffer(9, bufFVGTop,    INDICATOR_DATA);
   SetIndexBuffer(10,bufFVGBottom, INDICATOR_DATA);

   for(int i = 0; i < 11; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "SMC Market Structure");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
}

bool IsFractalHigh(const double &high[], int i, int n, int lastBar)
{
   if(i - n < 0 || i + n > lastBar) return false;
   for(int k = 1; k <= n; k++)
      if(high[i-k] >= high[i] || high[i+k] >= high[i]) return false;
   return true;
}

bool IsFractalLow(const double &low[], int i, int n, int lastBar)
{
   if(i - n < 0 || i + n > lastBar) return false;
   for(int k = 1; k <= n; k++)
      if(low[i-k] <= low[i] || low[i+k] <= low[i]) return false;
   return true;
}

void DrawLabel(datetime t, double price, string text, color clr, bool above)
{
   // Ambil huruf KEDUA ("HH"/"LH" -> "H", "HL"/"LL" -> "L") supaya compact text
   // menunjukkan tipe pivot (high/low); perbandingan naik/turunnya tetap dibawa oleh warna.
   string shown = InpCompactMode ? StringSubstr(text, 1, 1) : text;
   string name = OBJ_PREFIX + "LBL_" + (string)t + "_" + text;
   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, shown);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpLabelFontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
}

void DrawInducement(datetime t, double price)
{
   string name = OBJ_PREFIX + "IDM_" + (string)t;
   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, InpCompactMode ? "." : "IDM");
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpColorIDM);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpCompactMode ? InpLabelFontSize + 4 : InpLabelFontSize);
}

void DrawBOS(datetime tFrom, datetime tTo, double price, int dir)
{
   string lname = OBJ_PREFIX + "BOSLINE_" + (string)tTo;
   ObjectCreate(0, lname, OBJ_TREND, 0, tFrom, price, tTo, price);
   ObjectSetInteger(0, lname, OBJPROP_COLOR, dir > 0 ? InpColorBOSUp : InpColorBOSDown);
   ObjectSetInteger(0, lname, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lname, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, lname, OBJPROP_WIDTH, 1);

   if(!InpCompactMode)
   {
      string txt = OBJ_PREFIX + "BOSLBL_" + (string)tTo;
      ObjectCreate(0, txt, OBJ_TEXT, 0, tTo, price);
      ObjectSetString(0, txt, OBJPROP_TEXT, dir > 0 ? "BOS UP" : "BOS DOWN");
      ObjectSetInteger(0, txt, OBJPROP_COLOR, dir > 0 ? InpColorBOSUp : InpColorBOSDown);
      ObjectSetInteger(0, txt, OBJPROP_FONTSIZE, InpLabelFontSize);
   }
}

int FindLastBearishBar(const double &open[], const double &close[], int fromIdx, int toIdx)
{
   int found = -1;
   for(int b = fromIdx; b <= toIdx; b++)
      if(close[b] < open[b]) found = b;
   return found;
}

int FindLastBullishBar(const double &open[], const double &close[], int fromIdx, int toIdx)
{
   int found = -1;
   for(int b = fromIdx; b <= toIdx; b++)
      if(close[b] > open[b]) found = b;
   return found;
}

void DrawZone(string name, datetime t1, double top, datetime t2, double bottom, color clr, string label)
{
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);

   if(!InpCompactMode)
   {
      string txt = name + "_LBL";
      ObjectCreate(0, txt, OBJ_TEXT, 0, t1, top);
      ObjectSetString(0, txt, OBJPROP_TEXT, label);
      ObjectSetInteger(0, txt, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, txt, OBJPROP_FONTSIZE, InpLabelFontSize);
      ObjectSetInteger(0, txt, OBJPROP_ANCHOR, ANCHOR_LOWER);
   }
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
   int n = MathMax(1, InpSwingBars);
   int lastBar = InpUseOnlyClosedBars ? rates_total - 2 : rates_total - 1;
   if(lastBar < 2 * n + 2)
      return rates_total;

   for(int i = 0; i < rates_total; i++)
   {
      bufHH[i] = EMPTY_VALUE;
      bufLH[i] = EMPTY_VALUE;
      bufHL[i] = EMPTY_VALUE;
      bufLL[i] = EMPTY_VALUE;
      bufIDM[i] = EMPTY_VALUE;
      bufBOSDir[i] = EMPTY_VALUE;
      bufBOSLevel[i] = EMPTY_VALUE;
      bufOBTop[i] = EMPTY_VALUE;
      bufOBBottom[i] = EMPTY_VALUE;
      bufFVGTop[i] = EMPTY_VALUE;
      bufFVGBottom[i] = EMPTY_VALUE;
   }
   ObjectsDeleteAll(0, OBJ_PREFIX);

   // --- Step 1: reduce fractals to an alternating pivot sequence ---
   SPivot pivots[];
   int pivotCount = 0;
   int lastType = 0; // 0 none, 1 high, -1 low

   for(int i = n; i <= lastBar - n; i++)
   {
      if(IsFractalHigh(high, i, n, lastBar))
      {
         if(lastType == 1)
         {
            if(high[i] > pivots[pivotCount-1].price)
            {
               pivots[pivotCount-1].price = high[i];
               pivots[pivotCount-1].idx = i;
            }
         }
         else
         {
            ArrayResize(pivots, pivotCount + 1);
            pivots[pivotCount].isHigh = true;
            pivots[pivotCount].price = high[i];
            pivots[pivotCount].idx = i;
            pivotCount++;
            lastType = 1;
         }
      }
      if(IsFractalLow(low, i, n, lastBar))
      {
         if(lastType == -1)
         {
            if(low[i] < pivots[pivotCount-1].price)
            {
               pivots[pivotCount-1].price = low[i];
               pivots[pivotCount-1].idx = i;
            }
         }
         else
         {
            ArrayResize(pivots, pivotCount + 1);
            pivots[pivotCount].isHigh = false;
            pivots[pivotCount].price = low[i];
            pivots[pivotCount].idx = i;
            pivotCount++;
            lastType = -1;
         }
      }
   }

   // --- Step 2: validate via inducement sweep + BOS, classify HH/LH/HL/LL ---
   bool haveLastValidHigh = false; double lastValidHighPrice = 0;
   bool haveLastValidLow  = false; double lastValidLowPrice  = 0;
   int lastBOSDir = 0; double lastBOSLevel = 0; datetime lastBOSTime = 0;

   for(int p = 0; p < pivotCount - 1; p++)
   {
      if(pivots[p].isHigh && !pivots[p+1].isHigh)
      {
         // Bullish path: swing high, then internal pullback low (inducement candidate)
         int idmIdx = pivots[p+1].idx;
         double idmPrice = pivots[p+1].price;

         int sweepBar = -1;
         for(int b = idmIdx + 1; b <= lastBar; b++)
            if(low[b] < idmPrice) { sweepBar = b; break; }
         if(sweepBar == -1) continue; // inducement not swept yet

         bool isHH = !haveLastValidHigh || pivots[p].price > lastValidHighPrice;
         if(isHH) bufHH[pivots[p].idx] = pivots[p].price;
         else     bufLH[pivots[p].idx] = pivots[p].price;
         DrawLabel(time[pivots[p].idx], pivots[p].price, isHH ? "HH" : "LH", isHH ? InpColorHH : InpColorLH, true);
         haveLastValidHigh = true;
         lastValidHighPrice = pivots[p].price;

         bufIDM[idmIdx] = idmPrice;
         DrawInducement(time[idmIdx], idmPrice);

         double runLow = idmPrice; int runLowIdx = idmIdx;
         int bosBar = -1;
         for(int b = idmIdx; b <= lastBar; b++)
         {
            if(low[b] < runLow) { runLow = low[b]; runLowIdx = b; }
            if(close[b] > pivots[p].price) { bosBar = b; break; }
         }
         if(bosBar != -1)
         {
            bool isHL = !haveLastValidLow || runLow > lastValidLowPrice;
            if(isHL) bufHL[runLowIdx] = runLow;
            else     bufLL[runLowIdx] = runLow;
            DrawLabel(time[runLowIdx], runLow, isHL ? "HL" : "LL", isHL ? InpColorHL : InpColorLL, false);
            haveLastValidLow = true;
            lastValidLowPrice = runLow;

            bufBOSDir[bosBar] = 1;
            bufBOSLevel[bosBar] = pivots[p].price;
            DrawBOS(time[pivots[p].idx], time[bosBar], pivots[p].price, 1);
            lastBOSDir = 1; lastBOSLevel = pivots[p].price; lastBOSTime = time[bosBar];

            if(InpShowOB)
            {
               int obIdx = FindLastBearishBar(open, close, idmIdx, bosBar - 1);
               if(obIdx == -1) obIdx = runLowIdx;
               double obTop = high[obIdx];
               double obBottom = low[obIdx];
               bufOBTop[obIdx] = obTop;
               bufOBBottom[obIdx] = obBottom;

               int mitBar = -1;
               for(int b = obIdx + 1; b <= lastBar; b++)
                  if(low[b] <= obTop) { mitBar = b; break; }
               datetime tEnd = (mitBar != -1) ? time[mitBar] : time[lastBar];
               color obClr = (mitBar != -1) ? InpColorMitigated : InpColorOBBull;
               DrawZone(OBJ_PREFIX + "OB_" + (string)time[obIdx], time[obIdx], obTop, tEnd, obBottom, obClr, "OB");
            }

            if(InpShowFVG)
            {
               for(int b = idmIdx + 1; b < bosBar; b++)
               {
                  if(low[b+1] > high[b-1])
                  {
                     double fvgTop = low[b+1];
                     double fvgBottom = high[b-1];
                     bufFVGTop[b] = fvgTop;
                     bufFVGBottom[b] = fvgBottom;

                     int mitBar2 = -1;
                     for(int c = b + 1; c <= lastBar; c++)
                        if(low[c] <= fvgTop) { mitBar2 = c; break; }
                     datetime tEnd2 = (mitBar2 != -1) ? time[mitBar2] : time[lastBar];
                     color fvgClr = (mitBar2 != -1) ? InpColorMitigated : InpColorFVGBull;
                     DrawZone(OBJ_PREFIX + "FVG_" + (string)time[b], time[b-1], fvgTop, tEnd2, fvgBottom, fvgClr, "FVG");
                  }
               }
            }
         }
      }
      else if(!pivots[p].isHigh && pivots[p+1].isHigh)
      {
         // Bearish path: swing low, then internal pullback high (inducement candidate)
         int idmIdx = pivots[p+1].idx;
         double idmPrice = pivots[p+1].price;

         int sweepBar = -1;
         for(int b = idmIdx + 1; b <= lastBar; b++)
            if(high[b] > idmPrice) { sweepBar = b; break; }
         if(sweepBar == -1) continue;

         bool isLL = !haveLastValidLow || pivots[p].price < lastValidLowPrice;
         if(isLL) bufLL[pivots[p].idx] = pivots[p].price;
         else     bufHL[pivots[p].idx] = pivots[p].price;
         DrawLabel(time[pivots[p].idx], pivots[p].price, isLL ? "LL" : "HL", isLL ? InpColorLL : InpColorHL, false);
         haveLastValidLow = true;
         lastValidLowPrice = pivots[p].price;

         bufIDM[idmIdx] = idmPrice;
         DrawInducement(time[idmIdx], idmPrice);

         double runHigh = idmPrice; int runHighIdx = idmIdx;
         int bosBar = -1;
         for(int b = idmIdx; b <= lastBar; b++)
         {
            if(high[b] > runHigh) { runHigh = high[b]; runHighIdx = b; }
            if(close[b] < pivots[p].price) { bosBar = b; break; }
         }
         if(bosBar != -1)
         {
            bool isLH = !haveLastValidHigh || runHigh < lastValidHighPrice;
            if(isLH) bufLH[runHighIdx] = runHigh;
            else     bufHH[runHighIdx] = runHigh;
            DrawLabel(time[runHighIdx], runHigh, isLH ? "LH" : "HH", isLH ? InpColorLH : InpColorHH, true);
            haveLastValidHigh = true;
            lastValidHighPrice = runHigh;

            bufBOSDir[bosBar] = -1;
            bufBOSLevel[bosBar] = pivots[p].price;
            DrawBOS(time[pivots[p].idx], time[bosBar], pivots[p].price, -1);
            lastBOSDir = -1; lastBOSLevel = pivots[p].price; lastBOSTime = time[bosBar];

            if(InpShowOB)
            {
               int obIdx = FindLastBullishBar(open, close, idmIdx, bosBar - 1);
               if(obIdx == -1) obIdx = runHighIdx;
               double obTop = high[obIdx];
               double obBottom = low[obIdx];
               bufOBTop[obIdx] = obTop;
               bufOBBottom[obIdx] = obBottom;

               int mitBar = -1;
               for(int b = obIdx + 1; b <= lastBar; b++)
                  if(high[b] >= obBottom) { mitBar = b; break; }
               datetime tEnd = (mitBar != -1) ? time[mitBar] : time[lastBar];
               color obClr = (mitBar != -1) ? InpColorMitigated : InpColorOBBear;
               DrawZone(OBJ_PREFIX + "OB_" + (string)time[obIdx], time[obIdx], obTop, tEnd, obBottom, obClr, "OB");
            }

            if(InpShowFVG)
            {
               for(int b = idmIdx + 1; b < bosBar; b++)
               {
                  if(high[b+1] < low[b-1])
                  {
                     double fvgTop = low[b-1];
                     double fvgBottom = high[b+1];
                     bufFVGTop[b] = fvgTop;
                     bufFVGBottom[b] = fvgBottom;

                     int mitBar2 = -1;
                     for(int c = b + 1; c <= lastBar; c++)
                        if(high[c] >= fvgBottom) { mitBar2 = c; break; }
                     datetime tEnd2 = (mitBar2 != -1) ? time[mitBar2] : time[lastBar];
                     color fvgClr = (mitBar2 != -1) ? InpColorMitigated : InpColorFVGBear;
                     DrawZone(OBJ_PREFIX + "FVG_" + (string)time[b], time[b-1], fvgTop, tEnd2, fvgBottom, fvgClr, "FVG");
                  }
               }
            }
         }
      }
   }

   string status = (lastBOSDir != 0)
      ? "BOS terakhir: " + (lastBOSDir > 0 ? "BULLISH" : "BEARISH") +
        " @ " + DoubleToString(lastBOSLevel, _Digits) +
        " (" + TimeToString(lastBOSTime, TIME_DATE|TIME_MINUTES) + ")"
      : "BOS terakhir: belum ada";

   if(InpCompactMode)
      status += "\nLegenda: H/L=huruf kedua HH-LH-HL-LL (warna=lime HH, oranye LH, biru HL, merah LL) | titik kuning=inducement | garis putus hijau/merah=BOS | kotak biru-oranye=OB, aqua-magenta=FVG, abu-abu=termitigasi";

   Comment(status);

   return rates_total;
}
