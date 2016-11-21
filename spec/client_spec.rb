require 'spec_helper'
require 'securerandom'

describe 'Client - Specification' do

  it 'should connect and close on block exit' do
    msgs = []

    nc = NATS::IO::Client.new
    nc.connect(:servers => ['nats://127.0.0.1:4222'])

    # Borrow the connection to NATS, meaning that we will
    # not be owning the connection.
    stan = STAN::Client.new

    # Discover cluster and send a message, and if block given
    # then we disconnect on exit.
    client_id = "client-#{SecureRandom.hex(5)}"
    acks = []
    msgs = []
    stan.connect("test-cluster", client_id, nats: nc) do |sc|

      sc.subscribe("hello") do |result, err|
        # Message has been received
      end

      10.times do |n|
        sc.publish("hello", "world-#{n}") do |guid, error|
          # Message has been published and acked at this point
          acks << guid
          expect(error).to be_nil
        end
      end

      # Synchronously receives the result or raises
      # an exception in case there was an error
      ack = sc.publish("hello", "again", timeout: 1)
      acks << ack

      # Wait for the messages to have been published
      sleep 1
    end

    expect(acks.count).to eql(11)
    acks.each do |guid|
      expect(guid.size).to eql(22)
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
