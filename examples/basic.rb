require 'stan/client'

sc = STAN::Client.new

# Customize connection to NATS
opts = { servers: ["nats://127.0.0.1:4222"] }
sc.connect("test-cluster", "client-123", nats: opts)

# Simple async subscriber
sub = sc.subscribe("foo", start_at: :first) do |msg|
  puts "Received a message (seq=#{msg.seq}): #{msg.data}"
end

# Synchronous Publisher, does not return until an ack
# has been received from NATS Streaming.
sc.publish("foo", "hello world")

# Publish asynchronously by giving a block
sc.publish("foo", "hello again") do |guid|
  puts "Received ack with guid=#{guid}"
end

# Unsubscribe
sub.unsubscribe

# Close connection
sc.close
