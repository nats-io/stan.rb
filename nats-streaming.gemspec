# Copyright 2017-2019 The NATS Authors
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require File.expand_path('../lib/stan/version', __FILE__)

spec = Gem::Specification.new do |s|
  s.name = 'nats-streaming'
  s.version = STAN::VERSION
  s.summary = 'Ruby client for the NATS Streaming messaging system.'
  s.homepage = 'https://nats.io'
  s.description = 'Ruby client for the NATS Streaming messaging system.'
  s.licenses = ['MIT']

  s.authors = ['Waldemar Quevedo']
  s.email = ['wally@synadia.com']

  s.require_paths = ['lib']

  s.files = %w[
    lib/stan/pb/protocol.pb.rb
    lib/stan/client.rb
    lib/stan/version.rb
  ]

  s.add_runtime_dependency('nats-pure', '~> 0')
  s.add_runtime_dependency('google-protobuf', '~> 3')
end
