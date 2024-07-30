# frozen_string_literal: true

# Used to determine the bucket to store the benchmark results in S3.
def benchmark_bucket
  case ENV.fetch('GH_REPO', nil)
  when 'aws/aws-sdk-ruby'
    'aws-sdk-ruby-v3-benchmarks'
  when 'aws/aws-sdk-ruby-staging'
    'aws-sdk-ruby-staging-v3-benchmarks'
  when 'smithy-lang/smithy-ruby'
    'hearth-benchmarks'
  when 'alextwoods/aws-sdk-ruby-v4' # temporary
    'aws-sdk-ruby-v4-benchmarks'
  else
    raise 'Unknown repository'
  end
end

# Used to determine the key to store the benchmark results in S3.
def benchmark_key
  folder = event_type
  folder += "/#{ENV.fetch('GH_REF', nil)}" if event_type != 'release'
  time = Time.now.strftime('%Y-%m-%d')
  "#{folder}/#{time}/benchmark_#{SecureRandom.uuid}.json"
end

# Used to determine the event type for the metric.
def event_type
  if ENV.fetch('GH_EVENT', nil) == 'pull_request'
    if ENV.fetch('GH_REPO', nil) == 'aws/aws-sdk-ruby-staging'
      'staging-pr'
    else
      'pr'
    end
  else
    'release'
  end
end
