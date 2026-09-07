# frozen_string_literal: true

# Requires a connection to already be established (see test/test_helper.rb) -
# this only defines the tables against it.
ActiveRecord::Schema.define do
  create_table :departments, force: true do |t|
    t.string :name, null: false
  end

  create_table :employees, force: true do |t|
    t.integer :manager_id
    t.integer :department_id
    t.integer :salary, null: false
  end
end
