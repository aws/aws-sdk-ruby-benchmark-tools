# frozen_string_literal: true

# Namespace for all RoadRunner code
module RoadRunner
  def self.initialize_report_data
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

  def self.convert_result(service, data, date, dimensions)
    results = []
    service_name = service.split('-')[-1]
    data.each do |key, value|
      next if key == 'gem_version'

      result = {}
      result['name'] = "#{service_name}.#{generate_result_name(key)}"
      result['description'] = generate_description(key)
      result['unit'] = unit(key)
      result['date'] = date
      result['dimensions'] = generate_dimensions(key, dimensions)
      result['measurements'] = value.is_a?(Array) ? value : [value]

      # RoadRunner currently doesn't support kilobyte units. Converting to megabytes instead.
      if result['unit'] == 'Kilobytes'
        result = 'Megabytes'
        if result['measurements'].is_a?(Array)
          result['measurements'].each_with_index do |measurement, index|
            result['measurements'][index] = measurement / 1000.0
          end
        else
          result['measurements'] = result['measurements'] / 1000.0
        end
      end
      results << result
    end
    results
  end

  def self.generate_result_name(benchmark)
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

  def self.generate_description(benchmark)
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

  def self.unit(benchmark)
    if benchmark.include?('kb')
      'Kilobytes'
    elsif benchmark.include?('ms')
      'Milliseconds'
    end
  end

  def self.generate_dimensions(key, shared_dimensions)
    dimensions = shared_dimensions.dup
    if key.include?('small')
      dimensions << { name: 'Size', value: 'Small'}
    elsif key.include?('large')
      dimensions << { name: 'Size', value: 'Large'}
    end
    dimensions
  end
end