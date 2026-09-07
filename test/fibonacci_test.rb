# frozen_string_literal: true

require_relative "test_helper"

class FibonacciTest < Minitest::Test
  EXPECTED = {0 => 0, 1 => 1, 2 => 1, 3 => 2, 4 => 3, 5 => 5, 6 => 8, 7 => 13, 8 => 21}.freeze

  # Eager/Metric/Cache answer synchronously - a bare call is enough.
  def test_compute_is_correct_for_directly_callable_evaluators
    [Evaluator::Eager.new, Evaluator::Metric.new(Evaluator::Eager.new), Evaluator::Cache.new(Evaluator::Eager.new)].each do |evaluator|
      Evaluator.using(evaluator) do
        EXPECTED.each do |n, value|
          assert_equal(value, Fibonacci.compute(n), "compute(#{n}) via #{evaluator.class}")
        end
      end
    end
  end

  # Concurrent suspends on a miss, so it only makes sense driven through #map -
  # calling Fibonacci.compute directly would try to yield outside of any Fiber
  # and raise.
  def test_compute_is_correct_for_concurrent_evaluator
    EXPECTED.each do |n, value|
      concurrent = Evaluator::Concurrent.new(Evaluator::Eager.new)
      result = Evaluator.using(concurrent) { concurrent.map([n]) { |i| Fibonacci.compute(i) } }
      assert_equal([value], result, "compute(#{n}) via Concurrent")
    end
  end

  def test_metric_recomputes_every_shared_subproblem
    metric = Evaluator::Metric.new(Evaluator::Eager.new)

    Evaluator.using(metric) { Fibonacci.compute(5) }

    # Naive recursion asks about the same n over and over - fib(5) calls fib(3)
    # three separate times, fib(2) five times, and so on - so a bare Metric,
    # which shares nothing, pays for every one of those repeats separately.
    assert_equal(7, metric.round_trips[Fibonacci::EDGE_SCOPE])
    assert_equal(15, metric.round_trips[Fibonacci::NODE_SCOPE])
  end

  def test_cache_pays_for_each_subproblem_once
    metric = Evaluator::Metric.new(Evaluator::Eager.new)
    cache = Evaluator::Cache.new(metric)

    Evaluator.using(cache) { Fibonacci.compute(5) }

    # Every n from 0 to 5 is asked about at least once, but never twice: fetching
    # each subproblem's edges and value once is enough to answer every repeat of
    # it, turning the naive 7/15 round trips above into one per distinct n.
    assert_equal(4, metric.round_trips[Fibonacci::EDGE_SCOPE])
    assert_equal(6, metric.round_trips[Fibonacci::NODE_SCOPE])
  end

  def test_concurrent_alone_only_shares_whatever_two_jobs_ask_for_at_the_same_moment
    metric = Evaluator::Metric.new(Evaluator::Eager.new)
    concurrent = Evaluator::Concurrent.new(metric)

    result = Evaluator.using(concurrent) { concurrent.map([5, 6]) { |n| Fibonacci.compute(n) } }

    assert_equal([5, 8], result)

    # A resolved answer is dropped as soon as the jobs waiting on it have read
    # it, so Concurrent alone doesn't remember fib(5)'s subtree for fib(6) to
    # reuse later - it only merges requests that land in the very same tick
    # (fib(5) and fib(6) walk down in lockstep for a while, so some of that
    # still happens). That's short of Cache's 4/6 for the same pair, but well
    # under running them with no sharing at all (7+12=19 edges, 15+25=40
    # nodes - see test_metric_recomputes_every_shared_subproblem and
    # test_fib_6_recomputes_every_shared_subproblem_too).
    assert_equal(13, metric.round_trips[Fibonacci::EDGE_SCOPE])
    assert_equal(28, metric.round_trips[Fibonacci::NODE_SCOPE])
  end

  def test_fib_6_recomputes_every_shared_subproblem_too
    metric = Evaluator::Metric.new(Evaluator::Eager.new)

    Evaluator.using(metric) { Fibonacci.compute(6) }

    assert_equal(12, metric.round_trips[Fibonacci::EDGE_SCOPE])
    assert_equal(25, metric.round_trips[Fibonacci::NODE_SCOPE])
  end

  def test_concurrent_wrapping_a_cache_remembers_across_the_whole_map
    metric = Evaluator::Metric.new(Evaluator::Eager.new)
    concurrent = Evaluator::Concurrent.new(Evaluator::Cache.new(metric))

    result = Evaluator.using(concurrent) { concurrent.map([5, 6]) { |n| Fibonacci.compute(n) } }

    assert_equal([5, 8], result)

    # Wrapping a Cache underneath restores full memoization for the whole
    # #map: now fib(6) really does ride for free on fib(5)'s subtree, the
    # same 4/6 Cache alone costs for fib(5) by itself (see
    # test_cache_pays_for_each_subproblem_once) - Concurrent's own bookkeeping
    # is only ever about which jobs are waiting on what right now, not about
    # remembering answers, so whether anything is remembered longer than a
    # tick is entirely up to what it wraps.
    assert_equal(4, metric.round_trips[Fibonacci::EDGE_SCOPE])
    assert_equal(6, metric.round_trips[Fibonacci::NODE_SCOPE])
  end

  def test_concurrent_alone_forgets_everything_between_separate_map_calls
    metric = Evaluator::Metric.new(Evaluator::Eager.new)
    concurrent = Evaluator::Concurrent.new(metric)

    Evaluator.using(concurrent) do
      concurrent.map([5, 6]) { |n| Fibonacci.compute(n) }
      first_run_edges = metric.round_trips[Fibonacci::EDGE_SCOPE]
      first_run_nodes = metric.round_trips[Fibonacci::NODE_SCOPE]

      result = concurrent.map([5, 6]) { |n| Fibonacci.compute(n) }

      # Every resolved answer is dropped once its tick's jobs have read it, so
      # by the time a #map call returns there's nothing left to reuse - a
      # second #map on the same instance costs exactly what the first one
      # did, all over again.
      assert_equal([5, 8], result)
      assert_equal(first_run_edges * 2, metric.round_trips[Fibonacci::EDGE_SCOPE])
      assert_equal(first_run_nodes * 2, metric.round_trips[Fibonacci::NODE_SCOPE])
    end
  end
end
