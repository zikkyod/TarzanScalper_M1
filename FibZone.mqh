//+------------------------------------------------------------------+
//| FibZone.mqh — CFibZone (Fib from BOS swing pair; zone 0.50–0.618)|
//| Architecture: FROZEN — Grok Bot approved 2026-09-21               |
//| Fib 0.0 = broken swing level; Fib 1.0 = prior opposite swing     |
//+------------------------------------------------------------------+
#ifndef TARZAN_FIB_ZONE_MQH
#define TARZAN_FIB_ZONE_MQH

#include "BiasState.mqh"
#include "SwingEngine.mqh"
#include "BosDetector.mqh"

//+------------------------------------------------------------------+
class CFibZone
  {
private:
   bool              m_valid;
   ENUM_TARZAN_BIAS  m_bias;
   double            m_fib0;   // broken swing (impulse end)
   double            m_fib1;   // origin / SL side
   double            m_level50;
   double            m_level618;
   datetime          m_drawn_time;
   int               m_drawn_bar;
   int               m_max_age_bars; // 0 = disabled
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   string            m_obj_prefix;

   double            LevelAt(const double ratio) const
     {
      // Standard: price = fib0 + (fib1 - fib0) * ratio
      // At 0.0 → fib0 (broken), at 1.0 → fib1 (origin)
      return m_fib0 + (m_fib1 - m_fib0) * ratio;
     }

   void              RecalcLevels(void)
     {
      m_level50  = LevelAt(0.50);
      m_level618 = LevelAt(0.618);
     }

   void              DeleteObjects(void)
     {
      ObjectDelete(0, m_obj_prefix + "F0");
      ObjectDelete(0, m_obj_prefix + "F50");
      ObjectDelete(0, m_obj_prefix + "F618");
      ObjectDelete(0, m_obj_prefix + "F1");
      ObjectDelete(0, m_obj_prefix + "ZONE");
     }

   void              DrawObjects(void)
     {
      if(!m_valid)
         return;
      datetime t1 = m_drawn_time;
      datetime t2 = t1 + PeriodSeconds(m_tf) * 40;
      color col0   = clrDodgerBlue;
      color col1   = clrOrangeRed;
      color col50  = clrGold;
      color col618 = clrGoldenrod;

      ObjectCreate(0, m_obj_prefix + "F0", OBJ_HLINE, 0, 0, m_fib0);
      ObjectSetInteger(0, m_obj_prefix + "F0", OBJPROP_COLOR, col0);
      ObjectSetInteger(0, m_obj_prefix + "F0", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetString(0, m_obj_prefix + "F0", OBJPROP_TEXT, "Fib 0.0");

      ObjectCreate(0, m_obj_prefix + "F1", OBJ_HLINE, 0, 0, m_fib1);
      ObjectSetInteger(0, m_obj_prefix + "F1", OBJPROP_COLOR, col1);
      ObjectSetInteger(0, m_obj_prefix + "F1", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetString(0, m_obj_prefix + "F1", OBJPROP_TEXT, "Fib 1.0 SL");

      ObjectCreate(0, m_obj_prefix + "F50", OBJ_HLINE, 0, 0, m_level50);
      ObjectSetInteger(0, m_obj_prefix + "F50", OBJPROP_COLOR, col50);
      ObjectSetInteger(0, m_obj_prefix + "F50", OBJPROP_STYLE, STYLE_DASH);

      ObjectCreate(0, m_obj_prefix + "F618", OBJ_HLINE, 0, 0, m_level618);
      ObjectSetInteger(0, m_obj_prefix + "F618", OBJPROP_COLOR, col618);
      ObjectSetInteger(0, m_obj_prefix + "F618", OBJPROP_WIDTH, 2);

      // Zone rectangle
      ObjectCreate(0, m_obj_prefix + "ZONE", OBJ_RECTANGLE, 0, t1, m_level50, t2, m_level618);
      ObjectSetInteger(0, m_obj_prefix + "ZONE", OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, m_obj_prefix + "ZONE", OBJPROP_FILL, true);
      ObjectSetInteger(0, m_obj_prefix + "ZONE", OBJPROP_BACK, true);
      ObjectSetInteger(0, m_obj_prefix + "ZONE", OBJPROP_STYLE, STYLE_SOLID);
     }

public:
                     CFibZone(void)
     {
      m_valid        = false;
      m_bias         = BIAS_NONE;
      m_fib0         = 0.0;
      m_fib1         = 0.0;
      m_level50      = 0.0;
      m_level618     = 0.0;
      m_drawn_time   = 0;
      m_drawn_bar    = 0;
      m_max_age_bars = 0;
      m_symbol       = NULL;
      m_tf           = PERIOD_M1;
      m_obj_prefix   = "TarzanFib_";
     }

                    ~CFibZone(void)
     {
      Clear();
     }

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                          const int max_age_bars = 0, const string obj_prefix = "TarzanFib_")
     {
      m_symbol       = symbol;
      m_tf           = tf;
      m_max_age_bars = max_age_bars;
      m_obj_prefix   = obj_prefix;
      Clear();
      return true;
     }

   bool              IsValid(void) const { return m_valid; }
   ENUM_TARZAN_BIAS  Bias(void) const { return m_bias; }
   double            Fib0(void) const { return m_fib0; }
   double            Fib1(void) const { return m_fib1; }
   double            Level50(void) const { return m_level50; }
   double            Level618(void) const { return m_level618; }

   // Price at arbitrary fib ratio (0.0..1.0)
   double            PriceAt(const double ratio) const
     {
      if(!m_valid)
         return 0.0;
      return LevelAt(ratio);
     }

   // LOCKED redraw from BOS event only (never from bare stop-out)
   bool              Redraw(const SBosEvent &bos)
     {
      if(!bos.valid)
         return false;
      if(bos.broken_swing.price == bos.origin_swing.price)
         return false;

      m_bias       = bos.bias;
      m_fib0       = bos.broken_swing.price; // LOCKED: broken swing, NOT BOS-bar extreme
      m_fib1       = bos.origin_swing.price; // LOCKED: prior opposite swing
      m_drawn_time = bos.bar_time;
      m_valid      = true;
      RecalcLevels();
      DeleteObjects();
      DrawObjects();
      return true;
     }

   void              Clear(void)
     {
      m_valid = false;
      m_bias  = BIAS_NONE;
      m_fib0  = m_fib1 = m_level50 = m_level618 = 0.0;
      DeleteObjects();
     }

   // Optional age invalidation
   bool              CheckAge(void)
     {
      if(!m_valid || m_max_age_bars <= 0)
         return m_valid;
      datetime t[];
      ArraySetAsSeries(t, true);
      if(CopyTime(m_symbol, m_tf, 0, 1, t) != 1)
         return m_valid;
      int bars = Bars(m_symbol, m_tf, m_drawn_time, t[0]);
      if(bars > m_max_age_bars)
        {
         Clear();
         return false;
        }
      return true;
     }

   // Is price inside gold zone [0.50, 0.618] inclusive (price space)
   bool              PriceInZone(const double price) const
     {
      if(!m_valid)
         return false;
      double lo = MathMin(m_level50, m_level618);
      double hi = MathMax(m_level50, m_level618);
      return (price >= lo && price <= hi);
     }

   // Preferred limit price per entry rules
   // Prefer 0.618; if price already inside zone past 0.618 toward 0.50, use zone edge still ≥0.50;
   // if price already through 0.50 toward origin — no chase (return 0 / false).
   bool              PreferredLimitPrice(const bool prefer_0618, double &limit_out) const
     {
      limit_out = 0.0;
      if(!m_valid)
         return false;

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0)
         return false;

      const double p50  = m_level50;
      const double p618 = m_level618;

      if(m_bias == BIAS_LONG)
        {
         // Pullback down into zone: fib0 (high) → fib1 (low); 0.618 is deeper (lower)
         // Zone between p50 and p618; for long typically p618 < p50 (retracement down)
         double zone_deep = MathMin(p50, p618); // deeper pullback
         double zone_shallow = MathMax(p50, p618);
         // Preferred = 0.618 level
         double pref = prefer_0618 ? p618 : p50;

         // If price already through shallow edge (0.50) toward origin (below deeper for long) — no chase
         // Long pullback: price falling from fib0 toward fib1. Through 0.50 toward origin means price < zone_deep
         if(bid < zone_deep)
            return false; // already through zone toward SL — no chase

         // If price already inside zone and past 0.618 toward 0.50 (i.e. bounced up from deep)
         if(bid <= zone_shallow && bid >= zone_deep)
           {
            // Place at current zone edge still ≥0.50 side — use bid capped into zone, prefer deep if still available
            if(prefer_0618 && bid <= p618)
               limit_out = p618;
            else
               limit_out = MathMax(bid, zone_deep); // rest at current or deep edge
            // Ensure inside [zone_deep, zone_shallow]
            limit_out = MathMax(zone_deep, MathMin(zone_shallow, limit_out));
            return true;
           }

         // Price still above zone — place limit at preferred
         limit_out = pref;
         return true;
        }

      if(m_bias == BIAS_SHORT)
        {
         // Pullback up into zone: fib0 (low) → fib1 (high); 0.618 deeper (higher)
         double zone_deep = MathMax(p50, p618);
         double zone_shallow = MathMin(p50, p618);
         double pref = prefer_0618 ? p618 : p50;

         // Through 0.50 toward origin means price > zone_deep — no chase
         if(ask > zone_deep)
            return false;

         if(ask >= zone_shallow && ask <= zone_deep)
           {
            if(prefer_0618 && ask >= p618)
               limit_out = p618;
            else
               limit_out = MathMin(ask, zone_deep);
            limit_out = MathMin(zone_deep, MathMax(zone_shallow, limit_out));
            return true;
           }

         limit_out = pref;
         return true;
        }

      return false;
     }
  };

#endif
//+------------------------------------------------------------------+
