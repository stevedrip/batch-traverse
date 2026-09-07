# frozen_string_literal: true

require_relative "test_helper"

# department_names is intentionally inefficient - see Employee - so it's
# where an Evaluator's round trips actually diverge, not just its result.
class DepartmentNamesTest < Minitest::Test
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

  def test_metric_collects_every_distinct_department_under_a_person
    Evaluator.using(Evaluator::Metric.new(Evaluator::Eager.new)) do
      assert_equal(Set["Company", "Engineering", "Sales"], @ceo.department_names)
      assert_equal(Set["Engineering"], @manager_a.department_names)
    end
  end

  def test_metric_re_fetches_the_same_manager_and_department_on_every_repeat
    metric = Evaluator::Metric.new(Evaluator::Eager.new)
    Evaluator.using(metric) { @ceo.department_names }

    # 4 employees (manager_a x2, manager_b x2) walk upward through SCOPE to
    # find their manager, 7 department lookups happen (one per employee
    # visited, since a bare Metric shares nothing).
    assert_equal(4, metric.round_trips[Employee::SCOPE])
    assert_equal(7, metric.round_trips[Department::SCOPE])
  end

  def test_cache_collects_every_distinct_department_under_a_person
    Evaluator.using(Evaluator::Cache.new(Evaluator::Eager.new)) do
      assert_equal(Set["Company", "Engineering", "Sales"], @ceo.department_names)
      assert_equal(Set["Engineering"], @manager_a.department_names)
    end
  end

  def test_cache_fetches_each_repeated_manager_and_department_only_once
    metric = Evaluator::Metric.new(Evaluator::Eager.new)
    Evaluator.using(Evaluator::Cache.new(metric)) { @ceo.department_names }

    # manager_a and manager_b are each looked up via SCOPE once, not once per
    # report asking about them; Company/Engineering/Sales are each fetched
    # once, not once per employee under them.
    assert_equal(2, metric.round_trips[Employee::SCOPE])
    assert_equal(3, metric.round_trips[Department::SCOPE])
  end

  def test_concurrent_collects_every_distinct_department_under_a_person
    concurrent = Evaluator::Concurrent.new(Evaluator::Eager.new)
    result = Evaluator.using(concurrent) { concurrent.map([@ceo]) { |e| e.department_names } }
    assert_equal([Set["Company", "Engineering", "Sales"]], result)
  end

  def test_concurrent_alone_still_re_fetches_departments_forgotten_between_ticks
    metric = Evaluator::Metric.new(Evaluator::Eager.new)
    concurrent = Evaluator::Concurrent.new(metric)
    Evaluator.using(concurrent) { concurrent.map([@ceo]) { |e| e.department_names } }

    # Concurrent only ever holds an answer long enough for whoever asked for
    # it this tick to read it - the two employees under manager_a both need
    # SCOPE(manager_a) at the same nested-map tick, so that's still merged,
    # but Engineering/Sales are consulted from several different tree levels
    # across different ticks, and each of those pays again since nothing
    # remembers the previous one.
    assert_equal(2, metric.round_trips[Employee::SCOPE])
    assert_equal(4, metric.round_trips[Department::SCOPE])
  end

  def test_concurrent_wrapping_a_cache_fetches_each_repeated_manager_and_department_only_once
    metric = Evaluator::Metric.new(Evaluator::Eager.new)
    concurrent = Evaluator::Concurrent.new(Evaluator::Cache.new(metric))
    Evaluator.using(concurrent) { concurrent.map([@ceo]) { |e| e.department_names } }

    # Wrapping a Cache underneath restores full memoization across the whole
    # nested #map, matching (or beating) Cache alone above.
    assert_equal(2, metric.round_trips[Employee::SCOPE])
    assert_equal(2, metric.round_trips[Department::SCOPE])
  end
end
