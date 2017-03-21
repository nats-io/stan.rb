require File.expand_path('../lib/stan/version', __FILE__)

spec = Gem::Specification.new do |s|
  s.name = 'nats-streaming'
  s.version = STAN::VERSION
  s.summary = 'Ruby client for the NATS Streaming messaging system.'
  s.homepage = 'https://nats.io'
  s.description = 'Ruby client for the NATS Streaming messaging system.'
  s.licenses = ['MIT']
  s.has_rdoc = false

  s.authors = ['Waldemar Quevedo']
  s.email = ['wally@apcera.com']

  s.require_paths = ['lib']

  s.files = %w[
    lib/stan/pb/protocol.pb.rb
    lib/stan/client.rb
    lib/stan/version.rb
  ]

  s.add_runtime_dependency('nats-pure', '~> 0')
  s.add_runtime_dependency('google-protobuf', '~> 3')
end
