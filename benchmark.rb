# frozen_string_literal: true

require_relative 'benchmark/gem'

# Namespace for all benchmarking code
module Benchmark
  # Monotonic system clock should be used for any time difference measurements
  def self.monotonic_milliseconds
    if defined?(Process::CLOCK_MONOTONIC)
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) / 1000.0
    else
      Time.now.to_f * 1000.0
    end
  end

  # Benchmark a block, returning an array of times (to allow statistic computation)
  def self.measure_time(num = 300, &block)
    values = Array.new(num)
    num.times do |i|
      t1 = monotonic_milliseconds
      block.call
      values[i] = monotonic_milliseconds - t1
    end
    values
  end

  # Run a block in a fork and returns the data from it
  # the block must take a single argument and will be called with an empty hash
  # any data that should be communicated back to the parent process can be written to that hash
  # rubocop:disable Metrics/MethodLength
  def self.fork_run(&block)
    # fork is not supported in JRuby, for now, just run this in the same process
    # data collected will not be as useful, but still valid for relative comparisons over time
    if defined?(JRUBY_VERSION)
      h = {}
      block.call(h)
      return h
    end

    rd, wr = IO.pipe
    p1 = fork do
      h = {}
      block.call(h)
      wr.write(JSON.dump(h))
      wr.close
    end
    Process.wait(p1)
    wr.close
    h = JSON.parse(rd.read, symbolize_names: true)
    rd.close
    h
  end
  # rubocop:enable Metrics/MethodLength

  def self.host_os
    case RbConfig::CONFIG['host_os']
    when /mac|darwin/
      'macos'
    when /linux|cygwin/
      'linux'
    when /mingw|mswin/
      'windows'
    else
      'other'
    end
  end

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/AbcSize
  def self.initialize_report_data
    report_data = { 'version' => '1.0' }
    begin
      report_data['commit_id'] = `git rev-parse HEAD`.strip
    rescue StandardError
      # unable to get a commit, maybe run outside of a git repo.  Skip
    end
    report_data['ruby_engine'] = RUBY_ENGINE
    report_data['ruby_engine_version'] = RUBY_ENGINE_VERSION
    report_data['ruby_version'] = RUBY_VERSION

    report_data['cpu'] = RbConfig::CONFIG['host_cpu']
    report_data['os'] = host_os
    report_data['execution_env'] = ENV['EXECUTION_ENV'] || 'unknown'

    report_data['timestamp'] = Time.now.to_i

    report_data['benchmark'] = {}
    report_data
  end
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/AbcSize
end
