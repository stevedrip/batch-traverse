# frozen_string_literal: true

require_relative "metric_scope"

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
