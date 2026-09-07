# frozen_string_literal: true

module Evaluator
  # #find is the same rule for every evaluator - a single id is a one-element
  # #where - so it's defined once here instead of once per class.
  module Findable
    def find(scope, id)
      where(scope, [id])[id]
    end
  end
end
