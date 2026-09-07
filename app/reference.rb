# frozen_string_literal: true

# One data source a traversal can ask an Evaluator about - the "scope" in
# evaluator.where(scope, ids)/evaluator.find(scope, id). #where is the only
# thing a subclass must implement: a bulk lookup, ids -> {id => value}, with
# entries omitted for ids it has nothing to say about. #find is answered in
# terms of it, so a single-id lookup and a many-id lookup are always the same
# rule.
#
# A Reference never talks to an Evaluator itself - resolving one is the
# Evaluator's job (see Evaluator::Eager/Metric/Cache/Concurrent), so the same
# Reference works unchanged whether it's read directly, cached, or batched
# across concurrent Fibers.
class Reference
  def where(ids)
    raise NotImplementedError
  end

  def find(id)
    where([id])[id]
  end
end
