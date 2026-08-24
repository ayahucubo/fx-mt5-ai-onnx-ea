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

# --- incremental version: NO unbounded backward scan anywhere. Every
# value used at BOS-confirm time was already tracked bar-by-bar as we
# went, exactly mirroring what Pine's bar-by-bar execution model can do
# without dynamic-offset historical lookups beyond a small fixed window. ---
start = 0
end = n - 1
length = end - start + 1

curBull = True
hvCount = 0
lvCount = 0
legs = []

candidate = {'idx': 0, 'value': high[start], 'real': high[start]}
shadow = None
lockedOpp = None
secondPoint = None
pendingFirst = None

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
bosRefPrice = 0

phase = "seek_first"

# incremental "window" trackers for the impulse since the latest secondPoint
windowCand = None       # {'idx','value','real'}
windowShadow = None     # {'idx','value','real'}

for i in range(1, length):
    h = high[start+i]; l = low[start+i]; c = close[start+i]

    currHi = h if curBull else -l
    currLo = l if curBull else -h
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
            windowCand = None
            windowShadow = None
            continue

        if currHi > candidate['value']:
            if shadow is not None:
                lockedOpp = shadow
                liveIdm = shadow
                haveLiveIdm = True
            candidate = {'idx': i, 'value': currHi, 'real': realHi}
            shadow = None
    else:
        secondMoved = False
        if secondPoint is None or currLo < secondPoint['value']:
            secondPoint = {'idx': i, 'value': currLo, 'real': realLo}
            secondMoved = True

        if secondMoved:
            windowCand = None
            windowShadow = None
        else:
            if i > secondPoint['idx']:
                if windowCand is None or currHi > windowCand['value']:
                    windowCand = {'idx': i, 'value': currHi, 'real': realHi}
                if is_pivot_clipped(i, secondPoint['idx'], curBull):
                    kVal = low[start+i] if curBull else -high[start+i]
                    kReal = low[start+i] if curBull else high[start+i]
                    if windowShadow is None or kVal < windowShadow['value']:
                        windowShadow = {'idx': i, 'value': kVal, 'real': kReal}

        bosTriggered = False
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
            bosHVIdx = pendingFirst['idx']; bosHVPrice = pendingFirst['real']
            bosBreakIdx = i; haveBos = True
            phase = "seek_first"

            # candidate = incrementally-tracked window max, falling back to
            # this bar's own high if the window never got a chance to
            # update (secondPoint moved on this exact bar - rare edge case)
            if windowCand is None or currHi > windowCand['value']:
                candidate = {'idx': i, 'value': currHi, 'real': realHi}
            else:
                candidate = dict(windowCand)
            shadow = None; lockedOpp = None; pendingFirst = None
            haveLiveIdm = False; liveIdm = None

            if windowShadow is not None:
                lockedOpp = dict(windowShadow); liveIdm = dict(windowShadow); haveLiveIdm = True
                shadow = None

            windowCand = None
            windowShadow = None

print(f"Total legs found: {len(legs)}\n")
print(f"{'firstLbl':>6} {'time':>12} {'price':>10}  |  {'secondLbl':>6} {'time':>12} {'price':>10}   trigger")
for leg in legs:
    ft = times[leg['firstIdx']]; fp = leg['firstPrice']; fl = leg['firstLbl']
    st = times[leg['secondIdx']]; sp = leg['secondPrice']; sl_ = leg['secondLbl']
    print(f"{fl:>6} {ft:>12} {fp:>10.3f}  |  {sl_:>6} {st:>12} {sp:>10.3f}   {leg['trigger']}")

print("\n--- final dangling state ---")
print("phase:", phase)
print("live IDM:", liveIdm, "at", times[liveIdm['idx']] if liveIdm else None)
print("pendingFirst:", pendingFirst, "at", times[pendingFirst['idx']] if pendingFirst else None)
