# frozen_string_literal: true

require_relative 'benchmark'

module Benchmark
  # Class for formatting RoadRunner results.
  class Result
    attr_reader :name, :description, :unit, :date, :measurements

    def initialize(name, description, unit, measurements)
      @name = name
      @description = description
      @unit = unit
      @measurements = measurements
    end

    def format
      {
        'name' => @name,
        'description' => @description,
        'unit' => @unit,
        'date' => Time.now.to_i,
        'dimensions' => [
          { name: 'RubyVersion', value: RUBY_VERSION.rpartition('.').first },
          { name: 'CPU', value: RbConfig::CONFIG['host_cpu'] },
          { name: 'OS', value: Benchmark.host_os }
        ],
        'measurements' => @measurements.is_a?(Array) ? @measurements : [@measurements]
      }
    end
  end
end