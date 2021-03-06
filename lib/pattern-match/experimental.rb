require 'pattern-match/core'

raise LoadError, 'Module#prepend required' unless Module.respond_to?(:prepend, true)

module PatternMatch
  module Deconstructable
    remove_method :call
    def call(*subpatterns)
      if Object == self
        PatternKeywordArgStyleDeconstructor.new(Object, :respond_to?, :__send__, *subpatterns)
      else
        pattern_matcher(*subpatterns)
      end
    end
  end

  module AttributeMatcher
    def self.included(klass)
      class << klass
        def pattern_matcher(*subpatterns)
          PatternKeywordArgStyleDeconstructor.new(self, :respond_to?, :__send__, *subpatterns)
        end
      end
    end
  end

  module KeyMatcher
    def self.included(klass)
      class << klass
        def pattern_matcher(*subpatterns)
          PatternKeywordArgStyleDeconstructor.new(self, :has_key?, :[], *subpatterns)
        end
      end
    end
  end

  class PatternKeywordArgStyleDeconstructor < PatternDeconstructor
    def initialize(klass, checker, getter, *keyarg_subpatterns)
      spec = normalize_keyword_arg(keyarg_subpatterns)
      super(*spec.values)
      @klass = klass
      @checker = checker
      @getter = getter
      @spec = spec
    end

    def match(vals)
      super do |val|
        next false unless val.kind_of?(@klass)
        next false unless @spec.keys.all? {|k| val.__send__(@checker, k) }
        @spec.all? do |k, pat|
          pat.match([val.__send__(@getter, k)]) rescue false
        end
      end
    end

    def inspect
      "#<#{self.class.name}: klass=#{@klass.inspect}, spec=#{@spec.inspect}>"
    end

    private

    def normalize_keyword_arg(subpatterns)
      syms = subpatterns.take_while {|i| i.kind_of?(Symbol) }
      rest = subpatterns.drop(syms.length)
      hash = case rest.length
             when 0
               {}
             when 1
               rest[0]
             else
               raise MalformedPatternError
             end
      variables = Hash[syms.map {|i| [i, PatternVariable.new(i)] }]
      Hash[variables.merge(hash).map {|k, v| [k, v.kind_of?(Pattern) ? v : PatternValue.new(v)] }]
    end
  end

  class PatternVariable
    def <<(converter)
      @converter = converter.respond_to?(:call) ? converter : converter.to_proc
      self
    end

    prepend Module.new {
      private

      def bind(val)
        super(@converter ? @converter.call(val) : val)
      end
    }
  end
end

class Hash
  include PatternMatch::KeyMatcher
end

class Object
  def assert_pattern(pattern)
    match(self) do
      Kernel.eval("with(#{pattern}) { self }", Kernel.binding)
    end
  end
end
