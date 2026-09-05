# frozen_string_literal: true

require "fiber"
require_relative "metric_scope"
require_relative "batch_runner"

# Suspends on a miss instead of fetching immediately, so BatchRunner can coalesce
# every in-flight job's misses into one round trip per kind per tick. Forgets
# everything between separate #run calls, so two runs cost whatever each costs on
# its own.
#
# Also overloads #where rather than #find, and also calls super for the real
# fetch - but #where runs on two very different sides of a suspend: called from
# inside a job's Fiber (via the inherited #find) it must yield rather than fetch,
# while BatchRunner's load_batch calls it again, outside of any Fiber, once the
# miss it yielded has actually been resolved and just needs writing into the
# cache. `resolving:` picks which side is talking.
class BatchScope < MetricScope
  def initialize
    super
    @cache = {}
  end

  def where(scope, ids, resolving: false)
    cache = (@cache[scope] ||= {})
    missing = ids.reject { |id| cache.key?(id) }

    return cache.slice(*ids) if missing.empty?

    if resolving
      found = super(scope, missing)
      missing.each { |id| cache[id] = found[id] }
      cache.slice(*ids)
    else
      Fiber.yield([scope, missing])
      cache.slice(*ids)
    end
  end

  # Called by BatchRunner between ticks, outside of any job's Fiber, with
  # everything every job asked for and didn't already have this tick. One real
  # round trip per kind, however many jobs (or ids) were waiting on it.
  def load_batch(requests)
    requests.group_by(&:first).each do |scope, pairs|
      where(scope, pairs.flat_map(&:last).uniq, resolving: true)
    end
  end

  def run(jobs)
    @cache.clear
    BatchRunner.run(self, jobs)
  end
end
