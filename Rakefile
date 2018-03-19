#!/usr/bin/env rake
# Copyright 2017-2018 The NATS Authors
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

require 'rspec/core'
require 'rspec/core/rake_task'

desc 'Run specs from client'
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
  spec.rspec_opts = ["--format", "documentation", "--colour", "--profile"]
end

task :default => :spec

desc 'Prepare the protocol buffer payloads'
task 'protobuf:compile' do
  system("protoc --ruby_out=lib/stan pb/protocol.proto")
  system("mv lib/stan/pb/protocol_pb.rb lib/stan/pb/protocol.pb.rb")
end
