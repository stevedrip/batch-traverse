# frozen_string_literal: true

require_relative "test_helper"

class SalaryTotalTest < Minitest::Test
  def setup
    @company = Department.create!(name: "Company")
    @engineering = Department.create!(name: "Engineering")
    @sales = Department.create!(name: "Sales")

    @ceo = Employee.create!(salary: 300_000, department_id: @company.id)
    @manager_a = Employee.create!(manager_id: @ceo.id, department_id: @engineering.id, salary: 150_000)
    @manager_b = Employee.create!(manager_id: @ceo.id, department_id: @sales.id, salary: 140_000)
    @employee_a1 = Employee.create!(manager_id: @manager_a.id, salary: 90_000)
    @employee_a2 = Employee.create!(manager_id: @manager_a.id, salary: 95_000)
    @employee_b1 = Employee.create!(manager_id: @manager_b.id, salary: 85_000)
    @employee_b2 = Employee.create!(manager_id: @manager_b.id, salary: 80_000)
  end

  def test_metric_sums_an_employees_own_salary_and_everyone_under_them
    Evaluator.using(Evaluator::Metric.new(Evaluator::Eager.new)) do
      assert_equal(940_000, @ceo.salary_total)
      assert_equal(335_000, @manager_a.salary_total)
      assert_equal(90_000, @employee_a1.salary_total)
    end
  end

  def test_cache_sums_an_employees_own_salary_and_everyone_under_them
    Evaluator.using(Evaluator::Cache.new(Evaluator::Eager.new)) do
      assert_equal(940_000, @ceo.salary_total)
      assert_equal(335_000, @manager_a.salary_total)
      assert_equal(90_000, @employee_a1.salary_total)
    end
  end

  def test_concurrent_sums_an_employees_own_salary_and_everyone_under_them
    concurrent = Evaluator::Concurrent.new(Evaluator::Eager.new)
    result = Evaluator.using(concurrent) do
      concurrent.map([@ceo, @manager_a, @employee_a1]) { |employee| employee.salary_total }
    end
    assert_equal([940_000, 335_000, 90_000], result)
  end
end
