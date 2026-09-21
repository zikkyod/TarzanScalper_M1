# Tarzan / Gold Zone M1 MT5 Scalper — Architecture

**Status:** FROZEN — Grok Bot approved 2026-09-21  
**Owner:** CODER (architecture)  
**Implementers:** CODER 3 (features/ship), CODER 2 (bugs/hardening)  
**Reviewer:** Grok Bot — quality review before ship  
**Platform:** MetaTrader 5, MQL5 Expert Advisor, timeframe M1 (XAUUSD / Gold)  
**v1 scope:** **one magic / one chart only** (multi-symbol later)

---

## 1. Goal

Scalp Gold on M1 using **structure + Fibonacci pullback**, not raw BOS entries.

Pipeline: **Bias from decisive BOS → draw Fib → wait for pullback into 0.50–0.618 → limit entry → SL at Fib 1.0 → TP near prior swing → RR gate → on stop-out, flip bias.**

Hard rule: **no BOS-only entries.** BOS only sets / flips bias and redraws Fib.

---

## 2. Module map (LOCKED)

| Module | Responsibility | Files |
|--------|----------------|-------|
| `CSwingEngine` | Pivot/swing detection with min distance | `SwingEngine.mqh` |
| `CBosDetector` | Decisive BOS on **candle close** only | `BosDetector.mqh` |
| `CFibZone` | Fib from BOS swing pair; zone 0.50–0.618 | `FibZone.mqh` |
| `CEntryEngine` | Limit orders in zone (prefer 0.618) | `EntryEngine.mqh` |
| `CRiskEngine` | SL @ Fib 1.0, TP near prior swing, RR filter | `RiskEngine.mqh` |
| `CBiasState` | Long/short bias; flip on stop-out | `BiasState.mqh` |
| `CTradeManager` | Place/modify/cancel; magic; one-position discipline | `TradeManager.mqh` |
| `TarzanScalper.mq5` | Wire OnTick / OnTradeTransaction; inputs | `TarzanScalper.mq5` |

Keep indicator math out of the EA body. Pure functions where possible for unit-testable logic.

---

## 3. Bias & BOS (decisive, close-only)

### 3.1 Swing / pivot (stronger + min distance)

- Swing high: bar `i` high > highs of `N` bars left and `N` bars right (confirmed only when right side is complete — no peeking unfinished bars).
- Swing low: symmetric on lows.
- **Min distance** (`InpMinSwingPoints` in price, or ATR multiple `InpMinSwingAtrMult`): reject pivots closer than this to the previous opposite pivot. Prevents choppy micro-swings on M1.
- Store last confirmed swing high/low with bar time + price. Maintain a short ring buffer (e.g. last 8 swings) for TP / Fib anchors.

### 3.2 Decisive BOS

- **Bullish BOS:** candle **closes** above last confirmed swing high (not wick pierce).
- **Bearish BOS:** candle **closes** below last confirmed swing low.
- Optional strength filter: close must clear the level by `InpBosBufferPoints` (or ATR fraction) so borderline closes don't count.
- On BOS: set bias (`BIAS_LONG` / `BIAS_SHORT`), invalidate prior Fib, call `CFibZone::Redraw(...)`.
- BOS never places a market/limit by itself.

### 3.3 Stop-out bias flip (LOCKED)

On our position hitting SL (`OnTradeTransaction` DEAL_ENTRY_OUT with loss / SL reason):

1. **Flip bias** to the opposite direction immediately.
2. **Cancel all pending limits** for this magic immediately.
3. **Do NOT redraw Fib** on the dirty post-SL structure.
4. **Wait for the next decisive BOS** (close-only) before any Fib redraw and before any new limit.

Until that next BOS: bias is flipped but Fib is invalid / cleared; no new entries.

---

## 4. Fibonacci after BOS (LOCKED anchors)

After decisive BOS only:

| Bias | Fib 0.0 (impulse end) | Fib 1.0 (origin / SL side) |
|------|------------------------|----------------------------|
| Long (bull BOS) | **Broken swing high** — the swing that BOS closed through | Prior opposite swing low that defined the move |
| Short (bear BOS) | **Broken swing low** — the swing that BOS closed through | Prior opposite swing high that defined the move |

**Not** the BOS-bar extreme. Fib 0.0 is always the broken swing level.

Standard pullback Fib: levels between origin (1.0) and impulse extreme (0.0).

**Entry zone:** price in **[0.50, 0.618]** inclusive.  
**Preferred fill level:** **0.618** (deeper pullback).  
**SL:** Fib **1.0**.  
**TP:** near **prior swing** in trade direction (e.g. long → last relevant swing high / liquidity above entry; short → prior swing low). If that TP fails RR, skip or use next structural target — do not lower SL.

Invalidate Fib if: opposite BOS, or stop-out clearing (§3.3), or optional time/structure break (`InpFibMaxAgeBars`).

---

## 5. Entry rules (limit only)

1. Bias set and Fib valid (Fib only valid after BOS redraw — never after bare stop-out flip).
2. No open position / no conflicting pending for this magic (`InpMaxPositions = 1`, one chart).
3. Place **buy limit** (long) or **sell limit** (short) at **0.618** by default; if price already inside zone and past 0.618 toward 0.50, place at current zone edge still ≥0.50 (or skip if price already through 0.50 toward origin — no chase).
4. Never market-enter on BOS.
5. Cancel / replace limit if Fib redraws.

---

## 6. Risk & RR filter (LOCKED default)

- **SL** = Fib 1.0 (± `InpSlBufferPoints` if needed for spread).
- **TP** = prior swing price (± buffer), clamped by broker stops level.
- **RR filter:** require `Reward / Risk >= InpMinRR`. **Default `InpMinRR = 1.5`** (input stays tunable). If TP distance / SL distance < min RR → **do not place** (log skip reason).
- Lot sizing: fixed lots or risk-% of equity from SL distance (`InpRiskPercent`).
- Spread / news filters optional inputs; off by default for v1.

---

## 7. State machine

```
IDLE → (decisive BOS close) → BIAS_SET → FIB_DRAWN → LIMIT_PENDING
  → FILLED → IN_TRADE
  → TP → IDLE (keep bias until opposite BOS or stop-out flip)
  → SL → FLIP_BIAS → cancel pendings → CLEAR_FIB → wait next decisive BOS
Opposite BOS at any time → cancel pendings → new bias → new Fib
```

---

## 8. Inputs (v1)

- `InpMagic`, `InpSlippage`, `InpMaxPositions` (= 1)
- `InpSwingN` (pivot wing), `InpMinSwingPoints` / `InpMinSwingAtrMult`
- `InpBosBufferPoints`
- `InpPrefer0618` (bool, default true), `InpZoneLo=0.50`, `InpZoneHi=0.618`
- `InpMinRR` (default **1.5**), `InpRiskPercent` or `InpFixedLots`
- `InpSlBufferPoints`, `InpTpBufferPoints`
- `InpFlipOnStopOut` (bool, default true)

---

## 9. Work split

| Who | Owns |
|-----|------|
| **CODER** | This architecture; module interfaces; invariants; structure review |
| **CODER 3** | Feature implementation: modules + EA wire-up, shippable `.mq5` |
| **CODER 2** | Edge cases: pivot confirmation, SL reason parse, Fib invalidation races, spread/stops |
| **Grok Bot** | Design approval (done); quality review before ship |

---

## 10. Acceptance criteria

1. BOS uses **close** vs swing, never wick-only.
2. No order path that enters solely because BOS fired.
3. Limits only inside 0.50–0.618; default price 0.618.
4. SL always Fib 1.0 (+ buffer); TP structural; RR gate with default 1.5.
5. Stop-out: flip bias + cancel pendings; **wait next BOS** before Fib redraw.
6. Fib 0.0 = broken swing level; Fib 1.0 = prior opposite swing.
7. v1: one magic, one chart.
8. M1 Gold: sane defaults for swing distance so Fib isn't redrawn every few bars.

---

## 11. Locked decisions (Grok Bot 2026-09-21)

| # | Question | Decision |
|---|----------|----------|
| 1 | Post-SL Fib | Flip bias + cancel pendings immediately; **wait for next decisive BOS** before Fib redraw. No immediate redraw on dirty post-SL structure. |
| 2 | Default `InpMinRR` | **1.5** (tunable input). |
| 3 | Fib 0.0 | **Broken swing level** (swing BOS closed through), not BOS-bar extreme. Fib 1.0 = prior opposite swing. |
| 4 | v1 scope | **One magic / one chart only.** Multi-symbol later. |

Interfaces above are frozen. CODER 3 implements against this doc; CODER 2 hardens edge cases; Grok Bot reviews before ship.
