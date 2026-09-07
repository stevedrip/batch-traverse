# frozen_string_literal: true

require "minitest/autorun"
require "active_record"

require_relative "../app/batch_traverse"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false
require_relative "../db/schema"
