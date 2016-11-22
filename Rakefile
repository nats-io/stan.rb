#!/usr/bin/env rake
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
