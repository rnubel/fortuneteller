module FortuneTeller
  class Benchmark
    def self.run(context = {})
      create_sim.simulate(**default_context.merge(context))
    end

    def self.default_context
      {
        growth_rates: {
          # these should match the holdings your retirement accounts have:
          stocks:       [1.06],
          bonds:        [1.04],

          # these are reserved parameters for the simulation:
          wage_growth:  [1.00],
          inflation:    [1.02]
        }
      }
    end

    def self.random_contexts(num)
      possible_returns = (0.90..1.30).step(0.01).to_a
      growth_streams = num.times.map do
        {
          stocks:      100.times.map { possible_returns.sample },
          bonds:       100.times.map { possible_returns.sample },
          inflation:   100.times.map { possible_returns.sample },
          wage_growth: 100.times.map { possible_returns.sample }
        }
      end
    end

    def self.create_sim
      sim = FortuneTeller.new(Date.today)

      sim.add_primary(
        gender: :female,
        birthday: Date.new(1964, 3, 2)
      )

      sim.add_partner(
        gender: :male,
        birthday: Date.new(1966, 5, 5)
      )

      # Define primary's key events and holdings
      primary_retirement = Date.new(2031, 3, 1)

      primary_401k = sim.add_account(:primary) do |plan|
        plan.beginning.set(
          type: :_401k,
          balances: {
            stocks: 300_000_00,
            bonds:  200_000_00
          }
        )
      end

      sim.add_job(:primary) do |plan|
        plan.beginning do |p|
          p.set(
            base: 100_000_00,
          )
          p.add_savings_plan(
            percent: 7,
            match: 3,
            account: primary_401k,
            holding: :stocks
          )
        end
        plan.on(primary_retirement).stop
      end

      sim.add_social_security(:primary) do |plan|
        plan.on(primary_retirement).start
      end

      # Define partner's key events and holdings
      partner_retirement = Date.new(2033, 5, 1)

      partner_401k = sim.add_account(:partner) do |plan|
        plan.beginning.set(
          type: :_401k,
          balances: {
            stocks: 200_000_00,
          }
        )
      end

      sim.add_job(:partner) do |plan|
        plan.beginning do |p|
          p.set(
            base: 75_000_00,
          )
          p.add_savings_plan(
            percent: 7,
            match: 3,
            account: partner_401k,
            holding: :stocks
          )
        end
        plan.on(partner_retirement).stop
      end

      sim.add_social_security(:partner) do |plan|
        plan.on(partner_retirement).start(
          pia: 1000_00
        )
      end

      # Start by spending the leftovers (after tax and saving) and change to
      # spending an exact amount in retirement

      sim.add_spending_strategy do |plan|
        plan.beginning.set(
          strategy: :remainder
        )
        future_take_home_pay = (sim.initial_take_home_pay * 0.8).round

        plan.on(primary_retirement).set(
          strategy: :exact,
          amount: future_take_home_pay # this will automatically increase with inflation
        )
      end

      sim.add_tax_strategy do |plan|
        plan.beginning.set(
          primary: :married_filing_jointly,
          partner: :married_filing_jointly
        )
      end

      sim
    end

    def self.create_sim_guaranteed_income
      sim = create_sim
      sim.add_guaranteed_income do |plan|
        plan.on(Date.new(2032, 2, 5)).start(
          amount: 500_00,
          annual_increase: 1.02
        )
      end
      sim
    end

  end
end
