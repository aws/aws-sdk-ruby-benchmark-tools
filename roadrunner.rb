# frozen_string_literal: true

# Namespace for all RoadRunner code
module RoadRunner
  class << self
    def run(commit_id)
      report = JSON.parse(File.read('benchmark_report.json'))
      rr_report = RoadRunner.initialize_report_data
      rr_report['commitId'] = commit_id if rr_report['commitId'] == ''

      date = report['timestamp']
      version = report['ruby_version'].split('.')[0..1].join('.')

      puts 'Converting benchmark_report.json into RoadRunner compatible results.json'
      report['benchmark'].each do |service, data|
        rr_report['results'] << RoadRunner.convert_result(service, data, date, version)
      end
      rr_report['results'].flatten!

      puts 'Conversion complete, writing out report to: results.json'
      File.write('results.json', JSON.pretty_generate(rr_report))
    end

    def initialize_report_data
      report_data = {}
      report_data['productId'] = 'ruby3'
      begin
        report_data['commitId'] = `git rev-parse HEAD`.strip
      rescue StandardError
        # unable to get a commit, maybe run outside a git repo.  Skip
      end
      report_data['results'] = []
      report_data
    end

    def convert_result(service, data, date, version)
      results = []
      service_name = service.split('-')[-1]
      data.each do |key, value|
        next if key == 'gem_version'

        results << generate_result(service_name, key, value, date, version)
      end
      results
    end

    def generate_result(service_name, benchmark, measurements, date, version)
      result = {}
      result['name'] = "#{service_name}.#{generate_result_name(benchmark)}"
      result['description'] = generate_description(benchmark)
      result['unit'] = unit(benchmark)
      result['date'] = date
      result['dimensions'] = generate_dimensions(benchmark, version)
      result['measurements'] = measurements.is_a?(Array) ? measurements : [measurements]

      # RoadRunner currently doesn't support kilobyte units. Converting to megabytes instead.
      kb_to_mb(result)
    end

    def kb_to_mb(result)
      if result['unit'] == 'Kilobytes'
        result['unit'] = 'Megabytes'
        result['measurements'].each_with_index do |measurement, index|
          result['measurements'][index] = measurement / 1000.0
        end
      end
    end

    def generate_result_name(benchmark)
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

    def generate_description(benchmark)
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

    def unit(benchmark)
      if benchmark.include?('kb')
        'Kilobytes'
      elsif benchmark.include?('ms')
        'Milliseconds'
      end
    end

    def generate_dimensions(key, version)
      dimensions = [
        { name: 'RubyVersion', value: version }
      ]
      if key.include?('small')
        dimensions << { name: 'Size', value: 'Small' }
      elsif key.include?('large')
        dimensions << { name: 'Size', value: 'Large' }
      end
      dimensions
    end
  end
end
