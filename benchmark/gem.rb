# frozen_string_literal: true

module Benchmark
  # Abstract base class for benchmarking an SDK Gem.
  # Implementors must define the `gem_name`, `client_klass`, and the
  # `operation_benchmarks` methods.
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
    def benchmark_gem_size(report_data)
      Dir.mktmpdir('benchmark-gem-size') do |tmpdir|
        Dir.chdir(gem_dir) do
          `gem build #{gem_name}.gemspec -o #{tmpdir}/#{gem_name}.gem`
          report_data['gem_size_kb'] =
            File.size("#{tmpdir}/#{gem_name}.gem") / 1024.0
          report_data['gem_version'] = File.read('VERSION').strip
        end
      end
    end

    # Benchmark requiring a gem - runs in a forked process (when supported)
    # to ensure state of parent process is not modified by the require.
    # For accurate results, should be run before any SDK gems are required
    # in the parent process.
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def benchmark_require(report_data)
      return unless gem_name

      report_data.merge!(Benchmark.fork_run do |out|
        t1 = Benchmark.monotonic_milliseconds
        require gem_name
        out[:require_time_ms] = (Benchmark.monotonic_milliseconds - t1)
      end)

      report_data.merge!(Benchmark.fork_run do |out|
        unless defined?(JRUBY_VERSION)
          r = ::MemoryProfiler.report { require gem_name }
          out[:require_mem_retained_kb] = r.total_retained_memsize / 1024.0
          out[:require_mem_allocated_kb] = r.total_allocated_memsize / 1024.0
        end
      end)
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    # Benchmark creating a client - runs in a forked process (when supported)
    # to ensure state of parent process is not modified by the require.
    # For accurate results, should be run before the client is initialized
    # in the parent process to ensure cache is clean.
    def benchmark_client(report_data)
      return unless client_module_name

      report_data.merge!(Benchmark.fork_run do |out|
        require gem_name
        client_klass = Kernel.const_get(client_module_name).const_get(:Client)
        unless defined?(JRUBY_VERSION)
          r = ::MemoryProfiler.report { client_klass.new(stub_responses: true) }
          out[:client_mem_retained_kb] = r.total_retained_memsize / 1024.0
          out[:client_mem_allocated_kb] = r.total_allocated_memsize / 1024.0
        end
      end)
    end

    # This runs in the main process and requires service gems.
    # It MUST be done after ALL testing of gem loads/client creates.
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def benchmark_operations(report_data)
      require_relative 'test_data'
      return unless gem_name && client_module_name && operation_benchmarks

      require gem_name

      client_klass = Kernel.const_get(client_module_name).const_get(:Client)

      report_data[:client_init_ms] = Benchmark.measure_time(300) do
        client_klass.new(stub_responses: true)
      end

      values = report_data[:client_init_ms]
      ms = format('%.2f', (values.sum(0.0) / values.size))
      puts "\t\t#{gem_name} client init avg: #{ms} ms"

      operation_benchmarks.each do |test_name, test_def|
        client = client_klass.new(stub_responses: true)
        req = test_def[:setup].call(client)

        # warmup (run a few iterations without measurement)
        2.times { test_def[:test].call(client, req) }

        mem_allocated = 0
        unless defined?(JRUBY_VERSION)
          r = ::MemoryProfiler.report { test_def[:test].call(client, req) }
          mem_allocated = report_data["#{test_name}_allocated_kb"] =
            r.total_allocated_memsize / 1024.0
        end

        n = test_def[:n] || 300
        values = Benchmark.measure_time(n) do
          test_def[:test].call(client, req)
        end
        report_data["#{test_name}_ms"] = values
        ms = format('%.2f', (values.sum(0.0) / values.size))
        puts "\t\t#{test_name} avg: #{ms} ms\t" \
             "mem_allocated: #{format('%.2f', mem_allocated)} kb"
      end
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength
  end
end
