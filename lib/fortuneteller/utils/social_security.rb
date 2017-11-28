module FortuneTeller
  module Utils

    # Calculates adjusted benefit from PIA
    # Based on https://www.ssa.gov/oact/quickcalc/early_late.html 11/16/2017
    class SocialSecurity
      attr_accessor :pia
      
      def initialize(dob:, start_month:)
        @dob = dob
        @adjusted_dob = (dob.day == 1 ? dob.yesterday : dob)
        @start_month = start_month.at_beginning_of_month
      end

      def estimate_pia(current_salary:, annual_raise:)
        year = Date.today.year
        last_year = @start_month.year
        salary_history = {year => current_salary}
        ((@dob.year+18)..(year-1)).reverse_each do |y|
          salary_history[y] = (salary_history[y+1]/annual_raise).floor
        end
        if(last_year > year)
          ((year+1)..last_year).each do |y|
            salary_history[y] = (salary_history[y-1]*annual_raise).floor
          end
        end
        salaries = salary_history.map{|y, s| s*indexing_factors[y]}
        aime = (salaries.sort.last(35).reduce(:+)/(35.0*12)).floor
        puts "AIME #{aime}"

        if aime > bend_points[1]
          pia_62 = (0.9*bend_points[0]+0.32*(bend_points[1]-bend_points[0])+0.15*(aime-bend_points[1])).floor
        elsif aime > bend_points[0]
          pia_62 = (0.9*bend_points[0]+0.32*(aime-bend_points[0])).floor
        else
          pia_62 = (0.9*aime).floor
        end

        pia_adjusted = pia_62
        ((@dob.year+63)..@start_month.year).each do |y|
          pia_adjusted = (pia_adjusted*(100+COLA_1975_START[y-1-1975])/100.0).floor
        end

        @pia = pia_adjusted
      end

      def fra_pia=(fra_pia)
        pia_adjusted = fra_pia
        if @start_month.year < full_retirement_month.year
          (@start_month.year..(full_retirement_month.year-1)).each do |y|
            pia_adjusted = (pia_adjusted/((100+COLA_1975_START[y-1975])/100.0)).floor
          end
        elsif @start_month.year > full_retirement_month.year
          puts "START GREATER"
          ((full_retirement_month.year+1)..@start_month.year).each do |y|
            puts "START: #{@start_month.year}, YEAR: #{y}"
            puts "PIA ADJ = #{pia_adjusted}"
            pia_adjusted = (pia_adjusted*(100+COLA_1975_START[y-1-1975])/100.0).floor
          end
        end
        @pia = pia_adjusted
      end

      def calculate_benefit
        frm = full_retirement_month
        puts "FRM: #{frm}"
        return @pia if @start_month == frm

        if(@start_month < frm)
          min_rm = min_retirement_month
          raise bounds_error(start: @start_month, min: min_rm) if @start_month < min_rm
          early_benefit( months: month_diff(@start_month, frm) )
        else
          max_rm = max_retirement_month
          raise bounds_error(start: @start_month, max: max_rm) if @start_month > max_rm
          late_benefit( months: month_diff(frm, @start_month) )
        end
      end

      private

      TRANSITION_YEARS = {
        1938 => [65, 2], 1939 => [65, 4], 1940 => [65, 6], 1941 => [65, 8],
        1942 => [65, 10], 1955 => [66, 2], 1956 => [66, 4], 1957 => [66, 6],
        1958 => [66, 8], 1959 => [66, 10],
      }
      DELAY_RATES = {
        1925 => (7/24.0), 1926 => (7/24.0), 1927 => (8/24.0), 1928 => (8/24.0),
        1929 => (9/24.0), 1930 => (9/24.0), 1931 => (10/24.0), 1932 =>  (10/24.0),
        1933 => (11/24.0), 1934 =>  (11/24.0), 1935 => (12/24.0), 1936 => (12/24.0),
        1937 => (13/24.0), 1938 => (13/24.0), 1939 => (14/24.0), 1940 => (14/24.0),
        1941 => (15/24.0), 1942 => (15/24.0),
      }

      AWI_1951_START = [
        # Final (1951-2016)
        # https://www.ssa.gov/oact/COLA/AWI.html
        279916, 297332, 313944, 315564, 330144, 353236, 364172, 367380, 385580, 
        400712, 408676, 429140, 439664, 457632, 465872, 493836, 521344, 557176, 
        589376, 618624, 649708, 713380, 758016, 803076, 863092, 922648, 977944, 
        1055603, 1147946, 1251346, 1377310, 1453134, 1523924, 1613507, 1682251, 
        1732182, 1842651, 1933404, 2009955, 2102798, 2181160, 2293542, 2313267, 
        2375353, 2470566, 2591390, 2742600, 2886144, 3046984, 3215482, 3292192, 
        3325209, 3406495, 3564855, 3695294, 3865141, 4040548, 4133497, 4071161, 
        4167383, 4297961, 4432167, 4488816, 4648152, 4809863, 4866473,
        # Estimates (2017-2070)
        # https://www.ssa.gov/oact/TR/TRassum.html (see awi_projector)
        5056265, 5298965, 5537418, 5775526, 6018098, 6252803, 6484156, 6730553, 
        6986314, 7251793, 7527361, 7813400, 8110309, 8418500, 8738403, 9070462, 
        9415139, 9772914, 10144284, 10529766, 10929897, 11345233, 11776351, 
        12223852, 12688358, 13170515, 13670994, 14190491, 14729729, 15289458, 
        15870457, 16473534, 17099528, 17749310, 18423783, 19123886, 19850593, 
        20604915, 21387901, 22200641, 23044265, 23919947, 24828904, 25772402, 
        26751753, 27768319, 28823515, 29918808, 31055722, 32235839, 33460800, 
        34732310, 36052137, 37422118
      ]

      COLA_1975_START = [
        # Final (1975-2017)
        # https://www.ssa.gov/oact/COLA/colaseries.html
        8.0, 6.4, 5.9, 6.5, 9.9, 14.3, 11.2, 7.4, 3.5, 3.5, 3.1, 1.3, 4.2, 
        4.0, 4.7, 5.4, 3.7, 3.0, 2.6, 2.8, 2.6, 2.9, 2.1, 1.3, 2.5, 3.5, 
        2.6, 1.4, 2.1, 2.7, 4.1, 3.3, 2.3, 5.8, 0.0, 0.0, 3.6, 1.7, 1.5, 
        1.7, 0.0, 0.3, 2.0, 
        # Estimates (2018-2070)
        # https://www.ssa.gov/oact/TR/TRassum.html
        3.1, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 
        2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 
        2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 
        2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 2.6, 
        2.6, 
      ]

      def bend_points
        return @bend_points unless @bend_points.nil?

        age_62_year = @dob.year+62
        age_62_index = AWI_1951_START[(age_62_year-1951)]
        year_1979_index = AWI_1951_START[(1979-1951)]
        year_1979_bends = [18000, 108500]
        @bend_points = [
          (year_1979_bends[0].to_f*(age_62_index/year_1979_index)).floor,
          (year_1979_bends[1].to_f*(age_62_index/year_1979_index)).floor,
        ]
      end

      def indexing_factors
        return @indexing_factors unless @indexing_factors.nil?

        age_60_year = @dob.year+60
        age_60_index = AWI_1951_START[(age_60_year-1951)]
        @indexing_factors = {}
        (18..60).each do |age|
          year = @dob.year+age
          @indexing_factors[year] = age_60_index.to_f/AWI_1951_START[(year-1951)]
        end
        (61..70).each do |age|
          year = @dob.year+age
          @indexing_factors[year] = 1.0          
        end
        @indexing_factors
      end

      def full_retirement_month
        return @frm unless @frm.nil?

        year = @adjusted_dob.year
        frm = @adjusted_dob.at_beginning_of_month
        if year <= 1938
          @frm = frm.years_since(65)
        elsif (year >= 1943 and year <= 1954)
          @frm = frm.years_since(66)
        elsif year >= 1960
          @frm = frm.years_since(67)
        else
          t = TRANSITION_YEARS[year][0]
          @frm = frm.years_since(t[0]).years_since(t[1])             
        end     
      end

      def max_retirement_month
        @adjusted_dob.at_beginning_of_month.years_since(70)
      end

      def min_retirement_month
        if @adjusted_dob.day == 1
          @adjusted_dob.years_since(62)
        else
          @adjusted_dob.at_beginning_of_month.years_since(62).months_since(1)
        end
      end

      def early_benefit(months:)
        if months <= 36
          multiplier = 100.0 - ((5.0 * months) / 9.0)
        else
          multiplier = 100.0 - 20.0 - ((5.0 * months) / 12.0)
        end
        puts "EARLY PIA: #{(pia*multiplier/100.0).floor}"
        (@pia*multiplier/100.0).floor
      end

      def late_benefit(months:)
        year = @adjusted_dob.year
        if year <= 1924
          monthly = 6/24.0
        elsif year <= 1942
          monthly = DELAY_RATES[year]
        else
          monthly = 16.0/24.0
        end
        multiplier = 100.0 + (monthly*months)
        puts "LATE PIA: #{(pia*multiplier/100.0).floor}"
        (@pia*multiplier/100.0).floor
      end

      def month_diff(a, b)
        (b.year * 12 + b.month) - (a.year * 12 + a.month)
      end

      def bounds_error(start:, min: nil, max: nil)
        self.class::StartDateBounds.new(start: start, min: min, max: max)
      end

      def self.awi_projector
        projected = []
        projected_increases = {
          # From https://www.ssa.gov/oact/TR/TRassum.html 
          2017 => 3.9,
          2018 => 4.8,
          2019 => 4.5,
          2020 => 4.3,
          2021 => 4.2,
          2022 => 3.9,
          2023 => 3.7,
          2024 => 3.8,
          2025 => 3.8,
          2026 => 3.8
        }
        last_awi = AWI_1951_START[2016-1951]
        (2017..2070).each do |year|
          increase = projected_increases[[2026, year].min]
          last_awi = (last_awi*((100+increase)/100.0)).floor
          projected << last_awi
        end
        projected
      end

      class StartDateBounds < StandardError
        def initialize(**kargs)
          if not kargs[:max].nil?
            super("Start #{kargs[:start]} is greater than max #{kargs[:max]}")
          elsif not kargs[:min].nil?
            super("Start #{kargs[:start]} is less than min #{kargs[:min]}")
          end
        end
      end

    end
  end
end