require 'set'

require 'ruby-debug'
Debugger.start

module Crontime

  unless (self.const_defined?('PREFIX_RE'))
    PREFIX_RE = '(?:^|\A|[^[:alpha:]])'
    SUFFIX_RE = '(?:$|\Z|[^[:alpha:]])'
  end

  def numerise(val_p)
    val = val_p.to_s.dup
    return val unless (self.class.const_defined?('NAMES'))
    list = self.class.const_get('NAMES')
    pattern = PREFIX_RE + '(' + list.keys.join('|') + ')' + SUFFIX_RE
    regex = Regexp.new(pattern, Regexp::IGNORECASE)
    while (m = val.match(regex))
      rpattern = Regexp.new(PREFIX_RE + m.captures[0] + SUFFIX_RE)
      val.sub!(rpattern, list[m.captures[0].downcase])
    end
    return val
  end

  class Field

    include Crontime

    attr_reader(:input)
    alias_method(:to_s, :input)
    attr_reader(:min)
    attr_reader(:max)
    attr_reader(:selected)

    def initialize(*args_p)
      @min = 0
      @max = 59
      @match_all = false
      if (args_p[0].kind_of?(Range))
        range = [ *args_p.shift ]
        @min = range.first
        @max = range.last
      else
        if (args_p[0].kind_of?(Integer) || (args_p[0] =~ %r!^\d+!))
          @min = args_p.shift.to_i
        end
        if (args_p[0].kind_of?(Integer) || (args_p[0] =~ %r!^\d+!))
          @max = args_p.shift.to_i
        end
      end
      if (self.class.const_defined?('ALWAYS'))
        @tauto = self.class::ALWAYS
      else
        @tauto = Set.new(@min .. @max)
      end
      self.parse(args_p[0]) if (args_p[0].kind_of?(String))
    end

    def parse(input_p='*')
      @input = input_p
      input = self.numerise(@input)
      @selected = Set.new
      input.strip.split(%r!\s*,\s*!).each do |clause|
        (range_p, modulo) = clause.split(%r!\s*/\s*!)
        if (range_p == '*')
          range = (@min .. @max)
        elsif (range_p =~ %r!^\d+$!)
          range = range_p.to_i
        elsif (m = range_p.match(%r!^(\d+)-(\d+)!))
          low = m.captures[0].to_i
          high = m.captures[1].to_i
          range = (low .. high)
        else
          raise ArgumentError.new('illegal clause: ' +
                                  "#{range_p.inspect} for #{self.class.name}")
        end
        range = Set.new([ *range ])
        unless (modulo.nil? || (modulo !~ %r!^\d+$!))
          modulo = modulo.to_i
          range = range.select { |elt| elt.%(modulo).zero? }
        end
        @selected |= range
      end
      @match_all = (@selected == @tauto)
      return @selected
    end

    def include?(poz_p)
      return true if (@match_all)
      poz = self.numerise(poz_p).to_i
      unless (poz.between?(@min, @max))
        raise RangeError.new("#{poz} out of range (#{@min}..#{@max}) for field")
      end
      return @selected.include?(poz)
    end

    def inspect(use_real=false)
      result = super()
      return result if (use_real)
      allowed = @selected.to_a.sort
      result.sub!(%r!(:0x[[:xdigit:]]+ @).*!, "\\1selected=#{allowed.inspect}>")
      return result
    end

  end

  class Minutes < Field

    unless (self.const_defined?('ALWAYS'))
      ALWAYS = Set.new(0..59).freeze
    end

    def initialize(*args_p)
      super(0..59, *args_p)
    end

  end

  class Hours < Field

    unless (self.const_defined?('ALWAYS'))
      ALWAYS = Set.new(0..23).freeze
    end

    def initialize(*args_p)
      super(0..23, *args_p)
    end

  end

  class MonthDays < Field

    unless (self.const_defined?('ALWAYS'))
      ALWAYS = Set.new(1..31).freeze
    end

    def initialize(*args_p)
      super(1..31, *args_p)
    end

  end

  class Months < Field

    unless (self.const_defined?('NAMES'))
      NAMES = {
        'jan'	=> '0',
        'feb'	=> '1',
        'mar'	=> '2',
        'apr'	=> '3',
        'may'	=> '4',
        'jun'	=> '5',
        'jul'	=> '6',
        'aug'	=> '7',
        'sep'	=> '8',
        'oct'	=> '9',
        'nov'	=> '10',
        'dec'	=> '11',
      }
    end

    unless (self.const_defined?('ALWAYS'))
      ALWAYS = Set.new(1..12).freeze
    end

    def initialize(*args_p)
      super(1..12, *args_p)
    end

  end

  class WeekDays < Field

    unless (self.const_defined?('NAMES'))
      NAMES = {
        'sun'	=> '0',
        'mon'	=> '1',
        'tue'	=> '2',
        'wed'	=> '3',
        'thu'	=> '4',
        'fri'	=> '5',
        'sat'	=> '6',
      }
    end

    unless (self.const_defined?('ALWAYS'))
      ALWAYS = Set.new(0..6).freeze
    end

    #
    # TODO: treat both 0 *and* 7 as Sunday.
    #
    def initialize(*args_p)
      super(0..6, *args_p)
    end

  end

  class Schedule

    include Crontime

    unless (self.const_defined?('SHORTCUTS'))
      SHORTCUTS = {
        '@yearly'	=> '0 0 1 1 *',
        '@annually'	=> '0 0 1 1 *',
        '@monthly'	=> '0 0 1 * *',
        '@weekly'	=> '0 0 * * 0',
        '@daily'	=> '0 0 * * *',
        '@hourly'	=> '0 * * * *',
        '@minutely'	=> '* * * * *',
      }
    end

    attr_reader(:input)
    alias_method(:to_s, :input)
    attr_reader(:minutes)
    attr_reader(:hours)
    attr_reader(:month_days)
    attr_reader(:months)
    attr_reader(:week_days)

    def initialize(*args_p)
      @minutes = Minutes.new
      @hours = Hours.new
      @month_days = MonthDays.new
      @months = Months.new
      @week_days = WeekDays.new
      @ordered_fields = [
                         @minutes,
                         @hours,
                         @month_days,
                         @months,
                         @week_days,
                        ]
      self.parse(*args_p) if (args_p[0].kind_of?(String))
    end

    def parse(*args_p)
      args = args_p.flatten.map { |elt| elt.to_s.strip }.join(' ')
      input = args.strip.gsub(%r!\s{2,}!, ' ').downcase
      tokens = args.split(%r!\s+!)
      if (SHORTCUTS.key?(tokens[0]))
        if (tokens.count > 1)
          warn("Extra tokens in '#{input}' ignored")
        end
        input = SHORTCUTS[tokens[0]]
      end
      tocks = input.split(%r!\s+!)[0, 5]
      @input = tocks.compact.join(' ')
      tocks = tocks.map { |elt| elt || '' }
      @minutes.parse(tocks[0])
      @hours.parse(tocks[1])
      @month_days.parse(tocks[2])
      @months.parse(tocks[3])
      @week_days.parse(tocks[4])
      return @input
    end

    #
    # Either a 5-array of integers/strings, or 5 individual
    # integers/strings, or a Time object.
    #
    def include?(*args_p)
      if (args_p[0].kind_of?(Time))
        args = args_p[0].strftime('%M %H %d %m %w').split(%r!\s+!)
      else
        args = args_p.flatten.map { |elt| elt.to_s }.join(' ').strip
        args = self.numerise(args)
        args = args.split(%r!\s+!)[0, 5]
        unless (args.all? { |elt| elt =~ %r!^\d+$! })
          raise ArgumentError.new('invalid time for comparison: ' +
                                  args_p.inspect)
        end
      end
      args.each_with_index do |elt,i|
        return false unless (@ordered_fields[i].include?(elt.to_i))
      end
      return true
    end

  end

end
