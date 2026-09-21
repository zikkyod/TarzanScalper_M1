# TarzanScalper M1 — Gold Zone / Tarzan (v1.10)

MetaTrader 5 Expert Advisor: **structure + Fibonacci pullback** scalper for **M1**.  
Hard rule: **no BOS-only entries**. BOS sets/flips bias and redraws Fib; entries are **limit orders** only in the **0.50–0.618** gold zone (prefer **0.618**).

**Architecture:** see `ARCHITECTURE.md` (Status: **FROZEN**, Grok Bot approved 2026-09-21).

**Demo-first.** `EnableTrading=false` by default — analysis + chart status only until you enable it.

---

## Files

| File | Role |
|------|------|
| `TarzanScalper.mq5` | EA wire-up (`OnTick` / `OnTradeTransaction`) |
| `SwingEngine.mqh` | `CSwingEngine` — pivot/swing detection |
| `BosDetector.mqh` | `CBosDetector` — decisive BOS on **candle close** |
| `FibZone.mqh` | `CFibZone` — Fib anchors + gold zone |
| `EntryEngine.mqh` | `CEntryEngine` — limit entries in zone |
| `RiskEngine.mqh` | `CRiskEngine` — SL @ Fib 1.0, TP, RR gate, lots |
| `BiasState.mqh` | `CBiasState` — bias / phase / post-SL wait |
| `TradeManager.mqh` | `CTradeManager` — place/cancel, magic discipline |
| `ARCHITECTURE.md` | Frozen design (source of truth) |

**v1 scope:** one magic / one chart only. Attach separately per symbol.

---

## Install

1. Open MetaTrader 5 → **File → Open Data Folder**.
2. Copy this entire folder into:
   ```
   <MT5 Data Folder>/MQL5/Experts/TarzanScalper_M1/
   ```
   All `.mq5` + `.mqh` + docs must sit together (includes are relative).
3. Restart MT5 or right-click **Navigator → Expert Advisors → Refresh**.

---

## Compile (expect 0 errors)

1. Open `TarzanScalper.mq5` in **MetaEditor** (F4 from MT5, or open the file).
2. Press **F7** (Compile).
3. Expect **0 errors**. Warnings (if any) should be reviewed but are usually harmless.
4. Confirm `TarzanScalper.ex5` appears beside the source.

---

## Demo attach — EURUSD M1

1. Open a **demo** account chart: **EURUSD**, timeframe **M1**.
2. Drag **TarzanScalper** onto the chart (or double-click in Navigator).
3. Inputs (recommended start):
   - `InpEnableTrading` = **false** (watch status first)
   - `InpMaxSpreadPoints` = **30** (typical FX band **25–35**)
   - `InpRiskPercent` = **2.0**
   - `InpMinRR` = **1.5**
   - `InpPrefer0618` = **true**
4. Allow **Algo Trading** on the toolbar when you are ready.
5. Watch the chart **Comment** status: bias, BOS, gold zone prices, spread vs max, block reason.
6. When comfortable, set `InpEnableTrading` = **true** (re-attach or change inputs and OK).

---

## Demo attach — XAUUSD M1 (Gold)

1. Open a **separate** demo chart: **XAUUSD** (or your broker’s gold symbol), **M1**.
2. Attach **TarzanScalper** again (v1 = one EA instance per chart/symbol).
3. Inputs:
   - `InpEnableTrading` = **false** first
   - `InpMaxSpreadPoints` = **30** (fallback)
   - `InpMaxSpreadPointsGold` = **60–80** (recommended; auto-used when symbol contains `XAU` or `GOLD`)
   - `InpRiskPercent` = **2.0**
   - `InpMinSwingPoints` may need raising on noisy gold feeds (defaults aim for sane M1 distance)
4. Enable trading only after you see clean BOS → Fib → limit behavior on the status line.

---

## Strategy checklist (v1.10)

1. Pivot/swing detection with minimum swing distance  
2. Decisive **BOS on candle CLOSE** through swing (not wick alone)  
3. After BOS → Fib from swing extremes (**0.0 = broken swing**, **1.0 = prior opposite swing**)  
4. Enter **ONLY** via **LIMIT** in Fib gold zone **0.50–0.618** (prefer **0.618**) — **never** on BOS alone  
5. **SL** at Fib **1.0**; **TP** near prior swing / opposite structure  
6. Minimum **RR** filter (`InpMinRR`, default **1.5**)  
7. Stop-out: **flip bias + cancel pendings immediately**; **wait next decisive BOS** before Fib redraw  
8. **All-session** operation (no session filter in v1.10)

---

## Chart status

Each tick / new bar the EA updates `Comment()` with:

- Symbol, `EnableTrading`
- Bias, phase, post-SL “await BOS” flag
- BOS / last reason
- Gold zone prices (0.0 / 0.50 / 0.618 / 1.0)
- Current spread vs max, risk %, MinRR
- Position / pending count, magic
- Block reason (spread, RR, EnableTrading=false, post-SL wait, etc.)

---

## Telegram / mobile remote

The EA **cannot run inside the MT5 mobile app**.  
For remote / Telegram-style control later: host the EA on a **VPS** with desktop MT5 (or a bridge you add later). Mobile is for monitoring the account only.

---

## Locked Grok Bot decisions

| # | Lock |
|---|------|
| 1 | Post-SL: flip bias + cancel pendings; **no immediate Fib**; wait next decisive BOS |
| 2 | Default `InpMinRR` = **1.5** |
| 3 | Fib 0.0 = **broken swing level** (not BOS-bar extreme); Fib 1.0 = prior opposite swing |
| 4 | v1 = **one magic / one chart** only |

---

## Disclaimer

Educational / demo tooling. No live-account assumptions. Past structure behavior does not guarantee future results. Use demo until you fully understand fills, spreads, and stop-out flips on your broker.
