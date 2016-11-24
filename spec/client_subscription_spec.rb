require 'spec_helper'
require 'securerandom'
require 'monitor'

describe 'Client - Subscriptions' do

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

  it "should be able to subscribe and unsubscribe" do
    opts = { :servers => ['nats://127.0.0.1:4222'] }
    acks = []
    msgs = []
    stan = STAN::Client.new    
    with_nats(opts) do |nc|
      stan.connect("test-cluster", client_id, nats: nc) do |sc|
        # By default, it only receives any newly published events,
        # this can be defined explicitly via start_at: :new_only
        sub = sc.subscribe("foo") do |msg|
          msgs << msg
        end

        # Publishes happen synchronously
        5.times { acks << sc.publish("foo", "bar") }

        # Stop receiving messages in this subscription
        expect do
          sub.unsubscribe
        end.to_not raise_error

        # Publishes happen synchronously
        5.times { acks << sc.publish("foo", "bar") }
      end
    end
    expect(msgs.count).to eql(5)
    expect(acks.count).to eql(10)    
  end

  context 'with subscribe(start_at: :time, time: $time)' do
    it 'should replay messages older than an hour' do
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      acks = []
      msgs = []
      with_nats(opts) do |nc|
        stan = STAN::Client.new
        stan.connect("test-cluster", client_id, nats: nc) do |sc|
          # Send some messages and the server should replay them back to us
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

          # Take a unix timestamp in seconds with optional nanoseconds if float.
          # Replay all messages which have been received in the last hour
          sc.subscribe("hello", start_at: :time, time: Time.now.to_i - 3600) do |msg|
            msgs << msg
          end

          # FIXME: Wait a bit for the messages to have been published
          sleep 1
        end
      end

      expect(msgs.count).to eql(11)
      expect(acks.count).to eql(11)
      acks.each do |guid|
        expect(guid.size).to eql(22)
      end
    end
  end

  context 'with subscribe(start_at: :timedelta, time: $time)' do
    it 'should replay messages older than 2 sec' do
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      acks = []
      msgs = []
      with_nats(opts) do |nc|
        stan = STAN::Client.new

        # Discover cluster and send a message, and if block given
        # then we disconnect on exit.
        stan.connect("test-cluster", client_id, nats: nc) do |sc|
          # Send some messages and the server should replay them back to us
          # since within the interval.
          1.upto(10).each do |n|
            sc.publish("hello", "world-#{n}") do |guid, error|
              acks << guid
              expect(error).to be_nil
            end
          end

          # These below won't be received
          sleep 3
          11.upto(20).each do |n|
            sc.publish("hello", "world-#{n}") do |guid, error|
              acks << guid
              expect(error).to be_nil
            end
          end

          # Synchronously receives the result or raises
          # an exception in case there was an error
          ack = sc.publish("hello", "again", timeout: 1)
          acks << ack

          # Take a unix timestamp in seconds with optional nanoseconds if float.
          # Replay all messages which have been received in the last hour
          sc.subscribe("hello", start_at: :timedelta, time: Time.now.to_f - 2) do |msg|
            msgs << msg
          end

          # Wait a bit for the messages to have been published
          sleep 1
        end
      end

      expect(msgs.count).to eql(11)
      expect(acks.count).to eql(21)
      acks.each do |guid|
        expect(guid.size).to eql(22)
      end
    end
  end

  context 'with subscribe(start_at: :first)' do
    it 'should replay all the messages' do
      opts = { :servers => ['nats://127.0.0.1:4222']}
      acks = []
      msgs = []
      with_nats(opts) do |nc|
        # Borrow the connection to NATS, meaning that we will
        # not be owning the connection.
        stan = STAN::Client.new

        # Discover cluster and send a message, and if block given
        # then we disconnect on exit.
        stan.connect("test-cluster", client_id, nats: nc) do |sc|
          # Send some messages and the server should replay them back to us
          1.upto(10).each do |n|
            sc.publish("hello", "world-#{n}") do |guid, error|
              # Message has been published and acked at this point
              acks << guid
              expect(error).to be_nil
            end
          end

          11.upto(20).each do |n|
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

          # Take a unix timestamp in seconds with optional nanoseconds if float.
          # Replay all messages which have been received in the last hour
          sc.subscribe("hello", start_at: :first) do |msg|
            msgs << msg
          end

          # Wait a bit for the messages to have been published
          sleep 1
        end
      end

      expect(msgs.count).to eql(21)
      expect(acks.count).to eql(21)
      acks.each do |guid|
        expect(guid.size).to eql(22)
      end
    end
  end

  context 'with subscribe(start_at: :sequence, sequence: $seq)' do
    it 'should replay messages starting from sequence' do
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      acks = []
      msgs = []

      with_nats(opts) do |nc|
        stan = STAN::Client.new
        stan.connect("test-cluster", client_id, nats: nc) do |sc|
          # Send some messages and the server should replay them back to us
          1.upto(10).each do |n|
            sc.publish("hello", "world-#{n}") do |guid, error|
              # Message has been published and acked at this point
              acks << guid
              expect(error).to be_nil
            end
          end

          11.upto(20).each do |n|
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

          # Take a unix timestamp in seconds with optional nanoseconds if float.
          # Replay all messages which have been received in the last hour
          sc.subscribe("hello", start_at: :sequence, sequence: 5) do |msg|
            msgs << msg
          end

          # Wait a bit for the messages to have been published
          sleep 1
        end
      end

      expect(msgs.count).to eql(17)
      expect(acks.count).to eql(21)
      acks.each do |guid|
        expect(guid.size).to eql(22)
      end
    end
  end

  context 'with subscribe(deliver_all_available: true, manual_acks: true)' do
    it 'should receive max inflight only if it does not ack' do
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      acks = []
      msgs = []
      with_nats(opts) do |nc|
        stan = STAN::Client.new
        stan.connect("test-cluster", client_id, nats: nc) do |sc|
          to_send = 100

          1.upto(to_send).each do |n|
            sc.publish("hello", "world-#{n}") do |guid, error|
              acks << guid
              expect(error).to be_nil
            end
          end

          sub_opts = {
            deliver_all_available: true,
            manual_acks: true,
            ack_wait: 1, # seconds
            max_inflight: 10
          }

          # Test we only receive max inflight if we do not ack
          sub = sc.subscribe("hello", sub_opts) do |msg|
            msgs << msg
          end

          # Wait a bit for the messages to have been published
          sleep 1
        end
      end

      expect(msgs.count).to eql(10)
      expect(acks.count).to eql(100)
    end

    it 'should receive all messages capped by max inflight with manual acks' do
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      acks = []
      msgs = []
      with_nats(opts) do |nc|
        stan = STAN::Client.new
        stan.connect("test-cluster", client_id, nats: nc) do |sc|
          to_send = 100

          1.upto(to_send).each do |n|
            sc.publish("hello", "world-#{n}") do |guid, error|
              acks << guid
              expect(error).to be_nil
            end
          end

          sub_opts = {
            deliver_all_available: true,
            manual_acks: true,
            ack_wait: 1,  # seconds
            max_inflight: 10
          }

          # Test we only receive max inflight if we do not ack
          sc.subscribe("hello", sub_opts) do |msg|
            msgs << msg

            # Need to process acks manually here
            expect(msg.sub.options[:manual_acks]).to eql(true)
            sc.ack(msg)
          end

          # Wait a bit for the messages to have been published
          sleep 1
        end
      end

      expect(msgs.count).to eql(100)
      expect(acks.count).to eql(100)
    end

    it "should redeliver the messages on ack timeout" do
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      acks = []
      msgs = []
      with_nats(opts) do |nc|
        stan = STAN::Client.new
        stan.connect("test-cluster", client_id, nats: nc) do |sc|
          to_send = 100

          1.upto(to_send).each do |n|
            sc.publish("hello", "world-#{n}") do |guid, error|
              acks << guid
              expect(error).to be_nil
            end
          end

          sub_opts = {
            deliver_all_available: true,
            manual_acks: true,
            ack_wait: 1,  # seconds
            max_inflight: to_send+1
          }

          # Test we only receive max inflight if we do not ack
          sc.subscribe("hello", sub_opts) do |msg|
            msgs << msg

            # Need to process acks manually here
            expect(msg.sub.options[:manual_acks]).to eql(true)

            # receives 100, but not acked manually so replayed
            # sc.ack(msg)
          end

          # Wait a bit for the messages to have been published
          sleep 1.1
        end
      end

      # Should have received the same sequence number twice
      msgs_map = Hash.new { |h,k| h[k] = []}
      msgs.each do |msg|
        msgs_map[msg.proto.sequence] << msg
      end
      expect(msgs_map.keys.count).to eql(100)

      expect(msgs.count).to eql(200)
      expect(acks.count).to eql(100)
    end
  end
end
