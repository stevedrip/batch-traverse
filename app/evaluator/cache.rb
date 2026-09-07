# frozen_string_literal: true

require_relative "findable"

module Evaluator
  # Wraps another evaluator and remembers what it already fetched, so the
  # same id is never asked of the wrapped evaluator twice - including across
  # separate top-level calls that happen to share one. #map passes straight
  # through: only #where does anything of its own.
  class Cache
    include Findable

    def initialize(inner)
      @inner = inner
      @cache = {}
    end

    def map(enumerable, &block)
      @inner.map(enumerable, &block)
    end

    def where(scope, ids)
      cache = (@cache[scope] ||= {})
      missing = ids.reject { |id| cache.key?(id) }

      unless missing.empty?
        found = @inner.where(scope, missing)
        missing.each { |id| cache[id] = found[id] }
      end

      cache.slice(*ids)
    end
  end
end
