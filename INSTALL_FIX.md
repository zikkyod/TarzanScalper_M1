# Fix: EA not showing in Navigator (Expert Advisors)

**Ship compile target (Grok Bot locked):** modular folder  
`/workspace/TarzanScalper_M1/` → copy to `<MT5 Data>/MQL5/Experts/TarzanScalper_M1/`  
Open **`TarzanScalper.mq5`** → F7 → expect **`TarzanScalper.ex5`**.

Do **not** treat `/workspace/tarzan/TarzanScalper_M1.mq5` (monolith) as ship-ready.

## Why it disappears
MT5 only lists EAs that compiled to an **`.ex5`**. Copying source alone is not enough. Any F7 error = no Navigator entry.

## Do this exactly
1. MetaTrader 5 → **File → Open Data Folder**
2. Copy the entire `TarzanScalper_M1/` folder into `MQL5/Experts/` (keep `.mq5` + all `.mqh` together)
3. In MT5 press **F4** (MetaEditor) → open `Experts/TarzanScalper_M1/TarzanScalper.mq5`
4. **Compile (F7)** — Errors tab must say **0 errors**. If not, paste the error lines to CODER 2
5. Confirm `TarzanScalper.ex5` appears beside the `.mq5`
6. Navigator → right-click **Expert Advisors** → **Refresh** (or restart MT5)

## Demo attach (after it appears)
1. Demo account — **EURUSD M1** (and separately **XAUUSD/GOLD M1**)
2. Drag **TarzanScalper** onto the chart
3. Inputs (demo-first):
   - `InpEnableTrading` = **false** until status looks sane
   - `InpRiskPercent` = **2.0**
   - `InpMinRR` = **1.5**
   - Forex: `InpMaxSpreadPoints` = **25–35**
   - Gold: `InpMaxSpreadPointsGold` = **60–80**
4. Allow Algo Trading toolbar = **ON** only when you flip trading on
5. Chart comment should show bias / BOS / gold zone / block reason

## Not blockers for Navigator
- Mobile start/stop → VPS-hosted EA + `InpEnableTrading` (MT5 mobile cannot host EAs)
- Gold Zone web chart empty after hydration → separate web dashboard bug (paint-after-hydrate + contrast)
