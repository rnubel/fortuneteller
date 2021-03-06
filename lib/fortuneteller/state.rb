module FortuneTeller
  # We extend `state` Hash with this module for readability
  class State
    attr_reader :date, :accounts, :cashflow, :from, :to

    def self.cashflow_base
      FortuneTeller::Cashflow.new(
        pretax_gross: 0,
        pretax_salary: 0,
        pretax_savings_withdrawal: 0,
        pretax_savings: 0,
        pretax_savings_matched: 0,
        pretax_adjusted: 0,
        tax_withholding: 0,
        take_home_pay: 0
      )
    end

    def initialize(start_date:, previous: nil)
      @from = start_date.dup
      @date = start_date
      @accounts = {}
      unless previous.nil?
        previous.accounts.each { |k, a| @accounts[k] = a.dup }
      end
      @cashflow = {
        primary: Array.new(12) { self.class.cashflow_base },
        partner: Array.new(12) { self.class.cashflow_base }
      }
    end

    def add_account(key:, account:)
      @accounts[key] = account.initial_state(start_date: @date)
    end

    def pass_time(to:)
      @date = to
      @to = to
      @accounts.each_value { |a| a.pass_time(to: to) }
    end

    def apply_pretax_savings_withdrawal(date:, holder:, amount:, source:)
      @accounts[source].debit(amount: amount, on: date)
      c = FortuneTeller::Cashflow.new(pretax_gross: amount, pretax_savings_withdrawal: amount)
      c.line_items[:pretax_adjusted] = amount
      c.line_items[:tax_withholding] = 0
      c.line_items[:take_home_pay] = amount
      apply_cashflow(date: date, holder: holder, cashflow: c)
    end

    def apply_w2_income(date:, holder:, income:, account_credits:)
      c = generate_w2_cashflow(date, income)
      apply_cashflow(date: date, holder: holder, cashflow: c)
      account_credits.each do |k, amount|
        @accounts[k].credit(amount: amount, on: date)
      end
    end

    def apply_ss_income(date:, holder:, income:)
      c = generate_ss_cashflow(date, income)
      apply_cashflow(date: date, holder: holder, cashflow: c)
    end

    def init_next
      self.class.new(start_date: @date, previous: self)
    end

    def merged_cashflow(holder:)
      @cashflow[holder].reduce(FortuneTeller::Cashflow.new, :merge!)
    end

    def as_json(_options = nil)
      {
        date: @date,
        # cashflow: {
        #   primary: merged_cashflow(holder: :primary).as_json(options),
        #   partner: merged_cashflow(holder: :partner).as_json(options)
        # },
        accounts: @accounts.as_json
      }
    end

    private

    def generate_w2_cashflow(date, income)
      c = FortuneTeller::Cashflow.new(
        pretax_gross: (income[:wages] + income[:matched]),
        pretax_salary: income[:wages],
        pretax_savings: income[:saved],
        pretax_savings_matched: income[:matched],
        pretax_adjusted: (income[:wages] - income[:saved])
      )
      c.line_items[:tax_withholding] = calculate_w2_withholding(
        date: date,
        adjusted_income: c.line_items[:pretax_adjusted],
        pay_period: income[:pay_period]
      )
      c.line_items[:take_home_pay] = c.line_items[:pretax_adjusted] - c.line_items[:tax_withholding]
      c
    end

    def generate_ss_cashflow(date, income)
      FortuneTeller::Cashflow.new(
        pretax_gross: income[:ss],
        pretax_ss: income[:ss],
        pretax_adjusted: income[:ss],
        tax_withholding: 0,
        take_home_pay: income[:ss]
      )
    end

    def calculate_w2_withholding(date:, adjusted_income:, pay_period:)
      # Ideally, use state to determine w-4 allowances
      (adjusted_income * 0.3).floor
    end

    def apply_cashflow(date:, holder:, cashflow:)
      @cashflow[holder][(date.month - 1)].merge!(cashflow)
    end
  end
end
