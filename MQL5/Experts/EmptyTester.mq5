//+------------------------------------------------------------------+
//| EmptyTester.mq5                                                   |
//|                                                                    |
//| EA kosong -- tidak melakukan trading apapun. Satu-satunya fungsi   |
//| file ini adalah "mengisi slot" Expert Advisor di Strategy Tester,  |
//| karena Strategy Tester tidak bisa memilih indikator custom secara  |
//| langsung. Jalankan ini di Visual Mode, lalu attach indikator       |
//| SMC_MarketStructure ke chart Tester secara manual (klik kanan      |
//| chart -> Indicators List -> Custom) untuk melihatnya menggambar    |
//| ulang candle-per-candle seperti live, bukan sekali hitung penuh.   |
//+------------------------------------------------------------------+
#property copyright "fx-mt5-ai-onnx-ea"
#property version   "1.00"

int OnInit()
{
   return(INIT_SUCCEEDED);
}

void OnTick()
{
}
