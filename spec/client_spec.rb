require 'spec_helper'
require 'securerandom'
require 'monitor'

describe 'Client - Specification' do

  it 'should connect and close on block exit' do
    msgs = []
    msgs.extend(MonitorMixin)

    nc = NATS::IO::Client.new
    nc.connect(:servers => ['nats://127.0.0.1:4222'])

    # Borrow the connection to NATS, meaning that we will
    # not be owning the connection.
    stan = STAN::Client.new(nc)

    # Discover cluster and send a message, and if block given
    # then we disconnect on exit.
    client_id = "client-#{SecureRandom.hex(5)}"
    stan.connect("test-cluster", client_id) do |sc|
      future = msgs.new_cond
      
      sc.subscribe("hello") do |msg|
        # Message has been received
      end

      sc.publish("hello", "world") do
        # Message has been published

        # Though should be received ack
      end
    end
  end

  it 'should connect to NATS if not borrowing connection and disconnect on block exit' do
    stan = STAN::Client.new
    stan.connect("test-cluster", "client-123", :nats => {
        :servers => ["nats://127.0.0.1:4222"]
      }) do |sc|
      sc.subscribe("hello") do |msg|
        # Message has been received
      end

      sc.publish("hello", "world") do
        # Message has been published and acked
      end
    end
  end
end
