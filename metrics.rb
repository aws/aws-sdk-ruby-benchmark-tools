# frozen_string_literal: true

module Benchmark
  module Metrics
    # Put metrics into CloudWatch
    def put_metric(client:, dims:, timestamp:, metric_name:, metric_value:)
      return unless metric_value.is_a?(Numeric) || metric_value.is_a?(Array)

      # Attempt to determine unit
      unit_suffix = metric_name.split('_').last
      unit = {
        'kb' => 'Kilobytes',
        'b' => 'Bytes',
        's' => 'Seconds',
        'ms' => 'Milliseconds'
      }.fetch(unit_suffix, 'None')

      metric_data = {
        metric_name: metric_name,
        timestamp: timestamp,
        unit: unit,
        dimensions: dims.map { |k, v| { name: k.to_s, value: v } }
      }

      namespace =
        case ENV.fetch('GH_REPO', nil)
        when 'smithy-lang/smithy-ruby'
          'hearth-performance'
        when 'aws/aws-sdk-ruby'
          'aws-sdk-ruby-v3-performance'
        else
          raise 'Unknown repository'
        end

      case metric_value
      when Numeric
        metric_data[:value] = metric_value
        client.put_metric_data(namespace:, metric_data: [metric_data])
      when Array
        # cloudwatch has a limit of 150 values
        metric_value.each_slice(150) do |values|
          metric_data[:values] = values
          client.put_metric_data(namespace:, metric_data: [metric_data])
        end
      else
        raise 'Unknown type for metric value'
      end
    end
  end
end
