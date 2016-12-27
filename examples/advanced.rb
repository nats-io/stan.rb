require 'stan/client'

stan = STAN::Client.new

# Borrow already established connection to NATS
nats = NATS::IO::Client.new
nats.connect(servers: ['nats://127.0.0.1:4222'])

# Given a block it will unplug from NATS Streaming Server on block exit.
stan.connect("test-cluster", "client-456", nats: nats) do |sc|
  # Publish asynchronously by giving a block
  sc.publish("foo", "hello again") do |guid, error|
    puts "Received ack with guid=#{guid}"
  end

  sc.subscribe("foo", start_at: :first) do |msg|
    puts "Received a message (seq=#{msg.seq}): #{msg.data}"
  end
end
