module References
  module Fibonacci
    # ids -> {id => value}, entries omitted for anything past the base cases -
    # those have to be computed from their children instead.
    class Node < Reference
      def where(ids)
        ids.each_with_object({}) do |id, h|
          case id
          when 0 then h[0] = 0
          when 1 then h[1] = 1
          end
        end
      end
    end
  end
end
