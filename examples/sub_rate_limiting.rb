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
