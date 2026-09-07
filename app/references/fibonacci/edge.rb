module References
  module Fibonacci
    # ids -> {id => [child_id, child_id]}, both children always >= 0 since
    # this is only ever consulted for ids Node doesn't already answer.
    class Edge < Reference
      def where(ids)
        ids.each_with_object({}) { |id, h| h[id] = [id - 1, id - 2].select { |i| i >= 0 } }
      end
    end
  end
end
