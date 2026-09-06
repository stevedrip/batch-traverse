# frozen_string_literal: true

require_relative "application_record"

# An atomic word for one language - "four", "teen", "veinti" - referenced by id
# from Number#values so a compound like fourteen is expressed as the two ids of
# "four" and "teen" rather than duplicating "teen" as a string on every number
# that ends in it. A handful of numbers need a compound-only stem distinct from
# their standalone word (English "eight" vs the "eigh" of eighteen; Spanish
# "seis" vs the accented "séis" of dieciséis/veintiséis) - those get their own
# row rather than overloading one lexeme with two spellings.
class Lexeme < ApplicationRecord
end
