require 'stan/client'

sc = STAN::Client.new
opts = { servers: ["nats://127.0.0.1:4222"] }
sc.connect("test-cluster", "client-123", nats: opts)

# Subscribe with manual ack mode and a max in-flight limit of 25
sc.subscribe("foo", max_inflight: 25, manual_acks: true) do |msg|
  puts "Received message with seq=#{msg.seq}"

  # Manually ack the message
  sc.ack(msg)
end

8192.times do |n|
  sc.publish("foo", "Hello World")
end

sc.close
