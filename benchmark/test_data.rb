# frozen_string_literal: true

module Benchmark
  # Namspace for all test data generation methods.
  module TestData
    # Generate a random number between num1 and num2.
    def self.random_number(num1, num2)
      (num1.rand * num2).floor
    end

    # Generate predictable, but variable test values of different types.
    def self.random_value(num = 0, seed = 0)
      r = Random.new(num + seed) # use the index as the seed for predictable results
      case random_number(r, 5)
      when 0 then "Some String value #{num}"
      when 1 then r.rand # a float value
      when 2 then random_number(r, 100_000) # a large integer
      when 3 then (0..random_number(r, 100)).to_a # an array
      when 4 then { a: 1, b: 2, c: 3 } # a hash
      else
        'generic string'
      end
    end

    # Generate a predictable, but variable hash with a range of data types.
    def self.test_hash(n_keys = 5, seed = 0)
      n_keys.times.to_h { |i| ["key#{i}", random_value(i, seed)] }
    end
  end
end
