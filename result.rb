# frozen_string_literal: true

require_relative 'benchmark'

module Benchmark
  # Class for formatting RoadRunner results.
  class Result
    attr_reader :name, :description, :measurements

    def initialize(name, description, measurements)
      @name = name
      @description = description
      @measurements = measurements
    end

    # Will need to update this in the future if we include more than two unit.
    # This is a temporary solution to pass Rubocop.
    def unit(name)
      name.split('.').last == 'time' ? 'Milliseconds' : 'Megabytes'
    end

    def format
      {
        'name' => @name,
        'description' => @description,
        'unit' => unit(@name),
        'date' => Time.now.to_i,
        'dimensions' => [
          { name: 'RubyVersion', value: RUBY_VERSION.rpartition('.').first }
        ],
        'measurements' => @measurements.is_a?(Array) ? @measurements : [@measurements]
      }
    end
  end
end
