# frozen_string_literal: true

require_relative "findable"

module Evaluator
  # Wraps another evaluator and counts round trips by the Reference they went
  # through - one #where call is one round trip, whatever ids ride along in
  # it, no matter which evaluator wrapping this one triggered it. #map passes
  # straight through: only #where does anything of its own.
  class Metric
    include Findable

    attr_reader :round_trips

    def initialize(inner)
      @inner = inner
      @round_trips = Hash.new(0)
    end

    def map(enumerable, &block)
      @inner.map(enumerable, &block)
    end

    def where(scope, ids)
      round_trips[scope] += 1
      @inner.where(scope, ids)
    end
  end
end
