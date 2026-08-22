# CLAUDE.md — MT5 AI-Powered EA Project

Dokumen ini adalah context utama untuk sesi Claude Code di proyek ini. Baca dulu sebelum ngerjain apapun.

## 1. Konteks Proyek

Temen (client informal) minta bantuan bikin **Expert Advisor (EA) di MetaTrader 5** yang dibantu AI/ML — bukan EA rule-based indikator biasa. Trigger awal: MT5 sekarang support **ONNX runtime**, artinya model ML yang dilatih di Python (sklearn/XGBoost/PyTorch/dsb) bisa diekspor ke `.onnx` dan dipanggil langsung dari dalam EA (MQL5) tanpa perlu server Python nempel terus-terusan.

**Prinsip utama: TANPA HALU.** Ini domain uang beneran. Semua klaim soal:
- fungsi/API MQL5 yang tersedia,
- cara kerja `OnnxCreate`, `OnnxRun`, shape input/output tensor,
- perilaku broker/spread/slippage,
- hasil backtest,

...harus diverifikasi ke sumber resmi (dokumentasi MQL5 di mql5.com, forum resmi, atau hasil test langsung), bukan ditebak dari "kelihatannya begitu". Kalau nggak yakin, bilang "belum diverifikasi" — jangan sok tahu.

## 2. Arsitektur (4 Tahap, dari diskusi awal)

```
[Data Historis] → [Training di Python] → [Export .onnx] → [EA MQL5 di MT5]
```

1. **Data Collection**: OHLCV + indikator (RSI, MA, volume, dll) dari histori MT5, idealnya diambil via MT5 Python API (`MetaTrader5` package) biar konsisten sama data live nanti.
2. **Training (Python)**: cari pola / klasifikasi / regresi. Harus jelas target labelnya apa (misal: "harga naik >50 pip dalam 3 jam ke depan: ya/tidak").
3. **Export ke ONNX**: pastikan preprocessing (scaling, normalisasi) di-bake ke dalam model atau direplikasi persis di sisi MQL5 — ini sumber bug paling umum (training-serving skew).
4. **EA di MT5 (MQL5)**: load `.onnx` sekali di `OnInit()`, panggil `OnnxRun()` tiap candle baru, mapping output ke sinyal BUY/SELL/WAIT.

## 3. Kandidat Use Case (dari diskusi, belum difinalkan sama temen)

- **False Breakout Filter** — filter sinyal breakout palsu sebelum entry.
- **Market Regime Classifier** — deteksi Trending / Sideways / Volatile, lalu EA switch strategi.
- **Dynamic SL/TP** — prediksi range volatilitas untuk nentuin SL/TP proporsional, bukan pip tetap.

Ini masih ide awal, **belum tau strategi final yang diminta temen**. Jangan asumsikan salah satu ini yang dipilih — konfirmasi dulu.

## 4. Yang Perlu Dikonfirmasi ke Temen (Belum Terjawab)

- Pair & timeframe target (major pair? gold? crypto CFD?)
- Broker & jenis akun (ECN/spread berapa, latency eksekusi)
- Target: fully automated EA, atau semi (kasih sinyal, entry manual)?
- Sumber data training: MT5 history langsung, atau ada data pihak ketiga?
- Risk management: fixed lot / % equity / martingale-style (harus dihindari kalau memungkinkan)?
- Skala modal & toleransi drawdown — ini nentuin agresivitas model.
- Apakah temen expect real-time retraining (walk-forward) atau model statis yang di-retrain manual berkala?

## 5. Batasan & Red Flags yang Harus Dijaga

- **Jangan overfit ke backtest.** Model yang "wangi" di backtest 10 tahun tapi nggak pernah divalidasi out-of-sample/walk-forward = red flag besar. Selalu ingatkan soal ini kalau hasil kelihatan terlalu bagus.
- **Jangan janjiin winrate/profit tertentu.** Ini bukan ranah yang bisa dipastikan; kasih angka backtest apa adanya + disclaimer.
- **Spread/slippage/komisi** harus dimasukkan ke simulasi backtest, jangan asumsi eksekusi sempurna.
- **Data leakage**: pastikan fitur yang dipakai saat training benar-benar available secara real-time saat live trading (nggak pakai info masa depan).

## 6. Stack & Tools

- **MQL5** — bahasa EA di MT5 (mirip C++, event-driven: `OnInit`, `OnTick`, `OnDeinit`).
- **Python** — training model (pandas, scikit-learn/XGBoost/PyTorch → export `skl2onnx`/`onnx`/`torch.onnx`).
- **ONNX Runtime** — native support di MT5 build terbaru (`OnnxCreate`, `OnnxRun`, `OnnxSetInputShape`, dst — cek dokumentasi resmi tiap sesi, API ini masih relatif baru dan bisa berubah antar build MT5).
- **MetaTrader5 Python package** — buat tarik data historis & (opsional) live data untuk cross-check.

## 7. Gaya Komunikasi & Kerja

- Diskusi teknis santai pakai Bahasa Indonesia informal.
- Kalau ada deliverable buat ditunjukin ke temen (dokumentasi strategi, laporan hasil backtest), tulis lebih formal & rapi.
- Pendekatan: mulai dari prinsip dasar dulu (kenapa strategi ini masuk akal secara market microstructure), baru turun ke implementasi detail — bukan langsung nulis kode tanpa alasan yang jelas.
- Sebagai arsitek, Claude berperan sebagai co-pilot/sparring partner, bukan cuma nulis kode sesuai order — boleh push back kalau ada asumsi yang keliatan halu atau overengineered.

## 8. Status Proyek

🟡 **Tahap awal — exploratory.** Belum ada kode. Belum ada spek final dari temen. Dokumen ini akan diupdate begitu requirement lebih jelas.
