# NATS Streaming Ruby Client

A [Ruby](http://ruby-lang.org) client for the [NATS Streaming](http://nats.io/documentation/streaming/nats-streaming-intro/) platform.

[![License MIT](https://img.shields.io/npm/l/express.svg)](http://opensource.org/licenses/MIT)[![Build Status](https://travis-ci.org/nats-io/ruby-nats-streaming.svg)](http://travis-ci.org/nats-io/ruby-nats-streaming)

## Getting Started

```bash
gem install nats-streaming
```

## Basic Usage

```ruby
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
```

### Subscription Start (i.e. Replay) Options

NATS Streaming subscriptions are similar to NATS subscriptions,
but clients may start their subscription at an earlier point in the
message stream, allowing them to receive messages that were published
before this client registered interest.

The options are described with examples below:

```ruby
# Subscribe starting with most recently published value
sc.subscribe("foo", start_at: :last_received) do |msg|
  puts "Received a message (start_at: :last_received, seq: #{msg.seq}): #{msg.data}"
end

# Receive all stored values in order
sc.subscribe("foo", deliver_all_available: true) do |msg|
  puts "Received a message (start_at: :deliver_all_available, seq: #{msg.seq}}): #{msg.data}"
end

# Receive messages starting at a specific sequence number
sc.subscribe("foo", start_at: :sequence, sequence: 3) do |msg|
  puts "Received a message (start_at: :sequence, seq: #{msg.seq}): #{msg.data}"
end

# Subscribe starting at a specific time by giving a unix timestamp
# with an optional nanoseconds fraction
sc.subscribe("foo", start_at: :time, time: Time.now.to_f - 3600) do |msg|
  puts "Received a message (start_at: :time, seq: #{msg.seq}): #{msg.data}"
end
```

### Durable subscriptions

Replay of messages offers great flexibility for clients wishing to begin processing
at some earlier point in the data stream. However, some clients just need to pick up where
they left off from an earlier session, without having to manually track their position
in the stream of messages.
Durable subscriptions allow clients to assign a durable name to a subscription when it is created.
Doing this causes the NATS Streaming server to track the last acknowledged message for that
`clientID + durable name`, so that only messages since the last acknowledged message
will be delivered to the client.

```
# Subscribe with durable name
sc.subscribe("foo", durable_name: "bar") do |msg|
  puts "Received a message (seq: #{msg.seq}): #{msg.data}"
end

# Client receives message sequence 1-40
1.upto(40) { |n| sc2.publish("foo", "hello-#{n}") }

# Disconnect from the server and reconnect...

# Messages sequence 41-80 are published...
41.upto(80).each { |n| sc2.publish("foo", "hello-#{n}") }

# Client reconnects with same clientID "client-123"
sc.connect("test-cluster", "client-123", nats: opts)

# Subscribe with same durable name picks up from seq 40
sc.subscribe("foo", durable_name: "bar") do |msg|
  puts "Received a message (seq: #{msg.seq}): #{msg.data}"
end
```

### Queue groups

All subscriptions with the same queue name (regardless of the
connection they originate from) will form a queue group. Each message
will be delivered to only one subscriber per queue group, using
queuing semantics. You can have as many queue groups as you wish.

Normal subscribers will continue to work as expected.

#### Creating a Queue Group

A queue group is automatically created when the first queue subscriber
is created. If the group already exists, the member is added to the
group.

```ruby
opts = { servers: ["nats://127.0.0.1:4222"] }

sc1 = STAN::Client.new
sc1.connect("test-cluster", "client-1", nats: opts)

sc2 = STAN::Client.new
sc2.connect("test-cluster", "client-2", nats: opts)

sc3 = STAN::Client.new
sc3.connect("test-cluster", "client-3", nats: opts)

group = [sc1, sc2, sc3]

group.each do |sc|
  # Subscribe to queue group named 'bar'
  sc.subscribe("foo", queue: "bar") do |msg|
    puts "[#{sc.client_id}] Received a message on queue subscription   (seq: #{msg.seq}): #{msg.data}"
  end

  # Notice that you can have a regular subscriber on that subject
  sc.subscribe("foo") do |msg|
    puts "[#{sc.client_id}] Received a message on regular subscription (seq: #{msg.seq}): #{msg.data}"
  end
end

# Clients receives message sequence 1-40 on regular subscription and
# messages become balanced too on the queue group subscription
1.upto(40) { |n| sc2.publish("foo", "hello-#{n}") }

# When the last member leaves the group, that queue group is removed
group.each do |sc|
  sc.close
end
```

### Durable Queue Group

A durable queue group allows you to have all members leave but still maintain state. When a member re-joins,
it starts at the last position in that group.

#### Creating a Durable Queue Group

A durable queue group is created in a similar manner as that of a
standard queue group, except the `:durable_name` option must be used to
specify durability.

```ruby
# Subscribe to queue group named 'bar'
sc.subscribe("foo", queue: "bar", durable_name: "durable") do |msg|
  puts "[#{sc.client_id}] Received a message on durable queue subscription (seq: #{msg.seq}): #{msg.data}"
end
```

A group called `dur:bar` (the concatenation of durable name and group name) is created in the server.
This means two things:

- The character `:` is not allowed for a queue subscriber's durable name.

- Durable and non-durable queue groups with the same name can coexist.

## Advanced Usage

### Asynchronous Publishing

Advanced users may wish to process these publish acknowledgements
manually to achieve higher publish throughput by not waiting on
individual acknowledgements during the publish operation, this can
be enabled by passing a block to `publish`:

```ruby
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
```

### Message Acknowledgements and Redelivery

NATS Streaming offers At-Least-Once delivery semantics, meaning that
once a message has been delivered to an eligible subscriber, if an
acknowledgement is not received within the configured timeout
interval, NATS Streaming will attempt redelivery of the message.

This timeout interval is specified by the subscription option `:ack_wait`,
which defaults to 30 seconds.

By default, messages are automatically acknowledged by the NATS
Streaming client library after the subscriber's message handler is
invoked. However, there may be cases in which the subscribing client
wishes to accelerate or defer acknowledgement of the message. To do
this, the client must set manual acknowledgement mode on the
subscription, and invoke `ack` on the received message:

```ruby
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
```

## Rate limiting/matching

A classic problem of publish-subscribe messaging is matching the rate of message
producers with the rate of message consumers. Message producers can often outpace
the speed of the subscribers that are consuming their messages. This mismatch is
commonly called a "fast producer/slow consumer" problem, and may result in dramatic
resource utilization spikes in the underlying messaging system as it tries to
buffer messages until the slow consumer(s) can catch up.

### Publisher rate limiting

NATS Streaming provides a connection option called `:max_pub_acks_inflight`
that effectively limits the number of unacknowledged messages that a
publisher may have in-flight at any given time.  When this maximum is
reached, further `publish` calls will block until the number of
unacknowledged messages falls below the specified limit.

```ruby
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
```

### Subscriber rate limiting

Rate limiting may also be accomplished on the subscriber side, on a
per-subscription basis, using a subscription option called `:max_inflight`.
This option specifies the maximum number of outstanding
acknowledgements (messages that have been delivered but not
acknowledged) that NATS Streaming will allow for a given
subscription.  When this limit is reached, NATS Streaming will suspend
delivery of messages to this subscription until the number of
unacknowledged messages falls below the specified limit.

```ruby
# Subscribe with manual ack mode and a max in-flight limit of 25
sc.subscribe("foo", max_inflight: 25, manual_acks: true) do |msg|
  puts "Received message with seq=#{msg.seq}"

  # Manually ack the message
  sc.ack(msg)
end

8192.times do |n|
  sc.publish("foo", "Hello World")
end
```

## License

(The MIT License)

Copyright (c) 2016 Apcera Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
