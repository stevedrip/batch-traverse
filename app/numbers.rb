# frozen_string_literal: true

require_relative "models/lexeme"
require_relative "models/number"

# Spells out 1..30 in English and Spanish by composing Lexeme rows, backed by
# real AR relations instead of an in-memory Hash - the same Scope contract
# (find/where over an ids -> {id => value} lookup) works whether the lookup is
# a lambda closing over a Hash or an AR relation issuing a real query.
#
# NUMBER_SCOPE answers which lexemes compose a number, for both languages at
# once - that's structure, not content, so reading it doesn't touch either
# language's words. The two LEXEME_SCOPEs answer a lexeme's actual word, and
# are the only things that ever read a specific language's content: a
# traversal that only ever spells English numbers never issues a single
# SPANISH_LEXEME_SCOPE round trip, no matter how it's batched.
module Numbers
  NUMBER_SCOPE = ->(ids) { Number.where(id: ids).pluck(:id, :values).to_h }

  ENGLISH_LEXEME_SCOPE = ->(ids) { Lexeme.where(language: "english", id: ids).pluck(:id, :value).to_h }
  SPANISH_LEXEME_SCOPE = ->(ids) { Lexeme.where(language: "spanish", id: ids).pluck(:id, :value).to_h }

  LEXEME_SCOPE_FOR = {"english" => ENGLISH_LEXEME_SCOPE, "spanish" => SPANISH_LEXEME_SCOPE}.freeze

  # Standalone words, plus the handful of compound-only stems a few numbers
  # need instead of their standalone spelling (see Lexeme).
  ENGLISH_LEXEMES = {
    one: "one", two: "two", three: "three", four: "four", five: "five",
    six: "six", seven: "seven", eight: "eight", nine: "nine", ten: "ten",
    eleven: "eleven", twelve: "twelve", twenty: "twenty", thirty: "thirty",
    thir: "thir", fif: "fif", eigh: "eigh", teen: "teen"
  }.freeze

  SPANISH_LEXEMES = {
    uno: "uno", dos: "dos", tres: "tres", cuatro: "cuatro", cinco: "cinco",
    seis: "seis", siete: "siete", ocho: "ocho", nueve: "nueve", diez: "diez",
    once: "once", doce: "doce", trece: "trece", catorce: "catorce", quince: "quince",
    veinte: "veinte", treinta: "treinta",
    dieci: "dieci", veinti: "veinti", dos_acc: "dós", tres_acc: "trés", seis_acc: "séis"
  }.freeze

  # number => ordered lexeme keys, one array per language. 13-19 and 21-29
  # reuse the same "teen"/"twenty"/"dieci"/"veinti" lexeme as every other
  # number in their group, same as the accented compound stems (séis is used
  # by both 16 and 26).
  ENGLISH_COMPOSITION = {
    1 => [:one], 2 => [:two], 3 => [:three], 4 => [:four], 5 => [:five],
    6 => [:six], 7 => [:seven], 8 => [:eight], 9 => [:nine], 10 => [:ten],
    11 => [:eleven], 12 => [:twelve],
    13 => [:thir, :teen], 14 => [:four, :teen], 15 => [:fif, :teen],
    16 => [:six, :teen], 17 => [:seven, :teen], 18 => [:eigh, :teen], 19 => [:nine, :teen],
    20 => [:twenty],
    21 => [:twenty, :one], 22 => [:twenty, :two], 23 => [:twenty, :three],
    24 => [:twenty, :four], 25 => [:twenty, :five], 26 => [:twenty, :six],
    27 => [:twenty, :seven], 28 => [:twenty, :eight], 29 => [:twenty, :nine],
    30 => [:thirty]
  }.freeze

  SPANISH_COMPOSITION = {
    1 => [:uno], 2 => [:dos], 3 => [:tres], 4 => [:cuatro], 5 => [:cinco],
    6 => [:seis], 7 => [:siete], 8 => [:ocho], 9 => [:nueve], 10 => [:diez],
    11 => [:once], 12 => [:doce], 13 => [:trece], 14 => [:catorce], 15 => [:quince],
    16 => [:dieci, :seis_acc], 17 => [:dieci, :siete], 18 => [:dieci, :ocho], 19 => [:dieci, :nueve],
    20 => [:veinte],
    21 => [:veinti, :uno], 22 => [:veinti, :dos_acc], 23 => [:veinti, :tres_acc],
    24 => [:veinti, :cuatro], 25 => [:veinti, :cinco], 26 => [:veinti, :seis_acc],
    27 => [:veinti, :siete], 28 => [:veinti, :ocho], 29 => [:veinti, :nueve],
    30 => [:treinta]
  }.freeze

module_function

  # Inserts every Lexeme and Number row. Static reference data, so a test
  # suite only needs to call this once, not reset it between examples.
  def seed!
    english_ids = ENGLISH_LEXEMES.transform_values { |value| Lexeme.create!(language: "english", value: value).id }
    spanish_ids = SPANISH_LEXEMES.transform_values { |value| Lexeme.create!(language: "spanish", value: value).id }

    (1..30).each do |n|
      Number.create!(
        id: n,
        values: {
          "english" => ENGLISH_COMPOSITION.fetch(n).map { |key| english_ids.fetch(key) },
          "spanish" => SPANISH_COMPOSITION.fetch(n).map { |key| spanish_ids.fetch(key) }
        }
      )
    end
  end

  # Spells n out in the given language ("english" or "spanish") by finding
  # which lexemes compose it, then joining their values - a plain
  # concatenation, so it reproduces exact standard spelling everywhere a
  # compound's stems already do (fourteen, dieciséis, ...) but not where
  # English also inserts a hyphen (twenty-one comes out "twentyone").
  def spell(scope, language, n)
    lexeme_ids = scope.find(NUMBER_SCOPE, n).fetch(language)
    lexeme_scope = LEXEME_SCOPE_FOR.fetch(language)

    lexeme_ids.map { |lexeme_id| scope.find(lexeme_scope, lexeme_id) }.join
  end
end
