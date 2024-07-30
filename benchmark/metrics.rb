# frozen_string_literal: true

module Benchmark
  # Namespace for putting metrics into CloudWatch.
  module Metrics
    # Put metrics into CloudWatch.
    def self.put_metric(client:, dims:, timestamp:, metric_name:, metric_value:)
      return unless metric_value.is_a?(Numeric) || metric_value.is_a?(Array)

      metric_data = {
        metric_name: metric_name,
        timestamp: timestamp,
        unit: metric_unit(metric_name),
        dimensions: dims.map { |k, v| { name: k.to_s, value: v } }
      }

      case metric_value
      when Numeric
        metric_data[:value] = metric_value
        client.put_metric_data(
          namespace: metric_namespace,
          metric_data: [metric_data]
        )
      when Array
        # CloudWatch has a limit of 150 values
        metric_value.each_slice(150) do |values|
          metric_data[:values] = values
          client.put_metric_data(
            namespace: metric_namespace,
            metric_data: [metric_data]
          )
        end
      else
        raise 'Unknown type for metric value'
      end
    end

    class << self
      private

      def metric_unit(metric_name)
        unit_suffix = metric_name.split('_').last
        {
          'kb' => 'Kilobytes',
          'b' => 'Bytes',
          's' => 'Seconds',
          'ms' => 'Milliseconds'
        }.fetch(unit_suffix, 'None')
      end

      def metric_namespace
        case ENV.fetch('GH_REPO', nil)
        when 'aws/aws-sdk-ruby'
          'aws-sdk-ruby-v3-performance'
        when 'aws/aws-sdk-ruby-staging'
          'aws-sdk-ruby-v3-staging-performance'
        when 'smithy-lang/smithy-ruby'
          'hearth-performance'
        when 'alextwoods/aws-sdk-ruby-v4' # temporary
          'aws-sdk-ruby-v4-performance'
        else
          raise 'Unknown repository'
        end
      end
    end
  end
end
