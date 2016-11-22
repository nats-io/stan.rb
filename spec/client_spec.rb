require 'spec_helper'
require 'securerandom'

describe 'Client - Specification' do

  let(:client_id) {
    "scid-#{SecureRandom.hex(5)}"
  }

  it 'should connect and close on block exit' do
    nc = NATS::IO::Client.new
    nc.connect(:servers => ['nats://127.0.0.1:4222'])

    # Borrow the connection to NATS, meaning that we will
    # not be owning the connection.
    stan = STAN::Client.new

    # Discover cluster and send a message, and if block given
    # then we disconnect on exit.
    stan.connect("test-cluster", client_id, nats: nc) do
      # Check connected to STAN
      expect(stan.nats).to_not be_nil
    end

    # NATS connection no longer borrowed once we disconnect from STAN
    expect(stan.nats).to be_nil
  end

  it 'should publish and ack messages' do
    nc = NATS::IO::Client.new
    nc.connect(:servers => ['nats://127.0.0.1:4222'])

    # Borrow the connection to NATS, meaning that we will
    # not be owning the connection.
    sc = STAN::Client.new

    # Discover cluster and send a message, and if block given
    # then we disconnect on exit.
    client_id = "client-#{SecureRandom.hex(5)}"
    acks = []
    sc.connect("test-cluster", client_id, nats: nc)

    10.times do |n|
      sc.publish("hello", "world-#{n}") do |guid, error|
        # Message has been published and acked at this point
        acks << guid
        expect(error).to be_nil
      end
    end

    # Synchronously receives the result or raises
    # an exception in case there was an error
    ack = nil
    expect do
      ack = sc.publish("hello", "again", timeout: 1)
      acks << ack
    end.to_not raise_error

    expect(acks.count).to eql(11)
    acks.each do |guid|
      expect(guid.size).to eql(22)
    end
  end

  context 'when not borrowing NATS connection' do
    it 'should connect and disconnect from NATS on block exit' do
      stan = STAN::Client.new
      msgs = []
      acks = []
      stan.connect("test-cluster", "client-123", :nats => {
          :servers => ["nats://127.0.0.1:4222"]
        }) do |sc|
        expect(stan.nats).to_not be_nil

        sc.subscribe("hello") do |msg|
          msgs << msg
        end

        5.times do
          sc.publish("hello", "world") do |guid, error|
            acks << guid
          end
        end
      end

      # We don't nil out rather we just disconnect from NATS
      expect(stan.nats.closed?).to eql(true)
      expect(msgs.count).to eql(5)
      expect(acks.count).to eql(5)
    end
  end
end
