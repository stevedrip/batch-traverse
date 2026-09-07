module References
  module Organization
    class Employee < Reference
      def where(ids)
        ::Employee.where(id: ids).index_by(&:id)
      end
    end
  end
end
