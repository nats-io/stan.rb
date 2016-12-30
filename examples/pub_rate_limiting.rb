require 'stan/client'

sc = STAN::Client.new
opts = { servers: ["nats://127.0.0.1:4222"] }

# Customize max number of inflight acks to be processed
sc.connect("test-cluster", "client-123", max_pub_acks_inflight: 1024, nats: opts)

8192.times do |n|
  # If the server is unable to keep up with the publisher, the number of oustanding
  # acks will eventually reach the max and this call will block
  start_time = Time.now

  # Publish asynchronously by giving a block
  sc.publish("foo", "Hello World") do |guid|
    end_time = Time.now
    puts "Received ack ##{n} with guid=#{guid} in #{end_time - start_time}"
  end
end

sc.close
