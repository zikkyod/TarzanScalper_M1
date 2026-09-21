//+------------------------------------------------------------------+
//| SwingEngine.mqh — CSwingEngine (pivot detection + ring buffer)   |
//| Architecture: FROZEN — Grok Bot approved 2026-09-21               |
//+------------------------------------------------------------------+
#ifndef TARZAN_SWING_ENGINE_MQH
#define TARZAN_SWING_ENGINE_MQH

#include "BiasState.mqh"

#define TARZAN_SWING_BUF 8

enum ENUM_SWING_TYPE
  {
   SWING_NONE = 0,
   SWING_HIGH = 1,
   SWING_LOW  = 2
  };

struct SSwingPoint
  {
   ENUM_SWING_TYPE type;
   double          price;
   datetime        time;
   int             bar_index; // relative at detection time (informational)
  };

//+------------------------------------------------------------------+
class CSwingEngine
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_swing_n;           // pivot wing
   double            m_min_swing_points;  // price distance in points
   double            m_min_swing_atr_mult;
   int               m_atr_period;
   int               m_atr_handle;
   SSwingPoint       m_swings[TARZAN_SWING_BUF];
   int               m_count;
   datetime          m_last_bar_time;

   double            PointSize(void) const
     {
      double p = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      return (p > 0.0 ? p : _Point);
     }

   double            MinDistancePrice(void)
     {
      double dist = m_min_swing_points * PointSize();
      if(m_min_swing_atr_mult > 0.0 && m_atr_handle != INVALID_HANDLE)
        {
         double atr[];
         ArraySetAsSeries(atr, true);
         if(CopyBuffer(m_atr_handle, 0, 1, 1, atr) == 1 && atr[0] > 0.0)
           {
            double atr_dist = atr[0] * m_min_swing_atr_mult;
            if(atr_dist > dist)
               dist = atr_dist;
           }
        }
      return dist;
     }

   void              PushSwing(const ENUM_SWING_TYPE type, const double price, const datetime time, const int bar_index)
     {
      // Shift right; newest at index 0
      for(int i = TARZAN_SWING_BUF - 1; i > 0; i--)
         m_swings[i] = m_swings[i - 1];
      m_swings[0].type      = type;
      m_swings[0].price     = price;
      m_swings[0].time      = time;
      m_swings[0].bar_index = bar_index;
      if(m_count < TARZAN_SWING_BUF)
         m_count++;
     }

   bool              PassesMinDistance(const ENUM_SWING_TYPE type, const double price)
     {
      // Reject if closer than min distance to previous opposite pivot
      ENUM_SWING_TYPE opposite = (type == SWING_HIGH ? SWING_LOW : SWING_HIGH);
      for(int i = 0; i < m_count; i++)
        {
         if(m_swings[i].type == opposite)
           {
            double d = MathAbs(price - m_swings[i].price);
            if(d < MinDistancePrice())
               return false;
            break; // check nearest opposite only
           }
        }
      // Also reject duplicate same-side micro swings closer than min to last same type
      for(int i = 0; i < m_count; i++)
        {
         if(m_swings[i].type == type)
           {
            double d = MathAbs(price - m_swings[i].price);
            if(d < MinDistancePrice() * 0.5)
               return false;
            break;
           }
        }
      return true;
     }

public:
                     CSwingEngine(void)
     {
      m_symbol            = NULL;
      m_tf                = PERIOD_M1;
      m_swing_n           = 3;
      m_min_swing_points  = 50.0;
      m_min_swing_atr_mult = 0.0;
      m_atr_period        = 14;
      m_atr_handle        = INVALID_HANDLE;
      m_count             = 0;
      m_last_bar_time     = 0;
      ZeroMemory(m_swings);
     }

                    ~CSwingEngine(void)
     {
      if(m_atr_handle != INVALID_HANDLE)
        {
         IndicatorRelease(m_atr_handle);
         m_atr_handle = INVALID_HANDLE;
        }
     }

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                          const int swing_n,
                          const double min_swing_points,
                          const double min_swing_atr_mult = 0.0,
                          const int atr_period = 14)
     {
      m_symbol            = symbol;
      m_tf                = tf;
      m_swing_n           = MathMax(2, swing_n);
      m_min_swing_points  = min_swing_points;
      m_min_swing_atr_mult = min_swing_atr_mult;
      m_atr_period        = atr_period;
      m_count             = 0;
      m_last_bar_time     = 0;
      ZeroMemory(m_swings);

      if(m_atr_handle != INVALID_HANDLE)
        {
         IndicatorRelease(m_atr_handle);
         m_atr_handle = INVALID_HANDLE;
        }
      if(m_min_swing_atr_mult > 0.0)
        {
         m_atr_handle = iATR(m_symbol, m_tf, m_atr_period);
         if(m_atr_handle == INVALID_HANDLE)
            return false;
        }
      return true;
     }

   int               Count(void) const { return m_count; }

   bool              GetSwing(const int idx, SSwingPoint &out) const
     {
      if(idx < 0 || idx >= m_count)
         return false;
      out = m_swings[idx];
      return true;
     }

   bool              LastSwingHigh(SSwingPoint &out) const
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_swings[i].type == SWING_HIGH)
           {
            out = m_swings[i];
            return true;
           }
        }
      return false;
     }

   bool              LastSwingLow(SSwingPoint &out) const
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_swings[i].type == SWING_LOW)
           {
            out = m_swings[i];
            return true;
           }
        }
      return false;
     }

   // Prior opposite swing relative to a broken swing (for Fib 1.0)
   // Prefer swing of opposite type that occurred BEFORE the broken swing time.
   bool              PriorOppositeSwing(const SSwingPoint &broken, SSwingPoint &out) const
     {
      ENUM_SWING_TYPE need = (broken.type == SWING_HIGH ? SWING_LOW : SWING_HIGH);
      for(int i = 0; i < m_count; i++)
        {
         if(m_swings[i].type == need && m_swings[i].time < broken.time)
           {
            out = m_swings[i];
            return true;
           }
        }
      // Fallback: any opposite regardless of time order
      for(int i = 0; i < m_count; i++)
        {
         if(m_swings[i].type == need)
           {
            out = m_swings[i];
            return true;
           }
        }
      return false;
     }

   // Structural TP target: next swing in trade direction beyond entry
   bool              TpSwingForBias(const ENUM_TARZAN_BIAS bias, const double entry, SSwingPoint &out) const
     {
      // Long → relevant swing high above entry; Short → swing low below entry
      if(bias == BIAS_LONG)
        {
         for(int i = 0; i < m_count; i++)
           {
            if(m_swings[i].type == SWING_HIGH && m_swings[i].price > entry)
              {
               out = m_swings[i];
               return true;
              }
           }
         // Fallback: most recent swing high
         return LastSwingHigh(out);
        }
      if(bias == BIAS_SHORT)
        {
         for(int i = 0; i < m_count; i++)
           {
            if(m_swings[i].type == SWING_LOW && m_swings[i].price < entry)
              {
               out = m_swings[i];
               return true;
              }
           }
         return LastSwingLow(out);
        }
      return false;
     }

   // Scan confirmed pivots on new bar. Bar 0 is forming — never use as right wing.
   // Confirmed pivot candidate at bar index = swing_n (series), once right wing complete.
   void              Update(void)
     {
      datetime t[];
      ArraySetAsSeries(t, true);
      if(CopyTime(m_symbol, m_tf, 0, 1, t) != 1)
         return;
      if(t[0] == m_last_bar_time)
         return; // only on new bar
      m_last_bar_time = t[0];

      int need = m_swing_n * 2 + 3;
      double hi[], lo[];
      datetime tm[];
      ArraySetAsSeries(hi, true);
      ArraySetAsSeries(lo, true);
      ArraySetAsSeries(tm, true);
      if(CopyHigh(m_symbol, m_tf, 0, need, hi) < need)
         return;
      if(CopyLow(m_symbol, m_tf, 0, need, lo) < need)
         return;
      if(CopyTime(m_symbol, m_tf, 0, need, tm) < need)
         return;

      // Candidate pivot at index m_swing_n (fully confirmed; bars 1..n-1 are right side, n+1.. are left)
      const int i = m_swing_n;
      // Skip if we already recorded this bar time as a swing
      for(int k = 0; k < m_count; k++)
        {
         if(m_swings[k].time == tm[i])
            return;
        }

      bool is_high = true;
      bool is_low  = true;
      for(int j = 1; j <= m_swing_n; j++)
        {
         if(hi[i] <= hi[i - j] || hi[i] <= hi[i + j])
            is_high = false;
         if(lo[i] >= lo[i - j] || lo[i] >= lo[i + j])
            is_low = false;
        }

      if(is_high && PassesMinDistance(SWING_HIGH, hi[i]))
         PushSwing(SWING_HIGH, hi[i], tm[i], i);
      else if(is_low && PassesMinDistance(SWING_LOW, lo[i]))
         PushSwing(SWING_LOW, lo[i], tm[i], i);
     }
  };

#endif
//+------------------------------------------------------------------+
