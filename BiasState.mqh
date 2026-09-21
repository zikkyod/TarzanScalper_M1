//+------------------------------------------------------------------+
//| BiasState.mqh — CBiasState (long/short bias; flip on stop-out)   |
//| Architecture: FROZEN — Grok Bot approved 2026-09-21               |
//+------------------------------------------------------------------+
#ifndef TARZAN_BIAS_STATE_MQH
#define TARZAN_BIAS_STATE_MQH

enum ENUM_TARZAN_BIAS
  {
   BIAS_NONE  = 0,
   BIAS_LONG  = 1,
   BIAS_SHORT = 2
  };

enum ENUM_TARZAN_PHASE
  {
   PHASE_IDLE          = 0,  // no bias / waiting
   PHASE_BIAS_SET      = 1,  // bias set but Fib not yet valid (post-SL wait)
   PHASE_FIB_DRAWN     = 2,  // Fib valid, can place limits
   PHASE_LIMIT_PENDING = 3,
   PHASE_IN_TRADE      = 4
  };

//+------------------------------------------------------------------+
class CBiasState
  {
private:
   ENUM_TARZAN_BIAS  m_bias;
   ENUM_TARZAN_PHASE m_phase;
   bool              m_awaiting_bos_after_sl; // LOCKED: after SL flip, wait next BOS before Fib
   datetime          m_last_bos_time;
   datetime          m_last_flip_time;
   string            m_last_reason;

public:
                     CBiasState(void)
     {
      Reset();
     }

   void              Reset(void)
     {
      m_bias                 = BIAS_NONE;
      m_phase                = PHASE_IDLE;
      m_awaiting_bos_after_sl = false;
      m_last_bos_time        = 0;
      m_last_flip_time       = 0;
      m_last_reason          = "";
     }

   ENUM_TARZAN_BIAS  Bias(void) const { return m_bias; }
   ENUM_TARZAN_PHASE Phase(void) const { return m_phase; }
   bool              AwaitingBosAfterSl(void) const { return m_awaiting_bos_after_sl; }
   datetime          LastBosTime(void) const { return m_last_bos_time; }
   string            LastReason(void) const { return m_last_reason; }

   string            BiasText(void) const
     {
      if(m_bias == BIAS_LONG)  return "LONG";
      if(m_bias == BIAS_SHORT) return "SHORT";
      return "NONE";
     }

   string            PhaseText(void) const
     {
      switch(m_phase)
        {
         case PHASE_IDLE:          return "IDLE";
         case PHASE_BIAS_SET:      return "BIAS_SET";
         case PHASE_FIB_DRAWN:     return "FIB_DRAWN";
         case PHASE_LIMIT_PENDING: return "LIMIT_PENDING";
         case PHASE_IN_TRADE:      return "IN_TRADE";
        }
      return "?";
     }

   // Called on decisive BOS (close-only). Sets bias; caller redraws Fib unless awaiting cleared.
   void              OnDecisiveBos(const ENUM_TARZAN_BIAS new_bias, const datetime bos_time)
     {
      m_bias                  = new_bias;
      m_awaiting_bos_after_sl = false; // next BOS after SL unlocks Fib redraw
      m_last_bos_time         = bos_time;
      m_phase                 = PHASE_BIAS_SET; // Fib redraw happens next; then FIB_DRAWN
      m_last_reason           = "Decisive BOS → " + BiasText();
     }

   void              OnFibDrawn(void)
     {
      if(m_awaiting_bos_after_sl)
         return; // invariant: never Fib on dirty post-SL
      if(m_bias == BIAS_NONE)
         return;
      m_phase       = PHASE_FIB_DRAWN;
      m_last_reason = "Fib drawn";
     }

   void              OnLimitPending(void)
     {
      if(m_phase == PHASE_FIB_DRAWN || m_phase == PHASE_LIMIT_PENDING)
        {
         m_phase       = PHASE_LIMIT_PENDING;
         m_last_reason = "Limit pending";
        }
     }

   void              OnFilled(void)
     {
      m_phase       = PHASE_IN_TRADE;
      m_last_reason = "Position open";
     }

   // TP: keep bias until opposite BOS or stop-out flip
   void              OnTakeProfit(void)
     {
      m_phase       = PHASE_FIB_DRAWN; // bias retained; Fib may still be valid or redrawn later
      m_last_reason = "TP — bias kept";
     }

   // LOCKED §3.3: flip bias + cancel pendings (caller) + CLEAR Fib (caller) + wait next BOS
   void              OnStopOutFlip(void)
     {
      if(m_bias == BIAS_LONG)
         m_bias = BIAS_SHORT;
      else if(m_bias == BIAS_SHORT)
         m_bias = BIAS_LONG;
      else
         m_bias = BIAS_NONE;

      m_awaiting_bos_after_sl = true;
      m_phase                 = PHASE_BIAS_SET; // flipped but Fib cleared — wait BOS
      m_last_flip_time        = TimeCurrent();
      m_last_reason           = "SL flip → " + BiasText() + " (wait next BOS)";
     }

   void              ClearFibPhase(void)
     {
      // After invalidation without flip
      if(m_awaiting_bos_after_sl)
         m_phase = PHASE_BIAS_SET;
      else if(m_bias != BIAS_NONE)
         m_phase = PHASE_BIAS_SET;
      else
         m_phase = PHASE_IDLE;
     }

   // May redraw Fib only when bias set AND not waiting post-SL BOS
   bool              CanRedrawFib(void) const
     {
      return (m_bias != BIAS_NONE && !m_awaiting_bos_after_sl);
     }

   bool              CanPlaceLimit(void) const
     {
      return (m_phase == PHASE_FIB_DRAWN || m_phase == PHASE_LIMIT_PENDING)
             && !m_awaiting_bos_after_sl
             && m_bias != BIAS_NONE;
     }
  };

#endif
//+------------------------------------------------------------------+
