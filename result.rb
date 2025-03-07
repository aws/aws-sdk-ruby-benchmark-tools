# frozen_string_literal: true

module Benchmark
  # Class for formatting RoadRunner results.
  class Result
    attr_reader :name, :description, :unit, :date, :measurements

    def initialize(name, description, unit, date, measurements)
      @name = name
      @description = description
      @unit = unit
      @date = date
      @measurements = measurements
    end

    def format
      {
        'name' => @name,
        'description' => @description,
        'unit' => @unit,
        'date' => @date,
        'dimensions' => [
          { name: 'RubyVersion', value: RUBY_VERSION.split('.')[0..1].join('.') }
        ],
        'measurements' => @measurements
      }
    end
  end
end
