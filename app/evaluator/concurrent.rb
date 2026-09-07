# frozen_string_literal: true

require "fiber"
require_relative "findable"

module Evaluator
  # Runs several jobs concurrently, one Fiber each - including nested jobs a
  # running job spawns via its own #map call, since #where/#map always work
  # against Evaluator.current rather than an object a caller has to thread
  # through by hand.
  #
  # A job that calls #where and doesn't already have an answer suspends
  # instead of fetching immediately. Once every job in this batch is either
  # done or suspended, one pending scope is resolved - a single #where call
  # against the wrapped evaluator, however many ids (or jobs) were waiting on
  # it - jobs waiting on any other pending scope simply ask again next tick.
  #
  # A resolved answer is only held long enough for the jobs waiting on it to
  # read it, then it's dropped - this batches whoever asks for the same thing
  # at the same time, not whoever asks for it ever. Anything that should stay
  # answered across ticks, separate #map calls, or nesting levels belongs in
  # an Evaluator::Cache wrapped around the inner evaluator instead.
  class Concurrent
    include Findable

    def initialize(inner)
      @inner = inner
      @cache = {}
    end

    def map(enumerable, &block)
      fibers = enumerable.map { |element| Fiber.new { Evaluator.using(self) { block.call(element) } } }
      run(fibers)
    end

    def where(scope, ids)
      cache = (@cache[scope] ||= {})

      # Every pending job is resumed every tick, but only one scope is
      # resolved per tick - a resume can land on a tick that resolved someone
      # else's scope instead of this one, so a single yield isn't enough:
      # keep yielding the same request until this one's actually answered.
      until (missing = ids.reject { |id| cache.key?(id) }).empty?
        Fiber.yield([scope, missing])
      end

      cache.slice(*ids)
    end

  private

    def run(fibers)
      results = Array.new(fibers.size)
      pending = (0...fibers.size).to_a
      resolved = nil

      until pending.empty?
        requests = {}
        still_pending = []

        pending.each do |i|
          value = fibers[i].resume
          if fibers[i].alive?
            scope, ids = value
            (requests[scope] ||= []).concat(ids)
            still_pending << i
          else
            results[i] = value
          end
        end

        # Whatever was resolved last tick has now been read by every job that
        # was waiting on it (every pending job gets resumed every tick), so
        # it's no longer needed - drop it before resolving anything new.
        forget(resolved) if resolved

        pending = still_pending
        resolved = requests.empty? ? nil : resolve_one(requests)
      end

      results
    end

    # PLAN.md: "pick a scope and resolve its ids" - one at a time, however
    # many other scopes are also ready; those jobs stay pending one more tick
    # rather than being resolved alongside this one.
    def resolve_one(requests)
      scope, ids = requests.first
      ids = ids.uniq
      cache = (@cache[scope] ||= {})
      found = @inner.where(scope, ids)
      ids.each { |id| cache[id] = found[id] }
      [scope, ids]
    end

    def forget(resolved)
      scope, ids = resolved
      cache = @cache[scope]
      ids.each { |id| cache.delete(id) }
    end
  end
end
