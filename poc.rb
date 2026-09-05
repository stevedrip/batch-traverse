# frozen_string_literal: true

require "fiber"

# Fibonacci is well understood, and models a recursive structure with some data
# missing and needing to be computed: n's two "children" are n-1 and n-2
# (EDGE_SCOPE), and only the base cases have a value of their own (NODE_SCOPE) -
# everything else has to be computed from its children. Naive recursion revisits
# the same n many times over (computing fib(5) asks about fib(3) three separate
# times), which makes the payoff of caching or batching those lookups dramatic and
# easy to see, unlike a tree with no repeated substructure.
#
# EDGE_SCOPE and NODE_SCOPE are the only things that touch the "database" - bulk
# lookups that take many ids and answer everything they can about all of them in
# one round trip. Everything below them (MetricScope, CacheScope, BatchScope)
# answers id-by-id lookups against one of those without ever changing what it
# returns: batching is a property of how a traversal asks for data, not of the
# data source itself, so swapping the Scope a traversal runs against never
# changes its result, only how many round trips it costs.
module Fibonacci
  # ids -> {id => [child_id, child_id]}, both children always >= 0 since this is
  # only ever consulted for ids the NODE_SCOPE base cases don't already answer.
  EDGE_SCOPE = ->(ids) {
    ids.each_with_object({}) { |id, h| h[id] = [id - 1, id - 2].select { |i| i >= 0 } }
  }

  # ids -> {id => value}, entries omitted for anything past the base cases - those
  # have to be computed from their children instead.
  NODE_SCOPE = ->(ids) {
    ids.each_with_object({}) do |id, h|
      case id
      when 0 then h[0] = 0
      when 1 then h[1] = 1
      end
    end
  }

module_function

  def compute(scope, n)
    base = scope.find(NODE_SCOPE, n)
    return base unless base.nil?

    scope.find(EDGE_SCOPE, n).sum { |child| compute(scope, child) }
  end
end

# Fetches directly, one round trip per #where call - the naive baseline every
# other Scope here is measured against, and the metric they're measured on:
# round_trips counts real fetches by the scope they went through (EDGE_SCOPE,
# NODE_SCOPE, ...), no matter which subclass triggered them. #find is defined once,
# here, in terms of #where; every subclass below overloads #where instead of
# #find, so caching or batching only ever has to change when a round trip happens,
# never how a single id turns into one.
class MetricScope
  attr_reader :round_trips

  def initialize
    @round_trips = Hash.new(0)
  end

  def where(scope, ids)
    round_trips[scope] += 1
    scope.call(ids)
  end

  def find(scope, id)
    where(scope, [id])[id]
  end
end

# Remembers what it already fetched so the same id is never fetched twice by one
# instance - including across separate top-level calls that happen to share a
# node. Overloads #where, not #find: #find is inherited unchanged and already
# reduces to where(scope, [id]), so a cache keyed the same way covers both.
class CacheScope < MetricScope
  def initialize
    super
    @cache = {}
  end

  def where(scope, ids)
    cache = (@cache[scope] ||= {})
    missing = ids.reject { |id| cache.key?(id) }

    unless missing.empty?
      found = super(scope, missing)
      missing.each { |id| cache[id] = found[id] }
    end

    cache.slice(*ids)
  end
end

# Drives several jobs concurrently, one Fiber each, resuming every fiber once per
# tick and handing whatever they ask for and don't already have to the scope as one
# batch. A job that only needs a handful of ids still only ever asks for a handful
# of ids - the saving comes from sharing a round trip with every other job still
# waiting on one, not from fetching more than anything asked for.
class BatchRunner
  def self.run(scope, jobs)
    fibers = jobs.map { |job| Fiber.new { job.call(scope) } }
    results = Array.new(jobs.size)
    pending = (0...jobs.size).to_a

    until pending.empty?
      requests = []
      still_pending = []

      pending.each do |i|
        value = fibers[i].resume
        if fibers[i].alive?
          requests << value
          still_pending << i
        else
          results[i] = value
        end
      end

      pending = still_pending
      scope.load_batch(requests) unless requests.empty?
    end

    results
  end
end

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

if __FILE__ == $0
  require "minitest/autorun"

  class FibonacciTest < Minitest::Test
    EXPECTED = {0 => 0, 1 => 1, 2 => 1, 3 => 2, 4 => 3, 5 => 5, 6 => 8, 7 => 13, 8 => 21}.freeze

    # MetricScope/CacheScope answer synchronously - a bare call is enough.
    def test_compute_is_correct_for_directly_callable_scopes
      [MetricScope.new, CacheScope.new].each do |scope|
        EXPECTED.each do |n, value|
          assert_equal(value, Fibonacci.compute(scope, n), "compute(#{n}) via #{scope.class}")
        end
      end
    end

    # BatchScope suspends on a miss, so it only makes sense driven through #run -
    # calling Fibonacci.compute on one directly would try to yield outside of any
    # Fiber and raise.
    def test_compute_is_correct_for_batch_driven_scope
      EXPECTED.each do |n, value|
        batch = BatchScope.new
        assert_equal([value], batch.run([->(s) { Fibonacci.compute(s, n) }]), "compute(#{n}) via BatchScope")
      end
    end

    def test_metric_scope_recomputes_every_shared_subproblem
      metric = MetricScope.new

      Fibonacci.compute(metric, 5)

      # Naive recursion asks about the same n over and over - fib(5) calls fib(3)
      # three separate times, fib(2) five times, and so on - so MetricScope, which
      # shares nothing, pays for every one of those repeats separately.
      assert_equal(7, metric.round_trips[Fibonacci::EDGE_SCOPE])
      assert_equal(15, metric.round_trips[Fibonacci::NODE_SCOPE])
    end

    def test_cache_scope_pays_for_each_subproblem_once
      cache = CacheScope.new

      Fibonacci.compute(cache, 5)

      # Every n from 0 to 5 is asked about at least once, but never twice: fetching
      # each subproblem's edges and value once is enough to answer every repeat of
      # it, turning the naive 7/15 round trips above into one per distinct n.
      assert_equal(4, cache.round_trips[Fibonacci::EDGE_SCOPE])
      assert_equal(6, cache.round_trips[Fibonacci::NODE_SCOPE])
    end

    def test_batch_scope_shares_a_cache_across_concurrent_jobs
      batch = BatchScope.new
      jobs = [
        ->(scope) { Fibonacci.compute(scope, 5) },
        ->(scope) { Fibonacci.compute(scope, 6) }
      ]

      assert_equal([5, 8], batch.run(jobs))

      # fib(6) needs fib(5) and fib(4), both already inside fib(5)'s own 0..5
      # subproblem tree; running them concurrently means fib(6) rides along on
      # whatever fib(5) already forced into the cache, and only n=6 itself is new
      # work - so the pair costs exactly what fib(5) alone costs via CacheScope
      # (see test_cache_scope_pays_for_each_subproblem_once).
      assert_equal(4, batch.round_trips[Fibonacci::EDGE_SCOPE])
      assert_equal(6, batch.round_trips[Fibonacci::NODE_SCOPE])
    end

    def test_batch_scope_forgets_between_separate_runs
      jobs = [
        ->(scope) { Fibonacci.compute(scope, 5) },
        ->(scope) { Fibonacci.compute(scope, 6) }
      ]

      batch = BatchScope.new
      batch.run(jobs)
      first_run_edges = batch.round_trips[Fibonacci::EDGE_SCOPE]
      first_run_nodes = batch.round_trips[Fibonacci::NODE_SCOPE]

      batch.run(jobs)

      # A second #run starts from an empty cache, so it costs exactly what the
      # first one did, all over again - #run never remembers a previous #run.
      assert_equal(first_run_edges * 2, batch.round_trips[Fibonacci::EDGE_SCOPE])
      assert_equal(first_run_nodes * 2, batch.round_trips[Fibonacci::NODE_SCOPE])
    end
  end
end
