# frozen_string_literal: true

# Fetches directly, one round trip per #where call - the naive baseline every
# other Scope here is measured against, and the metric they're measured on:
# round_trips counts real fetches by the scope they went through (EDGE_SCOPE,
# NODE_SCOPE, ...), no matter which subclass triggered them. #find is defined once,
# here, in terms of #where; every subclass overloads #where instead of #find, so
# caching or batching only ever has to change when a round trip happens, never
# how a single id turns into one.
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
