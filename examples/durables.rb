require 'stan/client'

opts = { servers: ["nats://127.0.0.1:4222"] }

sc = STAN::Client.new
sc.connect("test-cluster", "client-123", nats: opts)

sc2 = STAN::Client.new
sc2.connect("test-cluster", "client-456", nats: opts)

# Subscribe with durable name
sc.subscribe("foo", durable_name: "bar") do |msg|
  puts "Received a message (seq: #{msg.seq}): #{msg.data}"
end

# Client receives message sequence 1-40
1.upto(40) { |n| sc2.publish("foo", "hello-#{n}") }

# Disconnect from the server and reconnect
sc.close
sc = STAN::Client.new

# Messages sequence 41-80 are published...
41.upto(80).each { |n| sc2.publish("foo", "hello-#{n}") }

# Client reconnects with same clientID "client-123"
sc.connect("test-cluster", "client-123", nats: opts)

# Subscribe with same durable name picks up from seq 40
sc.subscribe("foo", durable_name: "bar") do |msg|
  puts "Received a message (seq: #{msg.seq}): #{msg.data}"
end

sc.close
sc2.close
