module References
  module Organization
    class Department < Reference
      def where(ids)
        ::Department.where(id: ids).index_by(&:id)
      end
    end
  end
end
