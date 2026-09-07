# frozen_string_literal: true

require_relative "references/fibonacci/edge"
require_relative "references/fibonacci/node"

# Fibonacci is well understood, and models a recursive structure with some data
# missing and needing to be computed: n's two "children" are n-1 and n-2 (EDGE),
# and only the base cases have a value of their own (NODE) - everything else has
# to be computed from its children. Naive recursion revisits the same n many
# times over (computing fib(5) asks about fib(3) three separate times), which
# makes the payoff of caching or batching those lookups dramatic and easy to
# see, unlike a tree with no repeated substructure.
module Fibonacci
  EDGE_SCOPE = References::Fibonacci::Edge.new
  NODE_SCOPE = References::Fibonacci::Node.new

module_function

  def compute(n)
    base = Evaluator.current.find(NODE_SCOPE, n)
    return base unless base.nil?

    Evaluator.current.find(EDGE_SCOPE, n).sum { |child| compute(child) }
  end
end
