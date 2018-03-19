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

$expected = $count = 100_000

$sub  = 'test'
$data_size = 16

$hash  = 1000

$batch = 10_000.0

$cluster_name = 'test-cluster'

$client_id = SecureRandom.hex(5)

$replay = false

$stdout.sync = true

parser = OptionParser.new do |opts|
  opts.banner = "Usage: sub_perf [options]"

  opts.separator ""
  opts.separator "options:"

  opts.on("-id ID",     "Client ID to use on connect") { |client_id| $client_id = client_id }
  opts.on("-c CLUSTER", "Cluster name (default: #{$cluster_name}}") { |name| $cluster_name = name }
  opts.on("-n COUNT",   "Messages to send (default: #{$count}}") { |count| $expected = $count = count.to_i }
  opts.on("-r",         "Replay messages  (default: false}")     { |_| $replay = true }
  opts.on("-s SIZE",    "Message size (default: #{$data_size})") { |size| $data_size = size.to_i }
  opts.on("-S SUBJECT", "Send subject (default: (#{$sub})")      { |sub| $sub = sub }
  opts.on("-b BATCH",   "Batch size   (default: (#{$batch})")    { |batch| $batch = batch.to_i }
end

parser.parse(ARGV)

trap("TERM") { exit! }
trap("INT")  { exit! }

$data = Array.new($data_size) { "%01x" % rand(16) }.join('').freeze

stan = STAN::Client.new
done = stan.new_cond
received = 1
stan.connect($cluster_name, $client_id, servers: ['nats://127.0.0.1:4222']) do |sc|
  puts "Waiting for #{$expected} messages on [#{$sub}]"

  # Publish all the messages and have them be replayed
  # to the subscriber from the beginning.
  if $replay
    threads = []
    n = ($count / $batch)
    start_time = Time.now
    1.upto(n) do
      threads << Thread.new do
        1.upto($batch).each do |c|
          sc.publish($sub, $data)
          printf('#') if c.modulo($batch/10) == 0
        end
      end
    end
    threads.each {|t| t.join }
    end_time = Time.now
    elapsed = end_time - start_time
    mbytes = sprintf("%.1f", (($data_size*$count)/elapsed)/(1024*1024))
    puts "\nPublished #{($count/elapsed).ceil} msgs/sec (#{mbytes} MB/sec) using #{threads.count} threads (batch=#{$batch})\n"
  end

  sc.subscribe($sub, start_at: :first) do |msg|
    ($start = Time.now and puts "Started Receiving!") if (received == 1)
    if ((received += 1) == $expected)
      puts "\nTest completed : #{($expected/(Time.now-$start)).ceil} msgs/sec.\n"
      stan.synchronize do
        done.signal
      end
    end
    printf('+') if received.modulo($hash) == 0
  end

  stan.synchronize do
    done.wait
  end
end
