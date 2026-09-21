//+------------------------------------------------------------------+
//| TradeManager.mqh — CTradeManager (place/modify/cancel; magic)    |
//| Architecture: FROZEN — v1 one magic / one chart only              |
//+------------------------------------------------------------------+
#ifndef TARZAN_TRADE_MANAGER_MQH
#define TARZAN_TRADE_MANAGER_MQH

#include <Trade/Trade.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include "BiasState.mqh"
#include "RiskEngine.mqh"

//+------------------------------------------------------------------+
class CTradeManager
  {
private:
   string            m_symbol;
   ulong             m_magic;
   ulong             m_deviation;
   CTrade            m_trade;
   COrderInfo        m_order;
   CPositionInfo     m_pos;
   string            m_last_error;

   bool              IsOurMagic(const ulong magic) const
     {
      return (magic == m_magic);
     }

public:
                     CTradeManager(void)
     {
      m_symbol     = NULL;
      m_magic      = 0;
      m_deviation  = 10;
      m_last_error = "";
     }

   bool              Init(const string symbol, const ulong magic, const ulong slippage)
     {
      m_symbol    = symbol;
      m_magic     = magic;
      m_deviation = slippage;
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints((uint)m_deviation);
      m_trade.SetTypeFillingBySymbol(m_symbol);
      return true;
     }

   string            LastError(void) const { return m_last_error; }
   ulong             Magic(void) const { return m_magic; }

   bool              HasPosition(void)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() == m_symbol && IsOurMagic(m_pos.Magic()))
            return true;
        }
      return false;
     }

   bool              SelectOurPosition(void)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() == m_symbol && IsOurMagic(m_pos.Magic()))
            return true;
        }
      return false;
     }

   int               CountPendings(void)
     {
      int n = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!m_order.SelectByIndex(i))
            continue;
         if(m_order.Symbol() == m_symbol && IsOurMagic(m_order.Magic()))
           {
            ENUM_ORDER_TYPE t = m_order.OrderType();
            if(t == ORDER_TYPE_BUY_LIMIT || t == ORDER_TYPE_SELL_LIMIT ||
               t == ORDER_TYPE_BUY_STOP  || t == ORDER_TYPE_SELL_STOP)
               n++;
           }
        }
      return n;
     }

   bool              HasPending(void)
     {
      return (CountPendings() > 0);
     }

   // Cancel ALL pending limits/stops for this magic+symbol
   int               CancelAllPendings(void)
     {
      int cancelled = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!m_order.SelectByIndex(i))
            continue;
         if(m_order.Symbol() != m_symbol || !IsOurMagic(m_order.Magic()))
            continue;
         ENUM_ORDER_TYPE t = m_order.OrderType();
         if(t == ORDER_TYPE_BUY_LIMIT || t == ORDER_TYPE_SELL_LIMIT ||
            t == ORDER_TYPE_BUY_STOP  || t == ORDER_TYPE_SELL_STOP)
           {
            ulong ticket = m_order.Ticket();
            if(m_trade.OrderDelete(ticket))
               cancelled++;
            else
               m_last_error = StringFormat("OrderDelete fail %d", GetLastError());
           }
        }
      return cancelled;
     }

   // Place buy/sell limit from risk plan. One pending discipline.
   bool              PlaceLimit(const ENUM_TARZAN_BIAS bias, const SRiskPlan &plan)
     {
      m_last_error = "";
      if(!plan.valid)
        {
         m_last_error = "Invalid risk plan";
         return false;
        }
      if(HasPosition())
        {
         m_last_error = "Position already open";
         return false;
        }
      // Replace any stale pendings first
      if(HasPending())
         CancelAllPendings();

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);

      req.action       = TRADE_ACTION_PENDING;
      req.symbol       = m_symbol;
      req.magic        = m_magic;
      req.volume       = plan.lots;
      req.price        = plan.entry;
      req.sl           = plan.sl;
      req.tp           = plan.tp;
      req.deviation    = (uint)m_deviation;
      req.type_time    = ORDER_TIME_GTC;

      // Resolve filling mode from symbol
      ENUM_ORDER_TYPE_FILLING fill = ORDER_FILLING_RETURN;
      long filling = 0;
      if(SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE, filling))
        {
         if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
            fill = ORDER_FILLING_IOC;
         else if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
            fill = ORDER_FILLING_FOK;
         else
            fill = ORDER_FILLING_RETURN;
        }
      req.type_filling = fill;

      if(bias == BIAS_LONG)
         req.type = ORDER_TYPE_BUY_LIMIT;
      else if(bias == BIAS_SHORT)
         req.type = ORDER_TYPE_SELL_LIMIT;
      else
        {
         m_last_error = "No bias";
         return false;
        }

      // OrderCheck before send
      MqlTradeCheckResult check;
      ZeroMemory(check);
      if(!OrderCheck(req, check))
        {
         m_last_error = StringFormat("OrderCheck fail retcode=%u %s", check.retcode, check.comment);
         return false;
        }

      if(!OrderSend(req, res))
        {
         m_last_error = StringFormat("OrderSend fail retcode=%u err=%d", res.retcode, GetLastError());
         return false;
        }
      if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_DONE_PARTIAL &&
         res.retcode != TRADE_RETCODE_PLACED)
        {
         m_last_error = StringFormat("OrderSend retcode=%u %s", res.retcode, res.comment);
         return false;
        }
      return true;
     }

   // Detect if a deal OUT for our magic was a stop-out (loss)
   bool              IsOurStopOutDeal(const ulong deal_ticket)
     {
      if(deal_ticket == 0)
         return false;
      if(!HistoryDealSelect(deal_ticket))
         return false;
      if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != m_symbol)
         return false;
      if((ulong)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != m_magic)
         return false;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         return false;

      ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal_ticket, DEAL_REASON);
      double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT)
                      + HistoryDealGetDouble(deal_ticket, DEAL_SWAP)
                      + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);

      // SL reason, or loss exit treated as stop-out for flip
      if(reason == DEAL_REASON_SL)
         return true;
      if(profit < 0.0 && (reason == DEAL_REASON_SO || reason == DEAL_REASON_VMARGIN))
         return true;
      return false;
     }

   bool              IsOurTakeProfitDeal(const ulong deal_ticket)
     {
      if(deal_ticket == 0)
         return false;
      if(!HistoryDealSelect(deal_ticket))
         return false;
      if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != m_symbol)
         return false;
      if((ulong)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != m_magic)
         return false;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         return false;
      ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal_ticket, DEAL_REASON);
      return (reason == DEAL_REASON_TP);
     }
  };

#endif
//+------------------------------------------------------------------+
