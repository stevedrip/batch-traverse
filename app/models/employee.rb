# frozen_string_literal: true

require "set"

require_relative "department"
require_relative "../references/organization/employee"
require_relative "../references/organization/manager"

class Employee < ActiveRecord::Base
  SCOPE = References::Organization::Employee.new
  MANAGER_SCOPE = References::Organization::Manager.new

  # The department this employee belongs to, resolved from the nearest
  # managerial ancestor if this employee has none of their own.
  def department_name
    return Evaluator.current.find(Department::SCOPE, department_id).name unless department_id.nil?
    return nil if manager_id.nil?

    Evaluator.current.find(SCOPE, manager_id).department_name
  end

  # This method is intentionally inefficient - it traverses both upward (via
  # department_name, for anyone without a department of their own) and
  # downward (into every report), so the same managerial chain gets re-walked
  # once per descendant instead of once. That repetition is exactly what a
  # caching or batching Evaluator should absorb; a bare Metric pays for it in
  # full every time.
  def department_names
    Set.new.tap do |names|
      name = department_name
      names << name unless name.nil?

      reports = Evaluator.current.find(MANAGER_SCOPE, id) || []
      Evaluator.current.map(reports) { |employee| employee.department_names }.each do |found|
        names.merge(found)
      end
    end
  end

  # This employee's own salary, plus everyone under them, however deep.
  def salary_total
    reports = Evaluator.current.find(MANAGER_SCOPE, id) || []
    salary + Evaluator.current.map(reports) { |employee| employee.salary_total }.sum
  end
end
