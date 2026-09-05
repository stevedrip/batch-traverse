# frozen_string_literal: true

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
# one round trip. Every Scope (MetricScope, CacheScope, BatchScope) answers
# id-by-id lookups against one of those without ever changing what it returns:
# batching is a property of how a traversal asks for data, not of the data source
# itself, so swapping the Scope a traversal runs against never changes its
# result, only how many round trips it costs.
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
