//+------------------------------------------------------------------+
//| RiskEngine.mqh — CRiskEngine (SL@Fib1.0, TP structural, RR gate) |
//| Architecture: FROZEN — Grok Bot approved 2026-09-21               |
//| Default InpMinRR = 1.5                                            |
//+------------------------------------------------------------------+
#ifndef TARZAN_RISK_ENGINE_MQH
#define TARZAN_RISK_ENGINE_MQH

#include "BiasState.mqh"
#include "FibZone.mqh"
#include "SwingEngine.mqh"

struct SRiskPlan
  {
   bool     valid;
   double   entry;
   double   sl;
   double   tp;
   double   lots;
   double   rr;
   string   skip_reason;
  };

//+------------------------------------------------------------------+
class CRiskEngine
  {
private:
   string            m_symbol;
   double            m_min_rr;          // default 1.5
   double            m_risk_percent;
   double            m_fixed_lots;      // if > 0, use fixed lots instead of risk-%
   double            m_sl_buffer_points;
   double            m_tp_buffer_points;

   double            PointSize(void) const
     {
      double p = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      return (p > 0.0 ? p : _Point);
     }

   int               StopsLevelPoints(void) const
     {
      return (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
     }

   double            NormalizePrice(const double price) const
     {
      return NormalizeDouble(price, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
     }

public:
                     CRiskEngine(void)
     {
      m_symbol            = NULL;
      m_min_rr            = 1.5;
      m_risk_percent      = 2.0;
      m_fixed_lots        = 0.0;
      m_sl_buffer_points  = 0.0;
      m_tp_buffer_points  = 0.0;
     }

   bool              Init(const string symbol,
                          const double min_rr,
                          const double risk_percent,
                          const double fixed_lots,
                          const double sl_buffer_points,
                          const double tp_buffer_points)
     {
      m_symbol            = symbol;
      m_min_rr            = (min_rr > 0.0 ? min_rr : 1.5);
      m_risk_percent      = risk_percent;
      m_fixed_lots        = fixed_lots;
      m_sl_buffer_points  = sl_buffer_points;
      m_tp_buffer_points  = tp_buffer_points;
      return true;
     }

   double            CalcLot(const double entry, const double sl) const
     {
      if(m_fixed_lots > 0.0)
        {
         double vmin = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
         double vmax = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
         double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
         double lots = m_fixed_lots;
         if(step > 0.0)
            lots = MathFloor(lots / step) * step;
         lots = MathMax(vmin, MathMin(vmax, lots));
         return NormalizeDouble(lots, 2);
        }

      double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * (m_risk_percent / 100.0);
      if(risk_money <= 0.0)
         return 0.0;

      double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size <= 0.0 || tick_value <= 0.0)
         return 0.0;

      double sl_dist = MathAbs(entry - sl);
      if(sl_dist <= 0.0)
         return 0.0;

      double loss_per_lot = (sl_dist / tick_size) * tick_value;
      if(loss_per_lot <= 0.0)
         return 0.0;

      double lots = risk_money / loss_per_lot;
      double vmin = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double vmax = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(step > 0.0)
         lots = MathFloor(lots / step) * step;
      lots = MathMax(vmin, MathMin(vmax, lots));
      if(lots < vmin)
         return 0.0;
      return NormalizeDouble(lots, 2);
     }

   // Build SL/TP/lots; RR gate. Never lowers SL.
   bool              BuildPlan(const ENUM_TARZAN_BIAS bias,
                               const CFibZone &fib,
                               const double entry,
                               CSwingEngine &swings,
                               SRiskPlan &plan)
     {
      ZeroMemory(plan);
      plan.valid = false;
      plan.skip_reason = "";

      if(!fib.IsValid() || entry <= 0.0 || bias == BIAS_NONE)
        {
         plan.skip_reason = "Invalid fib/entry/bias";
         return false;
        }

      double pt  = PointSize();
      double slb = m_sl_buffer_points * pt;
      double tpb = m_tp_buffer_points * pt;

      // SL always Fib 1.0 (+ buffer away from entry)
      double sl = fib.Fib1();
      if(bias == BIAS_LONG)
         sl = sl - slb; // below origin for long
      else
         sl = sl + slb;

      // TP near prior swing in trade direction
      SSwingPoint tp_swing;
      double tp = 0.0;
      if(swings.TpSwingForBias(bias, entry, tp_swing))
         tp = tp_swing.price;
      else
        {
         // Fallback: use Fib 0.0 (broken swing / impulse extreme) as structural target
         tp = fib.Fib0();
        }

      if(bias == BIAS_LONG)
         tp = tp + tpb;
      else
         tp = tp - tpb;

      // Ensure TP is on correct side of entry
      if(bias == BIAS_LONG && tp <= entry)
        {
         // try Fib 0.0
         tp = fib.Fib0() + tpb;
         if(tp <= entry)
           {
            plan.skip_reason = "TP not above entry";
            return false;
           }
        }
      if(bias == BIAS_SHORT && tp >= entry)
        {
         tp = fib.Fib0() - tpb;
         if(tp >= entry)
           {
            plan.skip_reason = "TP not below entry";
            return false;
           }
        }

      // Ensure SL on correct side
      if(bias == BIAS_LONG && sl >= entry)
        {
         plan.skip_reason = "SL not below entry";
         return false;
        }
      if(bias == BIAS_SHORT && sl <= entry)
        {
         plan.skip_reason = "SL not above entry";
         return false;
        }

      // Broker stops level clamp (widen SL / shrink TP if needed — never lower SL toward entry)
      int stops = StopsLevelPoints();
      double min_dist = stops * pt;
      if(min_dist > 0.0)
        {
         if(bias == BIAS_LONG)
           {
            if(entry - sl < min_dist)
               sl = entry - min_dist;
            if(tp - entry < min_dist)
               tp = entry + min_dist;
           }
         else
           {
            if(sl - entry < min_dist)
               sl = entry + min_dist;
            if(entry - tp < min_dist)
               tp = entry - min_dist;
           }
        }

      double risk   = MathAbs(entry - sl);
      double reward = MathAbs(tp - entry);
      if(risk <= 0.0)
        {
         plan.skip_reason = "Zero risk";
         return false;
        }
      double rr = reward / risk;
      if(rr < m_min_rr)
        {
         plan.skip_reason = StringFormat("RR %.2f < MinRR %.2f", rr, m_min_rr);
         return false;
        }

      double lots = CalcLot(entry, sl);
      if(lots <= 0.0)
        {
         plan.skip_reason = "Lot size zero";
         return false;
        }

      plan.valid  = true;
      plan.entry  = NormalizePrice(entry);
      plan.sl     = NormalizePrice(sl);
      plan.tp     = NormalizePrice(tp);
      plan.lots   = lots;
      plan.rr     = rr;
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
