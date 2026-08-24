import pandas as pd

df = pd.read_csv("test-data/XAUUSDm_M5_20260820-21.csv", sep='\t')
df.columns = [c.strip('<>') for c in df.columns]
df = df.dropna(subset=['DATE']).reset_index(drop=True)
df['DT'] = pd.to_datetime(df['DATE'] + ' ' + df['TIME'])

high = df['HIGH'].values
low = df['LOW'].values
close = df['CLOSE'].values
times = [pd.Timestamp(t).strftime('%m-%d %H:%M') for t in df['DT'].values]
n = len(df)
sl = 3

def is_pivot_clipped(i, back_limit, bull):
    if i - sl < 0 or i + sl >= n:
        return False
    back_start = max(back_limit, i - sl)
    if bull:
        v = low[i]
        for k in range(back_start, i):
            if low[k] <= v: return False
        for k in range(i+1, i+sl+1):
            if low[k] <= v: return False
    else:
        v = high[i]
        for k in range(back_start, i):
            if high[k] >= v: return False
        for k in range(i+1, i+sl+1):
            if high[k] >= v: return False
    return True

# --- 1:1 port of the revised .mq5, bullish start, InpAutoBias=True ---
start = 0
end = n - 1
length = end - start + 1

curBull = True
hvCount = 0
lvCount = 0
legs = []
chocs = []

candidate = {'idx': 0, 'value': high[start], 'real': high[start]}
shadow = None
lockedOpp = None
secondPoint = None
pendingFirst = None
lastStructuralSecond = None
chocRefPrice = 0
chocRefIdx = -1

haveLiveIdm = False
liveIdm = None
haveSweptIdm = False
sweptIdmIdx = -1
sweptIdmPrice = 0
sweptIdmBreakIdx = -1

haveBos = False
bosHVIdx = -1
bosHVPrice = 0
bosBreakIdx = -1
bosIsBull = curBull
bosRefPrice = 0

phase = "seek_first"

for i in range(1, length):
    h = high[start+i]; l = low[start+i]; c = close[start+i]

    # 1. CHoC check
    if lastStructuralSecond is not None:
        chocTriggered = False
        newBull = curBull
        if curBull:
            if l < chocRefPrice:
                if c < chocRefPrice:
                    chocTriggered = True
                    newBull = False
                else:
                    chocRefPrice = l
                    chocRefIdx = i
                    if phase == "seek_first":
                        hvCount += 1
                        pendingFirst = {'idx': candidate['idx'], 'value': candidate['value'], 'real': candidate['real']}
                        bosRefPrice = candidate['real']
                        legs.append({'firstIdx': candidate['idx'], 'firstPrice': candidate['real'], 'firstLbl': f"HV{hvCount}",
                                     'secondIdx': -1, 'secondLbl': '', 'trigger': 'CHOC_SWAP', 'triggerIdx': i})
                        phase = "seek_second"
                        secondPoint = {'idx': i, 'value': l, 'real': l}
                        haveSweptIdm = True; sweptIdmIdx = -1; sweptIdmBreakIdx = i
                        haveLiveIdm = False; liveIdm = None
                        continue
        else:
            pass  # bearish path not needed - dataset never flips

        if chocTriggered:
            print(f"!!! CHoC TRIGGERED at {times[i]} (bull->bear) - not expected in this bull-only dataset")
            curBull = newBull
            # (bearish-flip handling omitted; dataset shouldn't reach here)
            break

    # 2. normal structure
    currHi = h if curBull else -l
    currLo = l if curBull else -h
    currCl = c if curBull else -c
    realLo = l if curBull else h
    realHi = h if curBull else l

    if phase == "seek_first":
        if is_pivot_clipped(i, candidate['idx'], curBull):
            if shadow is None or currLo < shadow['value']:
                shadow = {'idx': i, 'value': currLo, 'real': realLo}

        if lockedOpp is not None and currLo < lockedOpp['value']:
            pendingFirst = {'idx': candidate['idx'], 'value': candidate['value'], 'real': candidate['real']}
            bosRefPrice = candidate['real']
            phase = "seek_second"
            secondPoint = {'idx': i, 'value': currLo, 'real': realLo}
            sweptIdmIdx = lockedOpp['idx']; sweptIdmPrice = lockedOpp['real']; sweptIdmBreakIdx = i
            haveSweptIdm = True
            haveLiveIdm = False; liveIdm = None
            continue

        if currHi > candidate['value']:
            if shadow is not None:
                lockedOpp = shadow
                liveIdm = shadow
                haveLiveIdm = True
            candidate = {'idx': i, 'value': currHi, 'real': realHi}
            shadow = None
    else:
        if secondPoint is None or currLo < secondPoint['value']:
            secondPoint = {'idx': i, 'value': currLo, 'real': realLo}

        bosTriggered = False
        if curBull:
            if h > bosRefPrice:
                if c > bosRefPrice:
                    bosTriggered = True
                else:
                    bosRefPrice = h
        if bosTriggered:
            hvCount += 1; lvCount += 1
            legs.append({'firstIdx': pendingFirst['idx'], 'firstPrice': pendingFirst['real'], 'firstLbl': f"HV{hvCount}",
                         'secondIdx': secondPoint['idx'], 'secondPrice': secondPoint['real'], 'secondLbl': f"LV{lvCount}",
                         'trigger': 'BOS', 'triggerIdx': i})
            lastStructuralSecond = secondPoint
            chocRefPrice = secondPoint['real']; chocRefIdx = secondPoint['idx']
            bosHVIdx = pendingFirst['idx']; bosHVPrice = pendingFirst['real']
            bosBreakIdx = i; bosIsBull = curBull; haveBos = True
            phase = "seek_first"

            candIdx = i; candVal = currHi; candReal = realHi
            for k in range(secondPoint['idx']+1, i+1):
                kVal = high[start+k] if curBull else -low[start+k]
                kReal = high[start+k] if curBull else low[start+k]
                if kVal > candVal:
                    candVal = kVal; candReal = kReal; candIdx = k
            candidate = {'idx': candIdx, 'value': candVal, 'real': candReal}
            shadow = None; lockedOpp = None; pendingFirst = None
            haveLiveIdm = False; liveIdm = None

            for k in range(secondPoint['idx']+1, i):
                if is_pivot_clipped(k, secondPoint['idx'], curBull):
                    kVal = low[start+k] if curBull else -high[start+k]
                    kReal = low[start+k] if curBull else high[start+k]
                    if shadow is None or kVal < shadow['value']:
                        shadow = {'idx': k, 'value': kVal, 'real': kReal}
            if shadow is not None:
                lockedOpp = shadow; liveIdm = shadow; haveLiveIdm = True
                shadow = None
        else:
            if h > bosRefPrice:
                bosRefPrice = h  # (redundant w/ above but mirrors mq5 structure)

print(f"Total legs found: {len(legs)}\n")
print(f"{'firstLbl':>6} {'time':>12} {'price':>10}  |  {'secondLbl':>6} {'time':>12} {'price':>10}   trigger")
for leg in legs:
    ft = times[leg['firstIdx']]; fp = leg['firstPrice']; fl = leg['firstLbl']
    if leg.get('secondIdx', -1) >= 0:
        st = times[leg['secondIdx']]; sp = leg['secondPrice']; sl_ = leg['secondLbl']
        print(f"{fl:>6} {ft:>12} {fp:>10.3f}  |  {sl_:>6} {st:>12} {sp:>10.3f}   {leg['trigger']}")
    else:
        print(f"{fl:>6} {ft:>12} {fp:>10.3f}  |  {'--':>6} {'':>12} {'':>10}   {leg['trigger']}")

print("\n--- final dangling state ---")
print("phase:", phase)
print("live IDM:", liveIdm, "at", times[liveIdm['idx']] if liveIdm else None)
print("pendingFirst:", pendingFirst, "at", times[pendingFirst['idx']] if pendingFirst else None)
