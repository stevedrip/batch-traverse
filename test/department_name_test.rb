# frozen_string_literal: true

require_relative "test_helper"

class DepartmentNameTest < Minitest::Test
  def setup
    @company = Department.create!(name: "Company")
    @engineering = Department.create!(name: "Engineering")
    @sales = Department.create!(name: "Sales")

    @ceo = Employee.create!(salary: 300_000, department_id: @company.id)
    @manager_a = Employee.create!(manager_id: @ceo.id, department_id: @engineering.id, salary: 150_000)
    @manager_b = Employee.create!(manager_id: @ceo.id, department_id: @sales.id, salary: 140_000)
    @employee_a1 = Employee.create!(manager_id: @manager_a.id, salary: 90_000)
    @employee_b1 = Employee.create!(manager_id: @manager_b.id, salary: 85_000)
  end

  def test_metric_resolves_an_employees_own_department
    Evaluator.using(Evaluator::Metric.new(Evaluator::Eager.new)) do
      assert_equal("Company", @ceo.department_name)
      assert_equal("Engineering", @manager_a.department_name)
    end
  end

  def test_metric_resolves_upward_through_managers_for_an_employee_with_none_of_their_own
    Evaluator.using(Evaluator::Metric.new(Evaluator::Eager.new)) do
      assert_equal("Engineering", @employee_a1.department_name)
      assert_equal("Sales", @employee_b1.department_name)
    end
  end

  def test_cache_resolves_an_employees_own_department
    Evaluator.using(Evaluator::Cache.new(Evaluator::Eager.new)) do
      assert_equal("Company", @ceo.department_name)
      assert_equal("Engineering", @manager_a.department_name)
    end
  end

  def test_cache_resolves_upward_through_managers_for_an_employee_with_none_of_their_own
    Evaluator.using(Evaluator::Cache.new(Evaluator::Eager.new)) do
      assert_equal("Engineering", @employee_a1.department_name)
      assert_equal("Sales", @employee_b1.department_name)
    end
  end

  def test_concurrent_resolves_an_employees_own_department
    concurrent = Evaluator::Concurrent.new(Evaluator::Eager.new)
    result = Evaluator.using(concurrent) do
      concurrent.map([@ceo, @manager_a]) { |employee| employee.department_name }
    end
    assert_equal(["Company", "Engineering"], result)
  end

  def test_concurrent_resolves_upward_through_managers_for_an_employee_with_none_of_their_own
    concurrent = Evaluator::Concurrent.new(Evaluator::Eager.new)
    result = Evaluator.using(concurrent) do
      concurrent.map([@employee_a1, @employee_b1]) { |employee| employee.department_name }
    end
    assert_equal(["Engineering", "Sales"], result)
  end
end
