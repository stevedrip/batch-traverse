# frozen_string_literal: true

source "https://rubygems.org"

ruby "~> #{File.read('.ruby-version').chomp}"

gem "minitest"
gem "rake"

# For testing the Scope contract against real AR relations, not just plain
# lambdas over an in-memory Hash.
gem "activerecord"
gem "sqlite3"
