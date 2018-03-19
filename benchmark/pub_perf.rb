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

require 'optparse'
require 'securerandom'

$:.unshift File.expand_path('../../lib', __FILE__)
require 'stan/client'

$count = 100000

$sub  = 'test'
$data_size = 16

$hash  = 2500

$cluster_name = 'test-cluster'

$client_id = SecureRandom.hex(5)

$stdout.sync = true

parser = OptionParser.new do |opts|
  opts.banner = "Usage: pub_perf [options]"

  opts.separator ""
  opts.separator "options:"

  opts.on("-id ID",     "Client ID to use on connect") { |client_id| $client_id = client_id }
  opts.on("-c CLUSTER", "Cluster name (default: #{$cluster_name}}") { |name| $cluster_name = name }
  opts.on("-n COUNT",   "Messages to send (default: #{$count}}") { |count| $count = count.to_i }
  opts.on("-s SIZE",    "Message size (default: #{$data_size})") { |size| $data_size = size.to_i }
  opts.on("-S SUBJECT", "Send subject (default: (#{$sub})")      { |sub| $sub = sub }
  opts.on("-b BATCH",   "Batch size (default: (#{$batch})")      { |batch| $batch = batch.to_i }
end

parser.parse(ARGV)

trap("TERM") { exit! }
trap("INT")  { exit! }

$data = Array.new($data_size) { "%01x" % rand(16) }.join('').freeze

stan = STAN::Client.new
stan.connect($cluster_name, $client_id, servers: ['nats://127.0.0.1:4222']) do
  $start   = Time.now
  $to_send = $count

  puts "Sending #{$count} messages of size #{$data.size} bytes on [#{$sub}]"

  loop do
    $to_send -= 1
    if $to_send > 0
      stan.publish($sub, $data)
    else
      stan.publish($sub, $data)

      elapsed = Time.now - $start
      mbytes = sprintf("%.1f", (($data_size*$count)/elapsed)/(1024*1024))
      puts "\nTest completed : #{($count/elapsed).ceil} sent msgs/sec (#{mbytes} MB/sec)\n"
      exit
    end
    printf('#') if $to_send.modulo($hash) == 0
  end
end
