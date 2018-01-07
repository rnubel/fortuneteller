module FortuneTeller
  # Simulates personal finances.
  class Simulator
    OBJECT_TYPES = %i[account job social_security spending_strategy tax_strategy]
    USER_TYPES = %i[primary partner]

    attr_reader :beginning

    USER_TYPES.each do |user_type|
      attr_reader user_type
      define_method :"add_#{user_type}" do |**kwargs|
        raise FortuneTeller::PlanSetupError.new(:plan_finalized) if @finalized
        instance_variable_set(
          :"@#{user_type}", 
          FortuneTeller::Person.new(**kwargs)
        )
      end
    end

    OBJECT_TYPES.each do |object_type|
      attr_reader object_type.to_s.pluralize.to_sym
      define_method :"add_#{object_type}" do |holder=nil, &block|
        raise FortuneTeller::PlanSetupError.new(:plan_finalized) if @finalized
        component = "fortune_teller/#{object_type}/component".classify.constantize
        key = @available_keys.shift
        obj = component.new(key, @beginning, holder, &block)
        collection = send(object_type.to_s.pluralize.to_sym)[key] = obj
        obj
      end
    end

    def initialize(beginning, end_age=100)
      @allocation_strategy = nil
      @beginning = beginning
      @end_age = end_age
      @available_keys = ('AA'..'ZZ').to_a
      @finalized = false
      OBJECT_TYPES.each do |object_type|
        send("#{object_type.to_s.pluralize}=".to_sym, {})
      end
    end

    def initial_take_home_pay
      jobs.values.map do |job|
        plan = job.plan.to_reader.on(@beginning)
        monthly_base = (plan.base.initial_value / 12.0).round
        plan.savings_plans.each do |savings|
          monthly_base -= (savings[:percent]/100.0 * monthly_base).round
        end
        monthly_base -= (0.30 * monthly_base).round
      end.sum.round
    end

    def take_homes_without_withdrawals(year, month)
      plan_components_without_withdrawals
        .flat_map(&:values)
        .map do |c|
          c.generators[year].take_home_pay(month: month)
        end
    end

    def simulate(growth_rates:)
      finalize_plan! unless @finalized

      growth_rates = GrowthRateSet.new(growth_rates, start_year: @beginning.year)
      states       = [initial_state(growth_rates)]

      while states.last.date != @end_date
        states << simulate_next_state(states.last)
      end
      puts states.as_json if ENV['VERBOSE']

      states
    end

    def add_allocation_strategy(allocations:)
      raise setup_error(:allocation_exists) unless @allocation_strategy.nil?
      @allocation_strategy = FortuneTeller::AllocationStrategy.new(
        allocations: allocations,
        start_year:  start_year
      )
    end

    def start_year
      beginning.year
    end

    def end_year
      @end_date.year-1
    end

    def years
      (start_year..end_year)
    end

    private

    OBJECT_TYPES.each do |object_type|
      attr_writer object_type.to_s.pluralize.to_sym
    end

    def finalize_plan!
      validate_plan!

      #finalize end_date
      @end_date = first_day_of_year((youngest_birthday.year + @end_age + 1))

      plan_components.each do |component_types|
        component_types.values.each do |c|
          c.build_generators(self)
        end
      end

      @finalized = true
    end

    def simulate_next_state(last)
      end_date = first_day_of_year((last.date.year + 1))
      transforms = plan_transforms(from: last.date, to: end_date)
      evolve_state(last, transforms, end_date)
    end

    def first_day_of_year(year)
      Date.new(year, 1, 1)
    end

    def evolve_state(state, transforms, to)
      state = state.init_next
      transforms.each do |t| 
        t.apply_to(state)
      end
      state.pass_time(to: to)
      state
    end

    def plan_components_without_withdrawals
      @plan_components_without_withdrawals ||=
        %i[job social_security].map do |object_type|
          send(object_type.to_s.pluralize.to_sym)
        end
    end

    def plan_components
      @plan_components ||=
        # Keep spending strategy last
        %i[job social_security spending_strategy].map do |object_type|
          send(object_type.to_s.pluralize.to_sym)
        end
    end

    def plan_transforms(from:, to:)
      cache_key = [from, to]
      @cached_transforms ||= {}
      @cached_transforms[cache_key] ||= begin     
        plan_components
          .flat_map(&:values)
          .flat_map do |component|
            component.generators[from.year].gen_transforms(simulator: self)
          end
          .sort
      end
    end

    def youngest_birthday
      return @primary.birthday if no_partner?
      [@primary.birthday, @partner.birthday].min
    end

    def initial_state(growth_rates)
      s = FortuneTeller::State.new(
        start_date: @beginning, 
        growth_rates: growth_rates, 
        allocation_strategy: @allocation_strategy
      )
      accounts.each { |k, a| s.add_account(key: k, account: a, growth_rates: growth_rates) }
      s
    end

    def no_partner?
      @partner.nil?
    end

    def no_primary?
      @primary.nil?
    end

    def validate_plan!
      if no_primary? and no_partner?
        raise setup_error(:no_person)
      elsif no_primary?
        raise setup_error(:no_primary_person)
      end
    end

    def setup_error(token)
      FortuneTeller::PlanSetupError.new(token)
    end
  end
end
