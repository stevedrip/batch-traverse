module References
  module Organization
    class Manager < Reference
      def where(ids)
        ::Employee.where(manager_id: ids).group_by(&:manager_id)
      end
    end
  end
end
