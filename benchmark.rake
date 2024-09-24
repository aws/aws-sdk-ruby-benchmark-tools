# frozen_string_literal: true

require_relative 'benchmark_utils'

namespace :benchmark do
  desc 'Runs a performance benchmark'
  task :run do
    puts 'TASK START: benchmark:run'

    require 'json'
    require 'memory_profiler' # MemoryProfiler does not work for JRuby
    require 'tmpdir'
    # rubocop:disable Lint/RequireRelativeSelfPath
    require_relative 'benchmark'
    # rubocop:enable Lint/RequireRelativeSelfPath

    # Require all benchmark gems
    Dir[File.join(__dir__, '..', 'gems', '*.rb')]
      .sort.each { |file| require file }

    report_data = Benchmark.initialize_report_data
    benchmark_data = report_data['benchmark']

    puts 'Benchmarking gem size/requires/client initialization'
    Dir.mktmpdir('benchmark-run') do |_tmpdir|
      Benchmark::Gem.descendants.each do |benchmark_gem_klass|
        benchmark_gem = benchmark_gem_klass.new
        puts "\tBenchmarking #{benchmark_gem.gem_name}"
        gem_data = benchmark_data[benchmark_gem.gem_name] ||= {}
        benchmark_gem.benchmark_gem_size(gem_data)
        benchmark_gem.benchmark_require(gem_data)
        benchmark_gem.benchmark_client(gem_data)
      end
    end
    puts 'Done benchmarking gem size/requires/client initialization'
    puts "\n"

    # Benchmarking operations needs to be done after all require/client init
    # tests have been done. This ensures that no gem requires/cache state is in
    # process memory for those tests.
    puts 'Benchmarking operations'
    Benchmark::Gem.descendants.each do |benchmark_gem_klass|
      benchmark_gem = benchmark_gem_klass.new
      puts "\tBenchmarking #{benchmark_gem.gem_name}"
      benchmark_gem.benchmark_operations(benchmark_data[benchmark_gem.gem_name])
    end
    puts 'Done benchmarking operations'
    puts "\n"

    puts 'Benchmarking complete, writing out report to: benchmark_report.json'
    File.write('benchmark_report.json', JSON.pretty_generate(report_data))

    puts 'TASK END: benchmark:run'
  end

  desc 'Uploads the benchmark report'
  task 'upload-report' do
    puts 'TASK START: benchmark:upload-report'

    require 'aws-sdk-s3'
    require 'securerandom'

    bucket = benchmark_bucket
    key = benchmark_key
    puts "Uploading report to: #{bucket}/#{key}"
    client = Aws::S3::Client.new
    client.put_object(
      bucket: bucket,
      key: key,
      body: File.read('benchmark_report.json')
    )
    puts 'Upload complete'

    puts 'TASK END: benchmark:upload-report'
  end

  desc 'Puts benchmarking data into CloudWatch'
  task 'put-metrics' do
    puts 'TASK START: benchmark:put-metrics'

    require 'aws-sdk-cloudwatch'
    require_relative 'benchmark/metrics'

    report = JSON.parse(File.read('benchmark_report.json'))
    ruby_version = report['ruby_version'].split('.').first(2).join('.')
    target = "#{report['ruby_engine']}-#{ruby_version}"

    # common dimensions
    report_dims = {
      event: event_type,
      target: target,
      os: report['os'],
      cpu: report['cpu'],
      env: report['execution_env']
    }

    puts 'Uploading benchmarking metrics'
    client = Aws::CloudWatch::Client.new
    report['benchmark'].each do |gem_name, gem_data|
      gem_data.each do |metric_name, metric_value|
        Benchmark::Metrics.put_metric(
          client: client,
          dims: report_dims.merge(gem: gem_name),
          timestamp: report['timestamp'] || Time.now,
          metric_name: metric_name,
          metric_value: metric_value
        )
      end
    end
    puts 'Benchmarking metrics uploaded'

    puts 'TASK END: benchmark:put-metrics'
  end

  task 'check-regressions' do
    puts 'TASK START: benchmark:check-regressions'

    require 'aws-sdk-lambda'
    require_relative 'benchmark/metrics'

    client = Aws::Lambda::Client.new
    report = JSON.parse(File.read('benchmark_report.json'))
    payload = {
      metric_namespace: Benchmark::Metrics.metric_namespace,
      report: report
    }
    resp = client.invoke(
      function_name: 'DetectSDKPerformanceRegressions',
      payload: JSON.dump(payload)
    )
    output = JSON.parse(resp.payload.read)
    regressions = JSON.parse(output['body'])
    if regressions.size.positive?
      message = "Detected #{regressions.size} possible performance regressions:\n"
      regressions.each do |metric, data|
        message += "* #{metric} - #{data}\n"
      end
      puts message
      github_output = ENV.fetch('GITHUB_OUTPUT')
      if github_output && File.exist?(github_output)
        puts 'Setting step output'
        output = "message<<EOF\n#{message}\nEOF\n"
        File.write(github_output, output, mode: 'a+')
      end
    end

    puts 'TASK END: benchmark:put-metrics'
  end
end
