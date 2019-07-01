# frozen_string_literal: true

class SettingsEstimator
  include ActiveAttr::Model

  include Rounding

  # inputs
  attribute :quote_currency_balance, type: BigDecimal
  attribute :reserve, type: BigDecimal, default: 0.0
  attribute :buy_fee, type: BigDecimal
  attribute :sell_fee, type: BigDecimal
  attribute :base_currency_price, type: BigDecimal
  attribute :min_trade_amount, type: BigDecimal
  attribute :coverage, type: BigDecimal
  attribute :buy_down_interval, type: BigDecimal
  attribute :profit_interval, type: BigDecimal

  # results
  attribute :free_fall_trades
  attribute :buy_quantity, type: BigDecimal
  attribute :sell_quantity, type: BigDecimal
  attribute :quote_profit_per_sell, type: BigDecimal
  attribute :zero_balance_price, type: BigDecimal
  attribute :results_errors, default: []

  validates :coverage, inclusion: { in: 1..100, message: "must be between 1 and 100" }
  validates :quote_currency_balance,
            :base_currency_price,
            :buy_down_interval,
            :profit_interval, numericality: { greater_than: 0.0 }
  validates :buy_fee, :sell_fee, numericality: { greater_than_or_equal_to: 0.0 }
  validates :reserve, numericality: { greater_than_or_equal_to: 0.0 }
  validates :quote_currency_balance, numericality: { greater_than: ->(se) { se.reserve },
                                                     message: "must be more than reserve" }

  def results
    self.quote_currency_balance = quote_currency_balance - reserve
    self.buy_quantity = calculate_buy_quantity
    self.sell_quantity = buy_quantity
    self.quote_profit_per_sell = calculate_quote_profit_per_sell(base_currency_price, sell_quantity)
    self.zero_balance_price = calculate_zero_balance_price
    self.free_fall_trades = calculate_free_fall_trades
    add_results_errors
    self
  end

  def calculate_buy_quantity
    cov = as_proportion(coverage)
    dividend = buy_down_interval * 2 * quote_currency_balance
    divisor = (buy_fee_proportion + 1) * base_currency_price**2 * cov * (2 - cov)
    bc_tick_rounded((dividend / divisor))
  end

  def calculate_quote_profit_per_sell(buy_price, sell_quantity)
    qc_tick_rounded((revenue(buy_price, sell_quantity) - costs(buy_price)))
  end

  def revenue(buy_price, sell_quantity)
    ask(buy_price) * sell_quantity * (1 - sell_fee_proportion)
  end

  def costs(buy_price)
    buy_price * buy_quantity * (1 + buy_fee_proportion)
  end

  def ask(buy_price)
    buy_price + profit_interval
  end

  def buy_fee_proportion
    as_proportion(buy_fee)
  end

  def sell_fee_proportion
    as_proportion(sell_fee)
  end

  def calculate_zero_balance_price
    qc_tick_rounded(base_currency_price - (base_currency_price * as_proportion(coverage)))
  end

  def calculate_free_fall_trades
    balance = quote_currency_balance
    buy_price = base_currency_price
    sell_price = base_currency_price + profit_interval

    [].tap do |trade|
      loop do
        cost, b_fee, total_cost = buy_side_trade(buy_price)
        sell_quantity, revenue, s_fee, total_revenue = sell_side_trade(sell_price)

        break if total_cost > balance

        trade << {
          balance: qc_tick_rounded(balance),
          buy_price: qc_tick_rounded(buy_price),
          buy_quantity: buy_quantity,
          cost: qc_tick_rounded(cost),
          buy_fee: qc_tick_rounded(b_fee),
          total_cost: qc_tick_rounded(total_cost),
          sell_price: qc_tick_rounded(sell_price),
          sell_quantity: sell_quantity,
          revenue: qc_tick_rounded(revenue),
          sell_fee: qc_tick_rounded(s_fee),
          total_revenue: qc_tick_rounded(total_revenue),
          quote_profit: qc_tick_rounded(total_revenue - total_cost)
        }

        balance -= total_cost
        buy_price -= buy_down_interval
        sell_price -= buy_down_interval
      end
    end
  end

  def buy_side_trade(buy_price)
    cost = buy_price * buy_quantity
    b_fee = buy_fee_proportion * cost

    [
      cost,
      b_fee,
      cost + b_fee
    ]
  end

  def sell_side_trade(sell_price)
    sell_quantity = buy_quantity
    revenue = sell_price * sell_quantity
    s_fee = sell_fee_proportion * revenue

    [
      sell_quantity,
      revenue,
      s_fee,
      revenue - s_fee
    ]
  end

  def as_proportion(percent)
    percent / 100.0
  end

  def add_results_errors
    min_quantity
    negative_profit
  end

  def min_quantity
    msg = "GDAX's minimum order amount requirement is not met. Adjust your settings."
    results_errors << msg if buy_quantity < min_trade_amount
  end

  def negative_profit
    msg = "You're profit is negative."
    results_errors << msg if quote_profit_per_sell.negative?
  end
end
