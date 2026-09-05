# frozen_string_literal: true

require_relative "test_helper"

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
