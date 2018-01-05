module FortuneTeller
  module Base
    class Generator
      def initialize(holder:, year:)
        @holder = holder
        @year = year
      end

      # This avoids the time calculations involved in Date#beginning_of_month
      # for a slight speedup.
      def next_month(from)
        from.next_month.change(day: 1)
      end

      def start_month(simulator, day=1)
        beginning = simulator.beginning 
        if @year==beginning.year          
          return (beginning.day<=day ? beginning.month : (beginning.month+1))
        else
          return 1
        end
      end
    end
  end
end