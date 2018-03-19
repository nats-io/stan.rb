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
