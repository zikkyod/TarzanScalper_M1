//+------------------------------------------------------------------+
//| EntryEngine.mqh — CEntryEngine (limits in 0.50–0.618 only)       |
//| Architecture: FROZEN — never BOS-only entries; prefer 0.618      |
//+------------------------------------------------------------------+
#ifndef TARZAN_ENTRY_ENGINE_MQH
#define TARZAN_ENTRY_ENGINE_MQH

#include "BiasState.mqh"
#include "FibZone.mqh"
#include "RiskEngine.mqh"
#include "TradeManager.mqh"
#include "SwingEngine.mqh"

//+------------------------------------------------------------------+
class CEntryEngine
  {
private:
   string            m_symbol;
   bool              m_prefer_0618;
   double            m_zone_lo; // 0.50
   double            m_zone_hi; // 0.618
   int               m_max_positions; // = 1
   int               m_max_spread_points;
   int               m_max_spread_points_gold;
   bool              m_enable_trading;
   string            m_block_reason;

   double            PointSize(void) const
     {
      double p = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      return (p > 0.0 ? p : _Point);
     }

   bool              IsGoldSymbol(void) const
     {
      string s = m_symbol;
      StringToUpper(s);
      return (StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0);
     }

   int               EffectiveMaxSpread(void) const
     {
      if(IsGoldSymbol() && m_max_spread_points_gold > 0)
         return m_max_spread_points_gold;
      return m_max_spread_points;
     }

public:
                     CEntryEngine(void)
     {
      m_symbol                 = NULL;
      m_prefer_0618            = true;
      m_zone_lo                = 0.50;
      m_zone_hi                = 0.618;
      m_max_positions          = 1;
      m_max_spread_points      = 30;
      m_max_spread_points_gold = 70;
      m_enable_trading         = false;
      m_block_reason           = "";
     }

   bool              Init(const string symbol,
                          const bool prefer_0618,
                          const double zone_lo,
                          const double zone_hi,
                          const int max_positions,
                          const int max_spread_points,
                          const int max_spread_points_gold,
                          const bool enable_trading)
     {
      m_symbol                 = symbol;
      m_prefer_0618            = prefer_0618;
      m_zone_lo                = zone_lo;
      m_zone_hi                = zone_hi;
      m_max_positions          = MathMax(1, max_positions);
      m_max_spread_points      = max_spread_points;
      m_max_spread_points_gold = max_spread_points_gold;
      m_enable_trading         = enable_trading;
      m_block_reason           = "";
      return true;
     }

   void              SetEnableTrading(const bool en) { m_enable_trading = en; }
   string            BlockReason(void) const { return m_block_reason; }

   int               CurrentSpreadPoints(void) const
     {
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double pt  = PointSize();
      if(pt <= 0.0)
         return 0;
      return (int)MathRound((ask - bid) / pt);
     }

   int               MaxSpreadPoints(void) const { return EffectiveMaxSpread(); }

   // ManageEntries: place / refresh / skip. NEVER enters on BOS alone.
   // Call only when Fib valid and bias allows limits.
   void              ManageEntries(CBiasState &bias,
                                   CFibZone &fib,
                                   CRiskEngine &risk,
                                   CTradeManager &tm,
                                   CSwingEngine &swings)
     {
      m_block_reason = "";

      if(!m_enable_trading)
        {
         m_block_reason = "EnableTrading=false (analysis only)";
         return;
        }

      if(bias.AwaitingBosAfterSl())
        {
         m_block_reason = "Post-SL: waiting next decisive BOS";
         return;
        }

      if(!bias.CanPlaceLimit())
        {
         m_block_reason = "Phase not ready for limit (" + bias.PhaseText() + ")";
         return;
        }

      if(!fib.IsValid())
        {
         m_block_reason = "Fib invalid";
         return;
        }

      if(tm.HasPosition())
        {
         bias.OnFilled();
         m_block_reason = "Position open (max=1)";
         return;
        }

      int spread = CurrentSpreadPoints();
      int maxsp  = EffectiveMaxSpread();
      if(maxsp > 0 && spread > maxsp)
        {
         m_block_reason = StringFormat("Spread %d > max %d", spread, maxsp);
         return;
        }

      double limit_px = 0.0;
      if(!fib.PreferredLimitPrice(m_prefer_0618, limit_px) || limit_px <= 0.0)
        {
         m_block_reason = "No chase / zone unavailable";
         // Cancel stale if structure moved through zone
         if(tm.HasPending())
            tm.CancelAllPendings();
         return;
        }

      // Sanity: limit must sit in [0.50, 0.618] price band
      double lo = MathMin(fib.Level50(), fib.Level618());
      double hi = MathMax(fib.Level50(), fib.Level618());
      if(limit_px < lo || limit_px > hi)
        {
         m_block_reason = "Limit outside gold zone";
         return;
        }

      SRiskPlan plan;
      if(!risk.BuildPlan(bias.Bias(), fib, limit_px, swings, plan))
        {
         m_block_reason = plan.skip_reason;
         if(tm.HasPending())
            tm.CancelAllPendings(); // RR fail / invalid — don't leave stale
         return;
        }

      // If pending already exists at same price (±1 point), keep it
      if(tm.HasPending())
        {
         // Refresh on Fib redraw is caller's job via Cancel+replace; here replace if needed
         tm.CancelAllPendings();
        }

      if(!tm.PlaceLimit(bias.Bias(), plan))
        {
         m_block_reason = tm.LastError();
         return;
        }

      bias.OnLimitPending();
      m_block_reason = "";
     }

   // Cancel stale pendings when structure invalidates
   void              CancelIfInvalid(CBiasState &bias, CFibZone &fib, CTradeManager &tm)
     {
      if(!fib.IsValid() || bias.AwaitingBosAfterSl() || bias.Bias() == BIAS_NONE)
        {
         if(tm.HasPending())
            tm.CancelAllPendings();
        }
     }
  };

#endif
//+------------------------------------------------------------------+
