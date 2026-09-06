# frozen_string_literal: true

# Requires a connection to already be established (see test/test_helper.rb) -
# this only defines the tables against it.
ActiveRecord::Schema.define do
  create_table :lexemes, force: true do |t|
    t.string :language, null: false
    t.string :value, null: false
  end

  create_table :numbers, force: true do |t|
    t.json :values, null: false
  end
end
