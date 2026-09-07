# frozen_string_literal: true

require_relative "findable"

module Evaluator
  # Answers directly, synchronously, with no bookkeeping of its own - the
  # innermost evaluator every other one wraps. #map doesn't spawn anything;
  # it's a plain Enumerable#map, so nothing here is measured or shared.
  class Eager
    include Findable

    def map(enumerable, &block)
      enumerable.map(&block)
    end

    def where(scope, ids)
      scope.where(ids)
    end
  end
end
