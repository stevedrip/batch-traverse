# frozen_string_literal: true

require_relative "../references/organization/department"

class Department < ActiveRecord::Base
  SCOPE = References::Organization::Department.new
end
