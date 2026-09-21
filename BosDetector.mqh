//+------------------------------------------------------------------+
//| BosDetector.mqh — Decisive BOS on candle CLOSE only               |
//| Architecture: FROZEN — Grok Bot approved 2026-09-21                 |
//+------------------------------------------------------------------+
#ifndef TARZAN_BOS_DETECTOR_MQH
#define TARZAN_BOS_DETECTOR_MQH

#include "BiasState.mqh"
#include "SwingEngine.mqh"

//+------------------------------------------------------------------+
//| SBosEvent — result of a decisive BOS check                         |
//+------------------------------------------------------------------+
struct SBosEvent
  {
   bool              valid;
   ENUM_TARZAN_BIAS  bias;           // BIAS_LONG = bullish BOS, BIAS_SHORT = bearish
   SSwingPoint       broken_swing;   // Fib 0.0 = broken swing level (LOCKED)
   SSwingPoint       origin_swing;   // Fib 1.0 = prior opposite swing (LOCKED)
   datetime          bar_time;
   double            close_price;
  };

//+------------------------------------------------------------------+
class CBosDetector
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   double            m_bos_buffer_points;
   datetime          m_last_checked_bar;
   datetime          m_last_bos_bar; // prevent double-fire same bar

   double            PointSize(void) const
     {
      double p = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      return (p > 0.0 ? p : _Point);
     }

   double            BufferPrice(void) const
     {
      return m_bos_buffer_points * PointSize();
     }

public:
                     CBosDetector(void)
     {
      m_symbol            = NULL;
      m_tf                = PERIOD_M1;
      m_bos_buffer_points = 0.0;
      m_last_checked_bar  = 0;
      m_last_bos_bar      = 0;
     }

   bool              Init(const string symbol,
                          const ENUM_TIMEFRAMES tf,
                          const double bos_buffer_points)
     {
      m_symbol            = symbol;
      m_tf                = tf;
      m_bos_buffer_points = bos_buffer_points;
      m_last_checked_bar  = 0;
      m_last_bos_bar      = 0;
      return true;
     }

   // Check closed bar (index 1) only — never wick-only, never forming bar.
   // Returns true when a NEW decisive BOS is detected this call.
   bool              Check(CSwingEngine &swings, SBosEvent &ev)
     {
      ZeroMemory(ev);
      ev.valid = false;

      datetime t[];
      double   c[];
      ArraySetAsSeries(t, true);
      ArraySetAsSeries(c, true);
      if(CopyTime(m_symbol, m_tf, 0, 2, t) < 2)
         return false;
      if(CopyClose(m_symbol, m_tf, 0, 2, c) < 2)
         return false;

      // Only evaluate once per newly closed bar
      if(t[1] == m_last_checked_bar)
         return false;
      m_last_checked_bar = t[1];

      if(t[1] == m_last_bos_bar)
         return false;

      const double close1 = c[1];
      const double buf    = BufferPrice();

      SSwingPoint sh, sl;
      bool have_h = swings.LastSwingHigh(sh);
      bool have_l = swings.LastSwingLow(sl);

      // Bullish BOS: close above last swing high (+ optional buffer)
      if(have_h && close1 > sh.price + buf)
        {
         SSwingPoint origin;
         if(!swings.PriorOppositeSwing(sh, origin))
            return false; // need Fib 1.0 anchor

         ev.valid        = true;
         ev.bias         = BIAS_LONG;
         ev.broken_swing = sh;
         ev.origin_swing = origin;
         ev.bar_time     = t[1];
         ev.close_price  = close1;
         m_last_bos_bar  = t[1];
         return true;
        }

      // Bearish BOS: close below last swing low (− optional buffer)
      if(have_l && close1 < sl.price - buf)
        {
         SSwingPoint origin;
         if(!swings.PriorOppositeSwing(sl, origin))
            return false;

         ev.valid        = true;
         ev.bias         = BIAS_SHORT;
         ev.broken_swing = sl;
         ev.origin_swing = origin;
         ev.bar_time     = t[1];
         ev.close_price  = close1;
         m_last_bos_bar  = t[1];
         return true;
        }

      return false;
     }
  };

#endif // TARZAN_BOS_DETECTOR_MQH
//+------------------------------------------------------------------+
