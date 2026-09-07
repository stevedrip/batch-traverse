# frozen_string_literal: true

# The Evaluator in effect for whatever's running right now, so a traversal
# can call Evaluator.current.find(reference, id)/.map(...) instead of
# threading an evaluator argument through every method that needs one.
#
# Thread.current's []/[]= are fiber-local, not merely thread-local, so
# concurrent Fibers - including nested ones a Concurrent evaluator spawns
# from within an already-running Fiber - each see their own value without
# stepping on each other, and a synchronous call doesn't leak into whatever
# ran before or after it on the same thread. See Evaluator::Concurrent#map,
# which re-establishes this for every Fiber it creates, at any nesting depth.
module Evaluator
  def self.current
    Thread.current[:evaluator] ||
      raise("no evaluator is current - wrap the call in Evaluator.using(evaluator) { ... }")
  end

  def self.using(evaluator)
    previous = Thread.current[:evaluator]
    Thread.current[:evaluator] = evaluator
    yield
  ensure
    Thread.current[:evaluator] = previous
  end
end
