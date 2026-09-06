# frozen_string_literal: true

require_relative "test_helper"

class NumbersTest < Minitest::Test
  ENGLISH = {
    1 => "one", 2 => "two", 3 => "three", 4 => "four", 5 => "five",
    6 => "six", 7 => "seven", 8 => "eight", 9 => "nine", 10 => "ten",
    11 => "eleven", 12 => "twelve", 13 => "thirteen", 14 => "fourteen", 15 => "fifteen",
    16 => "sixteen", 17 => "seventeen", 18 => "eighteen", 19 => "nineteen", 20 => "twenty",
    # English also inserts a hyphen here (twenty-one) that plain concatenation
    # of the "twenty" and "one" lexemes doesn't reproduce - see Numbers.spell.
    21 => "twentyone", 22 => "twentytwo", 23 => "twentythree", 24 => "twentyfour", 25 => "twentyfive",
    26 => "twentysix", 27 => "twentyseven", 28 => "twentyeight", 29 => "twentynine", 30 => "thirty"
  }.freeze

  SPANISH = {
    1 => "uno", 2 => "dos", 3 => "tres", 4 => "cuatro", 5 => "cinco",
    6 => "seis", 7 => "siete", 8 => "ocho", 9 => "nueve", 10 => "diez",
    11 => "once", 12 => "doce", 13 => "trece", 14 => "catorce", 15 => "quince",
    16 => "dieciséis", 17 => "diecisiete", 18 => "dieciocho", 19 => "diecinueve", 20 => "veinte",
    21 => "veintiuno", 22 => "veintidós", 23 => "veintitrés", 24 => "veinticuatro", 25 => "veinticinco",
    26 => "veintiséis", 27 => "veintisiete", 28 => "veintiocho", 29 => "veintinueve", 30 => "treinta"
  }.freeze

  # F(8) down to F(1): the Fibonacci sequence counting down from 21, stopping
  # before F(0) = 0 since Numbers only seeds words for 1..30.
  COUNTDOWN = (1..8).to_a.reverse.freeze
  VALUES = [21, 13, 8, 5, 3, 2, 1, 1].freeze

  def test_spelling_every_seeded_number_is_correct_in_both_languages
    scope = CacheScope.new

    (1..30).each do |n|
      assert_equal(ENGLISH.fetch(n), Numbers.spell(scope, "english", n), "spell(#{n}, english)")
      assert_equal(SPANISH.fetch(n), Numbers.spell(scope, "spanish", n), "spell(#{n}, spanish)")
    end
  end

  def test_counting_down_fibonacci_in_english_never_loads_spanish_lexemes
    scope = CacheScope.new

    values = COUNTDOWN.map { |n| Fibonacci.compute(scope, n) }
    assert_equal(VALUES, values)

    words = values.map { |value| Numbers.spell(scope, "english", value) }
    assert_equal(VALUES.map { |v| ENGLISH.fetch(v) }, words)

    assert_equal(0, scope.round_trips[Numbers::SPANISH_LEXEME_SCOPE])
    # NUMBER_SCOPE is structural (both languages' lexeme ids live on one row),
    # so it's fetched regardless of which language ends up being spelled - one
    # round trip per distinct value: 21, 13, 8, 5, 3, 2, 1.
    assert_equal(7, scope.round_trips[Numbers::NUMBER_SCOPE])
    # Distinct English lexemes needed across all eight values: twenty, one,
    # thir, teen, eight, five, three, two - the repeated final 1 costs nothing
    # further once "one" is cached.
    assert_equal(8, scope.round_trips[Numbers::ENGLISH_LEXEME_SCOPE])
  end

  def test_counting_down_fibonacci_in_spanish_never_loads_english_lexemes
    scope = CacheScope.new

    values = COUNTDOWN.map { |n| Fibonacci.compute(scope, n) }
    assert_equal(VALUES, values)

    words = values.map { |value| Numbers.spell(scope, "spanish", value) }
    assert_equal(VALUES.map { |v| SPANISH.fetch(v) }, words)

    assert_equal(0, scope.round_trips[Numbers::ENGLISH_LEXEME_SCOPE])
    assert_equal(7, scope.round_trips[Numbers::NUMBER_SCOPE])
    # Distinct Spanish lexemes needed: veinti, uno, trece, ocho, cinco, tres, dos.
    assert_equal(7, scope.round_trips[Numbers::SPANISH_LEXEME_SCOPE])
  end

  # Same guarantee under real concurrent batching: 8 jobs, each computing its
  # own fib(n) and spelling the result, run together through one BatchScope.
  # Sharing the fibonacci and lexeme substructure drops the round trips further
  # still (8 English lexeme fetches sequentially -> 3 batched; 7 NUMBER_SCOPE
  # fetches -> 2 batched), but the other language is still never touched.
  def test_batch_scope_keeps_english_and_spanish_isolated_under_concurrent_jobs
    batch = BatchScope.new
    jobs = COUNTDOWN.map { |n| ->(scope) { Numbers.spell(scope, "english", Fibonacci.compute(scope, n)) } }

    assert_equal(VALUES.map { |v| ENGLISH.fetch(v) }, batch.run(jobs))
    assert_equal(0, batch.round_trips[Numbers::SPANISH_LEXEME_SCOPE])
    assert_equal(2, batch.round_trips[Numbers::NUMBER_SCOPE])
    assert_equal(3, batch.round_trips[Numbers::ENGLISH_LEXEME_SCOPE])

    batch = BatchScope.new
    jobs = COUNTDOWN.map { |n| ->(scope) { Numbers.spell(scope, "spanish", Fibonacci.compute(scope, n)) } }

    assert_equal(VALUES.map { |v| SPANISH.fetch(v) }, batch.run(jobs))
    assert_equal(0, batch.round_trips[Numbers::ENGLISH_LEXEME_SCOPE])
    assert_equal(2, batch.round_trips[Numbers::NUMBER_SCOPE])
    assert_equal(2, batch.round_trips[Numbers::SPANISH_LEXEME_SCOPE])
  end
end
