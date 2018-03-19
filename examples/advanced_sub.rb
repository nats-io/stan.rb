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
