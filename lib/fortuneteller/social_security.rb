module FortuneTeller
  # Represents a persons social security strategy
  class SocialSecurity < TransformGenerator
    attr_reader :pia
    def initialize(fra_pia: nil, **base)
      @fra_pia = fra_pia
      super(**base)
    end

    private

    def gen_transforms(from:, to:, plan:)
      benefit = get_benefit_amount(plan: plan).on(from)
      transforms = []
      transforms.push gen_transform(from, benefit) if from.day == 1
      current = from.next_month.at_beginning_of_month
      while current < to
        transforms.push gen_transform(current, benefit)
        current = current.next_month.at_beginning_of_month
      end
      transforms
    end

    def gen_transform(date, benefit)
      self.class::Transform.new(date: date, holder: holder, benefit: benefit)
    end

    def get_benefit_amount(plan:)
      return @benefit unless @benefit.nil?

      if @start_date.day == 1
        start_month = @start_date
      else
        start_month = @start_date.next_month.at_beginning_of_month
      end

      calc = FortuneTeller::Utils::SocialSecurity.new(
        dob: plan.send(@holder).birthday,
        start_month: start_month
      )
      if not @fra_pia.nil?
        calc.fra_pia = @fra_pia
      else
        current_salary = plan.jobs.values.keep_if { |j| j.holder==@holder }.map(&:salary).sum
        puts "CURRENT SAL #{@holder} #{current_salary}"
        calc.estimate_pia(current_salary: current_salary, annual_raise: 0.98)
      end

      benefit = calc.calculate_benefit
      puts "BENEFIT #{benefit}"
      @benefit = plan.inflating_int(benefit, start_month)
    end

    # The transforms generated by social security
    class Transform < FortuneTeller::TransformBase

      def initialize(benefit:, **base)
        @benefit = benefit
        super(**base)
      end

      def apply_to(state)
        state.apply_ss_income(
          date: date,
          holder: holder,
          income: {ss: @benefit},
        )
      end
    end
  end
end
