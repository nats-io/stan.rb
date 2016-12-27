require 'stan/client'

sc = STAN::Client.new

# Borrow already established connection to NATS
nats = NATS::IO::Client.new
nats.connect(servers: ['nats://127.0.0.1:4222'])

sc.connect("test-cluster", "client-123", nats: nats)
20.times do |n|
  sc.publish("foo", "hello") do |guid, error|
    puts "Received ack with guid=#{guid}"
  end
end

# Subscribe with manual ack mode, and set AckWait to 60 seconds
sub_opts = {
  deliver_all_available: true,
  ack_wait: 60,  # seconds
  manual_acks: true
}
sc.subscribe("foo", sub_opts) do |msg|
  puts "Received a message (seq=#{msg.seq}): #{msg.data}, acking..."
  sc.ack(msg)
end

sc.close
