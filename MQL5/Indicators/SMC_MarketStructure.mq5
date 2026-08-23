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
//|     setelahnya) berhasil di-sweep oleh wick SEBELUM pivot high   |
//|     lawan berikutnya terbentuk. Kalau harga bikin high baru      |
//|     duluan sebelum sempat sweep, berarti tidak ada inducement    |
//|     lokal -> leg itu di-skip (no inducement, no setup), TIDAK    |
//|     ditunggu sampai ketemu sweep di masa depan yang tidak        |
//|     relevan. Kalau high ini adalah puncak tertinggi sejauh ini   |
//|     (tidak ada pivot lawan sama sekali), pencarian TETAP dibatasi|
//|     InpMaxSweepBars -- tanpa ini, penurunan bertahap berhari-hari|
//|     kemudian bisa "keitung" sweep padahal bukan inducement       |
//|     genuine (yang harusnya relatif cepat/dekat).                 |
//|  3. "Low valid"   = low terendah antara bar sweep sampai bar     |
//|     BOS. Kalau tidak ada pullback tambahan, ini sama dengan      |
//|     titik inducement itu sendiri. Level yang harus DI-BODY-BREAK |
//|     buat BOS ini "ratchet": kalau ada candle yang wick-nya       |
//|     (swap) nembus lebih tinggi dari high valid TANPA body close  |
//|     di situ, acuannya pindah ke wick tertinggi itu -- body break |
//|     berikutnya harus ngelewatin titik itu, bukan level high      |
//|     valid yang asli (mirror: acuan turun buat jalur bearish).    |
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
//|  9. Bias (bullish/bearish) -- selama bias aktif ke satu arah,    |
//|     jalur validasi arah LAWAN di-skip total (tidak dievaluasi    |
//|     sama sekali), sampai ada CHoCH. SELAIN itu, selama bias      |
//|     bullish cuma high yang GENUINELY lebih tinggi dari H valid   |
//|     terakhir yang dievaluasi (begitu juga low lebih rendah untuk |
//|     bias bearish) -- high/low yang lebih rendah/tinggi bukan     |
//|     noise valid, di-skip total, bukan cuma dikasih label beda.   |
//| 10. CHoCH = saat bias bullish, candle body-close di BAWAH acuan   |
//|     -> bias flip ke bearish (sebaliknya untuk bias bearish,      |
//|     body-close di ATAS). Acuan ini "ratchet": kalau ada wick     |
//|     yang nembus lebih dalam/tinggi sebelum body-close (rejection |
//|     wick), acuannya ikut pindah ke titik wick terdalam itu --    |
//|     CHoCH cuma sah kalau beneran ngelewatin titik TERDALAM yang  |
//|     pernah disentuh, bukan level awal yang mungkin udah "dites"  |
//|     duluan sama wick yang lebih dalam.                           |
//| 11. IDM "live" (rule #2 di atas) CUMA boleh gerak/update kalau    |
//|     pivot yang bersangkutan genuinely lebih tinggi/rendah dari   |
//|     H/L valid terakhir (gate #9 dicek DULU, sebelum IDM          |
//|     disentuh sama sekali) -- IDM tidak boleh ikut gerak karena   |
//|     noise yang gagal gate.                                      |
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

input int   InpSwingBars        = 4;     // Jumlah bar kiri/kanan untuk deteksi fractal swing (2 kegampangan detect noise di M5, sudah divalidasi 4 lebih bersih)
input int   InpMaxSweepBars     = 50;    // Batas maks bar menunggu sweep inducement (0 = tanpa batas)
input int   InpMaxHistoryBars   = 10000; // Batas berapa bar terakhir yang diproses (0 = semua history -- BERAT kalau history panjang)
input bool  InpUseOnlyClosedBars = true;  // Hanya proses bar yang sudah close (hindari repaint)
input bool  InpShowOB            = true;  // Tampilkan Order Block (POI)
input bool  InpShowFVG           = true;  // Tampilkan Fair Value Gap
input bool  InpCompactMode       = true;  // Mode simpel: simbol/huruf tunggal, tanpa teks panjang
input int   InpLabelFontSize     = 7;     // Ukuran font label
input bool  InpShowSwingLabels   = true;  // Tampilkan huruf H/L di titik swing (HH/LH/HL/LL)
input bool  InpOnlyLatestBOS     = true;  // Cuma gambar BOS & inducement TERAKHIR (bukan semua history)
input bool  InpHideMitigated     = true;  // Sembunyikan total OB/FVG yang sudah termitigasi (bukan digrayscale)
input bool  InpShowLegend        = true;  // Tampilkan baris legenda di comment
input string InpLegendText       = "H/L=huruf kedua HH-LH-HL-LL | garis titik-titik=inducement | garis putus=BOS (kuning/abu2=IDM belum/sudah termitigasi) | kotak=OB/FVG (abu-abu=termitigasi)"; // Teks legenda (bebas diubah)
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
input color InpColorChoch        = clrWhite; // Warna garis CHoCH (beda dari BOS biar kebeda)

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

void DrawInducement(datetime tFrom, datetime tTo, double price, bool mitigated)
{
   string lname = OBJ_PREFIX + "IDMLINE_" + (string)tFrom;
   ObjectCreate(0, lname, OBJ_TREND, 0, tFrom, price, tTo, price);
   ObjectSetInteger(0, lname, OBJPROP_COLOR, mitigated ? InpColorMitigated : InpColorIDM);
   ObjectSetInteger(0, lname, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, lname, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, lname, OBJPROP_WIDTH, 1);

   if(!InpCompactMode)
   {
      string txt = OBJ_PREFIX + "IDMLBL_" + (string)tFrom;
      ObjectCreate(0, txt, OBJ_TEXT, 0, tFrom, price);
      ObjectSetString(0, txt, OBJPROP_TEXT, "IDM");
      ObjectSetInteger(0, txt, OBJPROP_COLOR, mitigated ? InpColorMitigated : InpColorIDM);
      ObjectSetInteger(0, txt, OBJPROP_FONTSIZE, InpLabelFontSize);
   }
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

void DrawChoch(datetime tFrom, datetime tTo, double price, int dir)
{
   string lname = OBJ_PREFIX + "CHOCHLINE_" + (string)tTo;
   ObjectCreate(0, lname, OBJ_TREND, 0, tFrom, price, tTo, price);
   ObjectSetInteger(0, lname, OBJPROP_COLOR, InpColorChoch);
   ObjectSetInteger(0, lname, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lname, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, lname, OBJPROP_WIDTH, 2);

   string txt = OBJ_PREFIX + "CHOCHLBL_" + (string)tTo;
   ObjectCreate(0, txt, OBJ_TEXT, 0, tTo, price);
   ObjectSetString(0, txt, OBJPROP_TEXT, InpCompactMode ? "C" : (dir > 0 ? "CHoCH UP" : "CHoCH DOWN"));
   ObjectSetInteger(0, txt, OBJPROP_COLOR, InpColorChoch);
   ObjectSetInteger(0, txt, OBJPROP_FONTSIZE, InpLabelFontSize);
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

   // Batasi jendela kerja ke InpMaxHistoryBars terakhir -- tanpa ini, full-recompute
   // tiap panggilan OnCalculate jadi O(n^2)-ish dan sangat berat begitu history yang
   // ke-load numpuk puluhan ribu bar (persis yang bikin Strategy Tester ketinggalan
   // jauh dari kecepatan replay-nya).
   int scanStart = (InpMaxHistoryBars > 0) ? MathMax(n, rates_total - InpMaxHistoryBars) : n;

   for(int i = MathMax(0, scanStart - n); i < rates_total; i++)
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

   for(int i = scanStart; i <= lastBar - n; i++)
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
   int lastBOSDir = 0; double lastBOSLevel = 0; datetime lastBOSTime = 0; datetime lastBOSFromTime = 0;
   bool haveIDM = false; datetime lastIDMTime = 0; double lastIDMPrice = 0;
   datetime lastIDMEndTime = 0; bool lastIDMMitigated = false;

   // bias: 0 = belum ada arah yang established, 1 = bullish, -1 = bearish.
   // Selama bias aktif ke satu arah, jalur validasi arah LAWAN di-skip total --
   // sampai CHoCH beneran kejadian (body-close menembus L-valid/H-valid yang
   // lagi jadi acuan) dan mem-flip bias-nya.
   int bias = 0;
   double activeLevelPrice = 0; int activeLevelIdx = -1;
   int lastChochDir = 0; double lastChochLevel = 0; datetime lastChochTime = 0; datetime lastChochFromTime = 0;

   for(int p = 0; p < pivotCount - 1; p++)
   {
      if(pivots[p].isHigh && !pivots[p+1].isHigh)
      {
         if(bias == -1) continue; // lagi bearish -- jalur bullish di-skip sampai ada CHoCH balik

         // Gate DULUAN sebelum apapun disentuh: selama bias masih bullish, cuma high
         // yang GENUINELY LEBIH TINGGI dari H valid terakhir yang relevan sama sekali --
         // high yang lebih rendah itu bukan noise yang boleh menggerakkan IDM sekalipun,
         // dia harus di-skip total dari awal (bukan cuma dilabel beda di akhir).
         bool isHH = !haveLastValidHigh || pivots[p].price > lastValidHighPrice;
         if(!isHH) continue;

         // Bullish path: swing high, then internal pullback low (inducement candidate)
         int idmIdx = pivots[p+1].idx;
         double idmPrice = pivots[p+1].price;

         // Batasi pencarian sweep sampai muncul pivot HIGH baru yang levelnya LEBIH
         // TINGGI dari high ini (bukan sekadar pivot high apapun -- pivot minor yang
         // masih lebih rendah itu wajar terjadi di tengah konsolidasi sebelum sweep-nya
         // beneran kejadian, dan tidak boleh motong pencarian). Kalau ada high baru yang
         // lebih ekstrem duluan sebelum sweep, baru dianggap leg ini stale/superseded.
         int windowEnd = lastBar;
         for(int p2 = p + 2; p2 < pivotCount; p2 += 2)
            if(pivots[p2].price > pivots[p].price) { windowEnd = pivots[p2].idx; break; }
         // Tambahan: kalau nggak ada pivot lawan yang lebih ekstrem (misal high ini
         // puncak tertinggi sejauh ini), windowEnd default ke lastBar -- yang berarti
         // penurunan bertahap berhari-hari kemudian bisa "keitung" sweep, padahal itu
         // bukan inducement yang genuine (sweep harusnya relatif deket/cepat). Batasi
         // juga dengan jumlah bar maksimum.
         if(InpMaxSweepBars > 0)
            windowEnd = MathMin(windowEnd, idmIdx + InpMaxSweepBars);

         int sweepBar = -1;
         for(int b = idmIdx + 1; b <= windowEnd; b++)
            if(low[b] < idmPrice) { sweepBar = b; break; }
         bool idmSwept = (sweepBar != -1);

         // Track IDM ini sebagai referensi TERKINI sekalipun belum ke-sweep (live) --
         // trader perlu bisa mantengin level ini di chart sebelum tau apakah bakal
         // di-sweep atau malah keburu ke-supersede oleh pullback yang lebih baru.
         bufIDM[idmIdx] = idmPrice;

         int idmMitBar = -1;
         if(idmSwept)
         {
            for(int b = sweepBar; b <= lastBar; b++)
               if(high[b] >= idmPrice) { idmMitBar = b; break; }
         }
         bool idmMitigated = idmSwept && (idmMitBar != -1);
         datetime idmEndTime = idmMitigated ? time[idmMitBar] : time[lastBar];

         haveIDM = true; lastIDMTime = time[idmIdx]; lastIDMPrice = idmPrice;
         lastIDMEndTime = idmEndTime; lastIDMMitigated = idmMitigated;
         if(!InpOnlyLatestBOS)
            DrawInducement(time[idmIdx], idmEndTime, idmPrice, idmMitigated);

         if(!idmSwept) continue; // belum ke-sweep -> H belum valid, belum ada setup

         bufHH[pivots[p].idx] = pivots[p].price;
         if(InpShowSwingLabels)
            DrawLabel(time[pivots[p].idx], pivots[p].price, "HH", InpColorHH, true);
         haveLastValidHigh = true;
         lastValidHighPrice = pivots[p].price;

         // Sweep sudah confirmed di sini -- pencarian BOS TIDAK dibatasi windowEnd lagi.
         // Konsolidasi panjang dengan beberapa candle yang cuma wick nembus (bukan body
         // close) itu wajar; breakout body-close yang beneran boleh terjadi kapan saja
         // setelahnya, bukan cuma sebelum pivot high kecil berikutnya kebentuk.
         //
         // bosWatchLevel di-ratchet naik kalau ada candle yang wick-nya (swap) nembus
         // lebih tinggi dari HV tanpa body close di situ -- acuan body-break buat LV
         // pindah ke titik swap terdalam itu, bukan tetap di level HV yang asli.
         double runLow = idmPrice; int runLowIdx = idmIdx;
         double bosWatchLevel = pivots[p].price;
         int bosBar = -1;
         for(int b = idmIdx; b <= lastBar; b++)
         {
            if(low[b] < runLow) { runLow = low[b]; runLowIdx = b; }
            if(high[b] > bosWatchLevel) bosWatchLevel = high[b];
            if(close[b] > bosWatchLevel) { bosBar = b; break; }
         }
         if(bosBar != -1)
         {
            bool isHL = !haveLastValidLow || runLow > lastValidLowPrice;
            if(isHL) bufHL[runLowIdx] = runLow;
            else     bufLL[runLowIdx] = runLow;
            if(InpShowSwingLabels)
               DrawLabel(time[runLowIdx], runLow, isHL ? "HL" : "LL", isHL ? InpColorHL : InpColorLL, false);
            haveLastValidLow = true;
            lastValidLowPrice = runLow;

            bufBOSDir[bosBar] = 1;
            bufBOSLevel[bosBar] = bosWatchLevel;
            if(!InpOnlyLatestBOS)
               DrawBOS(time[pivots[p].idx], time[bosBar], bosWatchLevel, 1);
            lastBOSDir = 1; lastBOSLevel = bosWatchLevel; lastBOSTime = time[bosBar]; lastBOSFromTime = time[pivots[p].idx];

            // L-valid ini sekarang jadi acuan aktif -- kalau nanti ada candle yang
            // body-close di BAWAHnya, itu CHoCH (bullish -> bearish).
            bias = 1;
            activeLevelPrice = runLow; activeLevelIdx = runLowIdx;
            // Watch level ini "ratchet" turun kalau ada wick yang nembus lebih dalam
            // (rejection wick, nggak close di situ) -- CHoCH baru sah kalau body-close
            // beneran ngelewatin titik TERDALAM yang pernah disentuh, bukan cuma level
            // acuan awal yang mungkin udah "dites" duluan sama wick yang lebih dalam.
            double watchLevel = activeLevelPrice;
            int chochBar = -1;
            for(int cb = bosBar + 1; cb <= lastBar; cb++)
            {
               if(low[cb] < watchLevel) watchLevel = low[cb];
               if(close[cb] < watchLevel) { chochBar = cb; break; }
            }
            if(chochBar != -1)
            {
               bias = -1;
               lastChochDir = -1; lastChochLevel = watchLevel;
               lastChochTime = time[chochBar]; lastChochFromTime = time[activeLevelIdx];
               if(!InpOnlyLatestBOS)
                  DrawChoch(time[activeLevelIdx], time[chochBar], watchLevel, -1);
               // Regime baru dimulai -- referensi low lama (dari struktur bullish
               // yang baru saja dipatahkan) sudah tidak relevan buat nge-gate low
               // pertama di regime bearish ini. Reset supaya low itu otomatis jadi
               // baseline baru, bukan ditolak karena "belum lebih rendah" dari level lama.
               haveLastValidLow = false;
            }

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
               bool obMitigated = (mitBar != -1);
               if(!obMitigated || !InpHideMitigated)
               {
                  datetime tEnd = obMitigated ? time[mitBar] : time[lastBar];
                  color obClr = obMitigated ? InpColorMitigated : InpColorOBBull;
                  DrawZone(OBJ_PREFIX + "OB_" + (string)time[obIdx], time[obIdx], obTop, tEnd, obBottom, obClr, "OB");
               }
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
                     bool fvgMitigated = (mitBar2 != -1);
                     if(!fvgMitigated || !InpHideMitigated)
                     {
                        datetime tEnd2 = fvgMitigated ? time[mitBar2] : time[lastBar];
                        color fvgClr = fvgMitigated ? InpColorMitigated : InpColorFVGBull;
                        DrawZone(OBJ_PREFIX + "FVG_" + (string)time[b], time[b-1], fvgTop, tEnd2, fvgBottom, fvgClr, "FVG");
                     }
                  }
               }
            }
         }
      }
      else if(!pivots[p].isHigh && pivots[p+1].isHigh)
      {
         if(bias == 1) continue; // lagi bullish -- jalur bearish di-skip sampai ada CHoCH balik

         // Gate duluan, mirror bullish: cuma low yang GENUINELY LEBIH RENDAH dari L
         // valid terakhir yang boleh menggerakkan apapun (termasuk IDM).
         bool isLL = !haveLastValidLow || pivots[p].price < lastValidLowPrice;
         if(!isLL) continue;

         // Bearish path: swing low, then internal pullback high (inducement candidate)
         int idmIdx = pivots[p+1].idx;
         double idmPrice = pivots[p+1].price;

         // Sama seperti jalur bullish: baru dianggap stale kalau ada low baru yang
         // LEBIH RENDAH dari low ini, bukan sekadar pivot low apapun.
         int windowEnd = lastBar;
         for(int p2 = p + 2; p2 < pivotCount; p2 += 2)
            if(pivots[p2].price < pivots[p].price) { windowEnd = pivots[p2].idx; break; }
         if(InpMaxSweepBars > 0)
            windowEnd = MathMin(windowEnd, idmIdx + InpMaxSweepBars);

         int sweepBar = -1;
         for(int b = idmIdx + 1; b <= windowEnd; b++)
            if(high[b] > idmPrice) { sweepBar = b; break; }
         bool idmSwept = (sweepBar != -1);

         bufIDM[idmIdx] = idmPrice;

         int idmMitBar = -1;
         if(idmSwept)
         {
            for(int b = sweepBar; b <= lastBar; b++)
               if(low[b] <= idmPrice) { idmMitBar = b; break; }
         }
         bool idmMitigated = idmSwept && (idmMitBar != -1);
         datetime idmEndTime = idmMitigated ? time[idmMitBar] : time[lastBar];

         haveIDM = true; lastIDMTime = time[idmIdx]; lastIDMPrice = idmPrice;
         lastIDMEndTime = idmEndTime; lastIDMMitigated = idmMitigated;
         if(!InpOnlyLatestBOS)
            DrawInducement(time[idmIdx], idmEndTime, idmPrice, idmMitigated);

         if(!idmSwept) continue;

         bufLL[pivots[p].idx] = pivots[p].price;
         if(InpShowSwingLabels)
            DrawLabel(time[pivots[p].idx], pivots[p].price, "LL", InpColorLL, false);
         haveLastValidLow = true;
         lastValidLowPrice = pivots[p].price;

         // Sama seperti jalur bullish: BOS tidak dibatasi windowEnd, cuma sweep-nya.
         // bosWatchLevel di-ratchet turun kalau ada candle yang wick-nya (swap) nembus
         // lebih rendah dari LV tanpa body close di situ -- acuan body-break buat HV
         // pindah ke titik swap terendah itu, bukan tetap di level LV yang asli.
         double runHigh = idmPrice; int runHighIdx = idmIdx;
         double bosWatchLevel = pivots[p].price;
         int bosBar = -1;
         for(int b = idmIdx; b <= lastBar; b++)
         {
            if(high[b] > runHigh) { runHigh = high[b]; runHighIdx = b; }
            if(low[b] < bosWatchLevel) bosWatchLevel = low[b];
            if(close[b] < bosWatchLevel) { bosBar = b; break; }
         }
         if(bosBar != -1)
         {
            bool isLH = !haveLastValidHigh || runHigh < lastValidHighPrice;
            if(isLH) bufLH[runHighIdx] = runHigh;
            else     bufHH[runHighIdx] = runHigh;
            if(InpShowSwingLabels)
               DrawLabel(time[runHighIdx], runHigh, isLH ? "LH" : "HH", isLH ? InpColorLH : InpColorHH, true);
            haveLastValidHigh = true;
            lastValidHighPrice = runHigh;

            bufBOSDir[bosBar] = -1;
            bufBOSLevel[bosBar] = bosWatchLevel;
            if(!InpOnlyLatestBOS)
               DrawBOS(time[pivots[p].idx], time[bosBar], bosWatchLevel, -1);
            lastBOSDir = -1; lastBOSLevel = bosWatchLevel; lastBOSTime = time[bosBar]; lastBOSFromTime = time[pivots[p].idx];

            // H-valid ini sekarang jadi acuan aktif -- kalau nanti ada candle yang
            // body-close di ATASnya, itu CHoCH (bearish -> bullish).
            bias = -1;
            activeLevelPrice = runHigh; activeLevelIdx = runHighIdx;
            // Ratchet ke atas: kalau ada wick yang nembus lebih tinggi (rejection wick),
            // level yang harus di-body-break buat CHoCH naik ikut ke titik itu.
            double watchLevel = activeLevelPrice;
            int chochBar = -1;
            for(int cb = bosBar + 1; cb <= lastBar; cb++)
            {
               if(high[cb] > watchLevel) watchLevel = high[cb];
               if(close[cb] > watchLevel) { chochBar = cb; break; }
            }
            if(chochBar != -1)
            {
               bias = 1;
               lastChochDir = 1; lastChochLevel = watchLevel;
               lastChochTime = time[chochBar]; lastChochFromTime = time[activeLevelIdx];
               if(!InpOnlyLatestBOS)
                  DrawChoch(time[activeLevelIdx], time[chochBar], watchLevel, 1);
               // Sama seperti bullish->bearish: reset referensi high lama dari
               // struktur bearish yang baru dipatahkan.
               haveLastValidHigh = false;
            }

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
               bool obMitigated = (mitBar != -1);
               if(!obMitigated || !InpHideMitigated)
               {
                  datetime tEnd = obMitigated ? time[mitBar] : time[lastBar];
                  color obClr = obMitigated ? InpColorMitigated : InpColorOBBear;
                  DrawZone(OBJ_PREFIX + "OB_" + (string)time[obIdx], time[obIdx], obTop, tEnd, obBottom, obClr, "OB");
               }
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
                     bool fvgMitigated = (mitBar2 != -1);
                     if(!fvgMitigated || !InpHideMitigated)
                     {
                        datetime tEnd2 = fvgMitigated ? time[mitBar2] : time[lastBar];
                        color fvgClr = fvgMitigated ? InpColorMitigated : InpColorFVGBear;
                        DrawZone(OBJ_PREFIX + "FVG_" + (string)time[b], time[b-1], fvgTop, tEnd2, fvgBottom, fvgClr, "FVG");
                     }
                  }
               }
            }
         }
      }
   }

   if(InpOnlyLatestBOS)
   {
      if(haveIDM)
         DrawInducement(lastIDMTime, lastIDMEndTime, lastIDMPrice, lastIDMMitigated);
      if(lastBOSDir != 0)
         DrawBOS(lastBOSFromTime, lastBOSTime, lastBOSLevel, lastBOSDir);
      if(lastChochDir != 0)
         DrawChoch(lastChochFromTime, lastChochTime, lastChochLevel, lastChochDir);
   }

   string status = "Bias: " + (bias > 0 ? "BULLISH" : (bias < 0 ? "BEARISH" : "belum ada"));
   status += (lastBOSDir != 0)
      ? "\nBOS terakhir: " + (lastBOSDir > 0 ? "BULLISH" : "BEARISH") +
        " @ " + DoubleToString(lastBOSLevel, _Digits) +
        " (" + TimeToString(lastBOSTime, TIME_DATE|TIME_MINUTES) + ")"
      : "\nBOS terakhir: belum ada";
   status += (lastChochDir != 0)
      ? "\nCHoCH terakhir: " + (lastChochDir > 0 ? "BULLISH" : "BEARISH") +
        " @ " + DoubleToString(lastChochLevel, _Digits) +
        " (" + TimeToString(lastChochTime, TIME_DATE|TIME_MINUTES) + ")"
      : "\nCHoCH terakhir: belum ada";

   if(InpShowLegend)
      status += "\n" + InpLegendText;

   Comment(status);

   return rates_total;
}
