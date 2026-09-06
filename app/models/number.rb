# frozen_string_literal: true

require_relative "application_record"

# id is the number itself. values is {"english" => [lexeme_id, ...], "spanish"
# => [lexeme_id, ...]} - the lexemes that spell it out in each language, in
# order: fourteen is {"english" => [id_of("four"), id_of("teen")]}. Holding
# both languages' lexeme ids on the one row is what makes them structural,
# not content - knowing which ids compose a number doesn't require reading
# either language's actual words, only asking Lexeme for the ids a task
# actually wants does that.
class Number < ApplicationRecord
end
