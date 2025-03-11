# frozen_string_literal: true

require_relative '../result'

module Benchmark
  # Abstract base class for benchmarking an SDK Gem.
  # Implementors must define the `gem_name`, `client_klass`, and the
  # `operation_benchmarks` methods.
  # rubocop:disable Metrics/ClassLength
  class Gem
    # Return all subclasses of this class.
    def self.descendants
      descendants = []
      ObjectSpace.each_object(singleton_class) do |k|
        next if k.singleton_class?

        descendants.unshift k unless k == self
      end
      descendants
    end

    # The name of the gem (eg: aws-sdk-s3).
    def gem_name; end

    def service_name(gem_name)
      gem_name.split('-').last
    end

    # The name of the gem directory (eg: gems/aws-sdk-s3).
    def gem_dir; end

    # The module that contains the client (eg Aws::S3).
    def client_module_name; end

    # Return a hash with definitions for operation benchmarks to run.
    # The key should be the name of the test (reported as the metric name).
    # Values should be a hash with keys:
    #   setup (proc), test (proc) and n (optional, integer)
    #
    # setup: Must be a proc that takes a client. Client will be pre initialized.
    # Setup may initialize stubs (eg `client.stub_responses(:operation, [...])`)
    # Setup MUST also return a hash with the request used in the test.
    # This avoids the cost of creating the argument in each run of the test.
    #
    # test: a proc that takes a client and request (generated from setup proc)
    def operation_benchmarks; end

    # Build the gem from its gemspec, then get the file size on disk.
    # Done within a temp directory to prevent accumulation of .gem artifacts.
    def benchmark_gem_size(legacy_report_data, report_data)
      Dir.mktmpdir('benchmark-gem-size') do |tmpdir|
        Dir.chdir(gem_dir) do
          `gem build #{gem_name}.gemspec -o #{tmpdir}/#{gem_name}.gem`
          legacy_report_data['gem_size_kb'] =
            File.size("#{tmpdir}/#{gem_name}.gem") / 1024.0
          legacy_report_data['gem_version'] = File.read('VERSION').strip

          report_data << Result.new(
            "#{service_name(gem_name)}.gem.size",
            "The size of the #{gem_name} gem.",
            [File.size("#{tmpdir}/#{gem_name}.gem") / (1024.0 * 1024.0)]
          ).format
        end
      end
    end

    # Benchmark requiring a gem - runs in a forked process (when supported)
    # to ensure state of parent process is not modified by the require.
    # For accurate results, should be run before any SDK gems are required
    # in the parent process.
    # rubocop:disable Metrics/MethodLength
    def benchmark_require(legacy_report_data, report_data)
      return unless gem_name

      time = Benchmark.fork_run do |out|
        t1 = Benchmark.monotonic_milliseconds
        require gem_name
        out[:require_time] = (Benchmark.monotonic_milliseconds - t1)
      end

      memory = Benchmark.fork_run do |out|
        unless defined?(JRUBY_VERSION)
          r = ::MemoryProfiler.report { require gem_name }
          out[:require_mem_retained] = r.total_retained_memsize / (1024.0 * 1024.0)
          out[:require_mem_allocated] = r.total_allocated_memsize / (1024.0 * 1024.0)
        end
      end

      legacy_report_data.merge!(time)
      legacy_report_data.merge!(memory)

      report_data << Result.new(
        "#{service_name(gem_name)}.require.time",
        "The time it takes to require the #{gem_name} gem.",
        [time[:require_time]]
      ).format

      report_data << Result.new(
        "#{service_name(gem_name)}.require.retained.size",
        "The amount of memory retained when requiring the #{gem_name} gem.",
        [memory[:require_mem_retained]]
      ).format

      report_data << Result.new(
        "#{service_name(gem_name)}.require.allocated.size",
        "The amount of memory allocated when requiring the #{gem_name} gem.",
        [memory[:require_mem_allocated]]
      ).format
    end
    # rubocop:enable Metrics/MethodLength

    # Benchmark creating a client - runs in a forked process (when supported)
    # to ensure state of parent process is not modified by the require.
    # For accurate results, should be run before the client is initialized
    # in the parent process to ensure cache is clean.
    def benchmark_client(legacy_report_data, report_data)
      return unless client_module_name

      memory = Benchmark.fork_run do |out|
        require gem_name
        client_klass = Kernel.const_get(client_module_name).const_get(:Client)
        unless defined?(JRUBY_VERSION)
          r = ::MemoryProfiler.report { client_klass.new(stub_responses: true) }
          out[:client_mem_retained] = r.total_retained_memsize / (1024.0 * 1024.0)
          out[:client_mem_allocated] = r.total_allocated_memsize / (1024.0 * 1024.0)
        end
      end

      legacy_report_data.merge!(memory)

      report_data << Result.new(
        "#{service_name(gem_name)}.client.retained.size",
        "The amount of memory retained when creating the #{service_name(gem_name)} client.",
        [memory[:client_mem_retained]]
      ).format

      report_data << Result.new(
        "#{service_name(gem_name)}.client.allocated.size",
        "The amount of memory allocated when creating the #{service_name(gem_name)} client.",
        [memory[:client_mem_allocated]]
      ).format
    end

    # This runs in the main process and requires service gems.
    # It MUST be done after ALL testing of gem loads/client creates.
    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
    def benchmark_operations(legacy_report_data, report_data)
      require_relative 'test_data'
      return unless gem_name && client_module_name && operation_benchmarks

      require gem_name

      client_klass = Kernel.const_get(client_module_name).const_get(:Client)

      legacy_report_data[:client_init_ms] = Benchmark.measure_time(300) do
        client_klass.new(stub_responses: true)
      end

      report_data << Result.new(
        "#{service_name(gem_name)}.client.init.time",
        "The time it takes to initialize the #{service_name(gem_name)} client.",
        legacy_report_data[:client_init_ms]
      ).format

      values = legacy_report_data[:client_init_ms]
      ms = format('%.2f', (values.sum(0.0) / values.size))
      puts "\t\t#{gem_name} client init avg: #{ms} ms"

      # rubocop:disable Metrics/BlockLength
      operation_benchmarks.each do |test_name, test_def|
        client = client_klass.new(stub_responses: true)
        req = test_def[:setup].call(client)

        op_name = test_name.to_s.split('_').join
        op_name_pascal = test_name.to_s.split('_').map(&:capitalize).join

        # warmup (run a few iterations without measurement)
        2.times { test_def[:test].call(client, req) }

        mem_allocated = 0
        unless defined?(JRUBY_VERSION)
          r = ::MemoryProfiler.report { test_def[:test].call(client, req) }
          mem_allocated = legacy_report_data["#{test_name}_allocated_kb"] =
            r.total_allocated_memsize / 1024.0

          report_data << Result.new(
            "#{service_name(gem_name)}.#{op_name}.allocated.size",
            'The amount of memory allocated to perform the ' \
            "#{op_name_pascal} operation.",
            [mem_allocated / 1024.0]
          ).format
        end

        n = test_def[:n] || 300
        values = Benchmark.measure_time(n) do
          test_def[:test].call(client, req)
        end
        legacy_report_data["#{test_name}_ms"] = values

        report_data << Result.new(
          "#{service_name(gem_name)}.#{op_name}.time",
          "The time it takes to perform the #{op_name_pascal} operation.",
          values
        ).format

        ms = format('%.2f', (values.sum(0.0) / values.size))
        puts "\t\t#{test_name} avg: #{ms} ms\t" \
             "mem_allocated: #{format('%.2f', mem_allocated)} kb"
      end
      # rubocop:enable Metrics/BlockLength
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
  end
  # rubocop:enable Metrics/ClassLength
end
