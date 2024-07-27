# frozen_string_literal: true

# Used to determine what folder to store the benchmark results in
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
