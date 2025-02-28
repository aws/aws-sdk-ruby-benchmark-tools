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
      GC.disable
      t1 = Process.times
      block.call
      t2 = Process.times
      GC.enable
      values[i] = ((t2.utime + t2.stime) - (t1.utime + t1.stime)) * 1000.0
    end
    values
  end

  # Run a block in a fork and returns the data from it
  # the block must take a single argument and will be called with an empty hash
  # any data that should be communicated back to the parent process can be written to that hash
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

  #
  # Methods used to generate results.json report for RoadRunner.
  #
  def self.initialize_rr_report_data
    report_data = {}
    report_data['productId'] = 'AWS SDK for Ruby v3'
    begin
      report_data['commitId'] = `git rev-parse HEAD`.strip
    rescue StandardError
      # unable to get a commit, maybe run outside a git repo.  Skip
    end
    report_data['results'] = []
    report_data
  end

  def self.convert_to_rr_result(service, data, date, dimensions)
    results = []
    service_name = service.split('-')[-1]
    data.each do |key, value|
      next if key == 'gem_version'

      result = {}
      result['name'] = "#{service_name}.#{generate_rr_result_name(key)}"
      result['description'] = generate_rr_description(key)
      result['unit'] = rr_unit(key)
      result['date'] = date
      result['dimensions'] = generate_rr_dimensions(key, dimensions, data['gem_version'])
      result['measurements'] = value.is_a?(Array) ? value : [value]
      results << result
    end
    results
  end

  def self.generate_rr_result_name(benchmark)
    split = benchmark.split('_')
    split.delete('mem')
    split.delete('time')
    split.delete('size')
    split[-1] = 'time' if split[-1] == 'ms'
    split[-1] = 'size' if split[-1] == 'kb'
    case split[0]
    when 'gem', 'require', 'client'
      split.join('.')
    else
      idx = split.index('small') || split.index('large')
      if idx
        "#{split[0...idx].join}.#{split[(idx + 1)..-1].join('.')}"
      elsif split.include?('time')
        "#{split[0...-1].join}.#{split[-1]}"
      elsif split.include?('size')
        "#{split[0...-2].join}.#{split[-2]}.#{split[-1]}"
      else
        split.join
      end
    end
  end

  def self.generate_rr_description(benchmark)
    split = benchmark.split('_')
    split.delete('mem')
    split.delete('time')
    split.delete('size')
    split[-1] = 'time' if split[-1] == 'ms'
    split[-1] = 'size' if split[-1] == 'kb'
    case split[0]
    when 'gem'
      'The size of the gem.'
    when 'require'
      if split.include?('time')
        'The time it takes to require the gem.'
      else
        "The amount of memory #{split[1]} when requiring the gem."
      end
    when 'client'
      if split.include?('time')
        'The time it takes to initialize the client.'
      else
        "The amount of memory #{split[1]} when creating the client."
      end
    else
      idx = split.index('small') || split.index('large')
      if idx
        operation = split[0...idx].map(&:capitalize).join
        if split.include?('time')
          "The time it takes to perform the #{operation} operation."
        else
          "The amount of memory allocated to perform the #{operation} operation."
        end
      elsif split.include?('time')
        operation = split[0...-1].map(&:capitalize).join
        "The time it takes to perform the #{operation} operation."
      elsif split.include?('size')
        operation = split[0...-2].map(&:capitalize).join
        "The amount of memory allocated to perform the #{operation} operation."
      else
        split.join(' ')
      end
    end
  end

  def self.rr_unit(benchmark)
    if benchmark.include?('kb')
      'Kilobytes'
    elsif benchmark.include?('ms')
      'Milliseconds'
    end
  end

  def self.generate_rr_dimensions(key, shared_dimensions, gem_version)
    dimensions = shared_dimensions.dup
    dimensions << { name: 'GemVersion', value: gem_version }
    if key.include?('small')
      dimensions << { name: 'Size', value: 'Small'}
    elsif key.include?('large')
      dimensions << { name: 'Size', value: 'Large'}
    end
    dimensions
  end
end
