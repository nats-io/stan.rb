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
    it 'should connect to STAN and close session upon connect block exit' do
      # Borrow the connection to NATS, meaning that we will
      # not be owning the connection.
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      with_nats(opts) do |nc|
        stan = STAN::Client.new

        # Discover cluster and send a message, and if block given
        # then we disconnect on exit.
        was_connected = false
        stan.connect("test-cluster", client_id, nats: nc) do
          # Check connected to STAN
          expect(stan.nats).to_not be_nil
          was_connected = true

          noop_sid = stan.subscribe("hello") { |msg| }
        end
        expect(was_connected).to eql(true)

        # NATS connection no longer borrowed once we disconnect from STAN
        expect(stan.nats).to be_nil

        # Though original connection is still connected
        expect(nc.connected?).to eql(true)

        # Confirm internal state to check that no other subscriptions remained
        subs = nc.instance_variable_get("@subs")
        expect(subs.count).to eql(0)
      end
    end

    it 'should publish and ack messages' do
      opts = { :servers => [@s.uri] }
      with_nats(opts) do |nc|
        # Borrow the connection to NATS, meaning that we will
        # not be owning the connection.
        sc = STAN::Client.new

        # Discover cluster and send a message, and if block given
        # then we disconnect on exit.
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

    it 'should publish and allow controlling inflight published acks' do
      opts = { :servers => [@s.uri] }
      with_nats(opts) do |nc|
        stan = STAN::Client.new
        acks = []
        done = stan.new_cond
        stan.connect("test-cluster", client_id, { max_pub_acks_inflight: 100, nats: nc }) do |sc|
          1024.times do |n|
            sc.publish("hello", "world-#{n}") do |guid, error|
              acks << guid
              expect(error).to be_nil
              done.signal if acks.count == 1024
            end
          end
        end

        stan.synchronize do
          done.wait(3)
        end
        expect(acks.count).to eql(1024)
      end
    end

    it 'should reconnect even if not closing gracefully after first connect' do
      opts = { :servers => [@s.uri] }
      with_nats(opts) do |nc|
        sc = STAN::Client.new
        acks = []
        sc.connect("test-cluster", client_id, nats: nc)

        10.times do |n|
          guid = sc.publish("hello", "world-#{n}")
          acks << guid
        end

        expect(acks.count).to eql(10)
      end

      # Initial discovery message on reconnect would take at least 500ms
      with_nats(opts) do |nc|
        sc = STAN::Client.new
        expect do
          sc.connect("test-cluster", client_id, nats: nc, connect_timeout: 0.250)
        end.to raise_error(NATS::IO::TimeoutError)
      end

      with_nats(opts) do |nc|
        sc = STAN::Client.new
        acks = []
        expect do
          sc.connect("test-cluster", client_id, nats: nc, connect_timeout: 1) do
            10.times do |n|
              guid = sc.publish("hello", "world-#{n}")
              acks << guid
            end

            expect(acks.count).to eql(10)
          end
        end.to_not raise_error
      end
    end
  end

  context 'when not borrowing NATS connection' do
    it 'should connect and disconnect from NATS on block exit' do
      stan = STAN::Client.new
      opts = { :servers => [@s.uri] }
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
