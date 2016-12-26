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

stan = STAN::Client.new

# Customize connection to NATS
opts = { servers: ["nats://127.0.0.1:4222"] }
stan.connect("test-cluster", "client-123", nats: opts) do |sc|

  # Synchronous Publisher, does not return until an ack
  # has been received from NATS Streaming.
  sc.publish("foo", "hello world")

  # Publish asynchronously by giving a block
  sc.publish("foo", "hello again") do |guid, error|
    puts "Received ack with guid=#{guid}"
  end

  sc.subscribe("foo", start_at: :first) do |msg|
    puts "Received a message (seq=#{msg.seq}): #{msg.data}"
  end
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
