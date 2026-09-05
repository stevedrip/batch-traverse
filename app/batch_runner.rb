# frozen_string_literal: true

require "fiber"

# Drives several jobs concurrently, one Fiber each, resuming every fiber once per
# tick and handing whatever they ask for and don't already have to the scope as one
# batch. A job that only needs a handful of ids still only ever asks for a handful
# of ids - the saving comes from sharing a round trip with every other job still
# waiting on one, not from fetching more than anything asked for.
class BatchRunner
  def self.run(scope, jobs)
    fibers = jobs.map { |job| Fiber.new { job.call(scope) } }
    results = Array.new(jobs.size)
    pending = (0...jobs.size).to_a

    until pending.empty?
      requests = []
      still_pending = []

      pending.each do |i|
        value = fibers[i].resume
        if fibers[i].alive?
          requests << value
          still_pending << i
        else
          results[i] = value
        end
      end

      pending = still_pending
      scope.load_batch(requests) unless requests.empty?
    end

    results
  end
end
