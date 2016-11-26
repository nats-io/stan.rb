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
done = stan.new_cond
options = {
  nats: { servers: ['nats://127.0.0.1:4222'] },
  max_pub_acks_inflight: 16384
}
stan.connect($cluster_name, $client_id, options) do
  $start   = Time.now
  $to_send = $count

  puts "Sending #{$count} messages of size #{$data.size} bytes on [#{$sub}]"

  acks = 0
  loop do
    $to_send -= 1
    if $to_send > 0
      stan.publish($sub, $data) do |ack|
        stan.synchronize do
          acks += 1
          done.signal if acks == $count
        end
      end
    else
      stan.publish($sub, $data) do |ack|
        stan.synchronize do
          acks += 1
          done.signal if acks == $count
        end
      end
      stan.synchronize do
        done.wait
      end

      elapsed = Time.now - $start
      mbytes = sprintf("%.1f", (($data_size*$count)/elapsed)/(1024*1024))
      puts "\nTest completed : #{($count/elapsed).ceil} sent msgs/sec (#{mbytes} MB/sec)\n"
      exit
    end
    printf('#') if $to_send.modulo($hash) == 0
  end
end
