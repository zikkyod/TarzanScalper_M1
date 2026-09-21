//+------------------------------------------------------------------+
//| TarzanScalper.mq5 — Gold Zone / Tarzan M1 Scalper                 |
//| Architecture: FROZEN — Grok Bot approved 2026-09-21               |
//| Demo-first. One magic / one chart. No BOS-only entries.           |
//+------------------------------------------------------------------+
#property copyright "Gold Zone / Tarzan"
#property link      ""
#property version   "1.10"
#property description "Tarzan M1 Gold Zone scalper: BOS bias → Fib pullback limits (0.50–0.618)"
#property description "NEVER enters on BOS alone. Demo-first; EnableTrading=false by default."

#include "BiasState.mqh"
#include "SwingEngine.mqh"
#include "BosDetector.mqh"
#include "FibZone.mqh"
#include "RiskEngine.mqh"
#include "TradeManager.mqh"
#include "EntryEngine.mqh"

//--- Inputs (v1 + CODER 3 ship brief)
input group "=== Trading ==="
input bool     InpEnableTrading        = false;   // EnableTrading (false = analysis + status only)
input double   InpRiskPercent          = 2.0;     // RiskPercent of equity per trade
input double   InpFixedLots            = 0.0;     // FixedLots (0 = use RiskPercent)
input int      InpMaxSpreadPoints      = 30;      // MaxSpreadPoints (FX 25–35; gold use Gold input)
input int      InpMaxSpreadPointsGold  = 70;      // MaxSpreadPointsGold (XAU*/GOLD auto)
input ulong    InpMagic                = 1102026; // Magic (one chart = one magic)
input ulong    InpSlippage             = 10;      // Slippage points
input int      InpMaxPositions         = 1;       // MaxPositions (v1 locked = 1)

input group "=== Structure / BOS ==="
input int      InpSwingN               = 3;       // SwingN pivot wing
input double   InpMinSwingPoints       = 80.0;    // MinSwingPoints (price points)
input double   InpMinSwingAtrMult      = 0.5;     // MinSwingAtrMult (0=off)
input double   InpBosBufferPoints      = 0.0;     // BosBufferPoints beyond swing for close

input group "=== Fib / Entry ==="
input bool     InpPrefer0618           = true;    // Prefer0618 (deeper pullback)
input double   InpZoneLo               = 0.50;    // ZoneLo
input double   InpZoneHi               = 0.618;   // ZoneHi
input int      InpFibMaxAgeBars        = 0;       // FibMaxAgeBars (0=off)

input group "=== Risk ==="
input double   InpMinRR                = 1.5;     // MinRR (LOCKED default 1.5)
input double   InpSlBufferPoints       = 5.0;     // SlBufferPoints beyond Fib 1.0
input double   InpTpBufferPoints       = 0.0;     // TpBufferPoints at structural TP
input bool     InpFlipOnStopOut        = true;    // FlipOnStopOut (LOCKED behavior when true)

input group "=== Display ==="
input bool     InpShowStatus           = true;    // Show chart Comment status

//--- Modules
CBiasState     g_bias;
CSwingEngine   g_swings;
CBosDetector   g_bos;
CFibZone       g_fib;
CRiskEngine    g_risk;
CTradeManager  g_tm;
CEntryEngine   g_entry;

string         g_status_block = "";

//+------------------------------------------------------------------+
int OnInit()
  {
   // Demo-first note
   Print("TarzanScalper v1.10 — demo-first. EnableTrading=", InpEnableTrading,
         " Magic=", InpMagic, " Symbol=", _Symbol, " TF=", EnumToString(_Period));

   if(_Period != PERIOD_M1)
      Print("WARNING: Designed for M1. Current TF=", EnumToString(_Period));

   if(InpMaxPositions != 1)
      Print("WARNING: v1 architecture locks MaxPositions=1; input will be clamped.");

   if(!g_swings.Init(_Symbol, _Period, InpSwingN, InpMinSwingPoints, InpMinSwingAtrMult))
     {
      Print("SwingEngine init failed");
      return INIT_FAILED;
     }
   if(!g_bos.Init(_Symbol, _Period, InpBosBufferPoints))
      return INIT_FAILED;
   if(!g_fib.Init(_Symbol, _Period, InpFibMaxAgeBars, "TarzanFib_"))
      return INIT_FAILED;
   if(!g_risk.Init(_Symbol, InpMinRR, InpRiskPercent, InpFixedLots,
                   InpSlBufferPoints, InpTpBufferPoints))
      return INIT_FAILED;
   if(!g_tm.Init(_Symbol, InpMagic, InpSlippage))
      return INIT_FAILED;
   if(!g_entry.Init(_Symbol, InpPrefer0618, InpZoneLo, InpZoneHi,
                    1 /* v1 lock */, InpMaxSpreadPoints, InpMaxSpreadPointsGold,
                    InpEnableTrading))
      return INIT_FAILED;

   g_bias.Reset();
   UpdateStatus();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_fib.Clear();
   Comment("");
   Print("TarzanScalper removed. reason=", reason);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // Sync enable flag each tick (input immutable in tester but ok for live toggle via re-attach)
   g_entry.SetEnableTrading(InpEnableTrading);

   // 1) Update swings (new-bar confirmed pivots)
   g_swings.Update();

   // 2) Age-check Fib
   if(g_fib.IsValid() && !g_fib.CheckAge())
     {
      g_bias.ClearFibPhase();
      g_tm.CancelAllPendings();
      g_status_block = "Fib aged out";
     }

   // 3) Decisive BOS on closed bar (close-only)
   SBosEvent bos;
   if(g_bos.Check(g_swings, bos) && bos.valid)
     {
      // Opposite or any decisive BOS: cancel pendings → new bias → new Fib
      // LOCKED: after SL flip we wait for THIS BOS before Fib redraw
      g_tm.CancelAllPendings();
      g_bias.OnDecisiveBos(bos.bias, bos.bar_time);

      if(g_bias.CanRedrawFib())
        {
         if(g_fib.Redraw(bos))
           {
            g_bias.OnFibDrawn();
            g_status_block = "BOS " + g_bias.BiasText() + " → Fib redrawn";
           }
         else
           {
            g_fib.Clear();
            g_bias.ClearFibPhase();
            g_status_block = "BOS but Fib redraw failed";
           }
        }
      else
        {
         // Should not happen: OnDecisiveBos clears awaiting flag
         g_fib.Clear();
         g_status_block = "BOS received but Fib blocked";
        }
     }

   // 4) Sync phase with live position / pendings
   if(g_tm.HasPosition())
      g_bias.OnFilled();
   else if(g_tm.HasPending() && g_fib.IsValid() && !g_bias.AwaitingBosAfterSl())
      g_bias.OnLimitPending();

   // 5) Cancel stale when structure invalid
   g_entry.CancelIfInvalid(g_bias, g_fib, g_tm);

   // 6) Manage limit entries (never on BOS alone — requires valid Fib + phase)
   g_entry.ManageEntries(g_bias, g_fib, g_risk, g_tm, g_swings);

   // 7) Chart status
   UpdateStatus();
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // Focus on deal add (exit)
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.deal == 0)
      return;

   // Ensure history available
   if(!HistoryDealSelect(trans.deal))
      return;

   // Take-profit: keep bias
   if(g_tm.IsOurTakeProfitDeal(trans.deal))
     {
      g_bias.OnTakeProfit();
      g_status_block = "TP hit — bias kept";
      UpdateStatus();
      return;
     }

   // Stop-out flip (LOCKED §3.3)
   if(InpFlipOnStopOut && g_tm.IsOurStopOutDeal(trans.deal))
     {
      // 1) Flip bias immediately
      g_bias.OnStopOutFlip();
      // 2) Cancel all pending limits immediately
      g_tm.CancelAllPendings();
      // 3) Do NOT redraw Fib on dirty post-SL — CLEAR Fib
      g_fib.Clear();
      // 4) Wait for next decisive BOS before Fib redraw / new limit
      g_status_block = "SL flip → " + g_bias.BiasText() + " — wait next BOS (no Fib yet)";
      UpdateStatus();
     }
  }

//+------------------------------------------------------------------+
void UpdateStatus()
  {
   if(!InpShowStatus)
      return;

   int spread = g_entry.CurrentSpreadPoints();
   int maxsp  = g_entry.MaxSpreadPoints();
   string fib_info = "n/a";
   if(g_fib.IsValid())
      fib_info = StringFormat("0.0=%.5f | 0.50=%.5f | 0.618=%.5f | 1.0=%.5f",
                              g_fib.Fib0(), g_fib.Level50(), g_fib.Level618(), g_fib.Fib1());

   string block = g_entry.BlockReason();
   if(block == "" && g_status_block != "")
      block = g_status_block;
   if(block == "")
      block = "(none)";

   string txt = "";
   txt += "=== TarzanScalper v1.10 ===\n";
   txt += StringFormat("Symbol: %s | TF: %s\n", _Symbol, EnumToString(_Period));
   txt += StringFormat("EnableTrading: %s\n", (InpEnableTrading ? "TRUE" : "FALSE"));
   txt += StringFormat("Bias: %s | Phase: %s | AwaitBOS_afterSL: %s\n",
                       g_bias.BiasText(), g_bias.PhaseText(),
                       (g_bias.AwaitingBosAfterSl() ? "YES" : "no"));
   txt += StringFormat("BOS state: %s\n", g_bias.LastReason());
   txt += StringFormat("Gold zone: %s\n", fib_info);
   txt += StringFormat("Spread: %d / max %d pts | Risk: %.2f%% | MinRR: %.2f\n",
                       spread, maxsp, InpRiskPercent, InpMinRR);
   txt += StringFormat("Pos: %s | Pendings: %d | Magic: %s\n",
                       (g_tm.HasPosition() ? "OPEN" : "flat"),
                       g_tm.CountPendings(), IntegerToString((long)InpMagic));
   txt += StringFormat("Block: %s\n", block);
   txt += "All-session (no session filter) | Demo-first\n";

   Comment(txt);
  }

//+------------------------------------------------------------------+
