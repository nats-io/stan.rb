require 'spec_helper'
require 'securerandom'

describe 'Client - Specification' do

  let(:client_id) {
    "scid-#{SecureRandom.hex(5)}"
  }

  before(:each) do
    @s = NatsStreamingServerControl.new
    @s.start_server(true)

    # FIXME: We need to wait for the server to be ready...
    sleep 1
  end

  after(:each) do
    @s.kill_server
    # FIXME: We need to wait for the server to be ready...
    sleep 1
  end

  context "with borrowed NATS connection" do
    it 'should connect to STAN and close session on connect block exit' do
      nc = NATS::IO::Client.new
      begin
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

        # Though original connection is still connected
        expect(nc.connected?).to eql(true)
      ensure
        nc.close rescue nil
      end
    end

    it 'should publish and ack messages' do
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      with_nats(opts) do |nc|
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
    end
  end

  context 'when not borrowing NATS connection' do
    it 'should connect and disconnect from NATS on block exit' do
      stan = STAN::Client.new
      opts = { :servers => ["nats://127.0.0.1:4222"] }
      msgs = []
      acks = []      
      stan.connect("test-cluster", "client-123", nats: opts) do |sc|
        expect(stan.nats).to_not be_nil

        sc.subscribe("hello") do |msg|
          msgs << msg
        end

        5.times do
          acks << sc.publish("hello", "world")
        end
      end

      # We don't nil out rather we just disconnect from NATS
      expect(stan.nats.closed?).to eql(true)
      expect(msgs.count).to eql(5)
      expect(acks.count).to eql(5)
    end
  end
end
