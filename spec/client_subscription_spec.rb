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

  context 'with subscribe(start_at: :time, time: $time)' do
    it 'should replay messages older than an hour' do
      nc = NATS::IO::Client.new
      nc.connect(:servers => ['nats://127.0.0.1:4222'])

      # Borrow the connection to NATS, meaning that we will
      # not be owning the connection.
      stan = STAN::Client.new

      # Discover cluster and send a message, and if block given
      # then we disconnect on exit.
      acks = []
      msgs = []
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

        # Wait a bit for the messages to have been published
        sleep 1
      end

      expect(msgs.count > 10).to eql(true)
      expect(acks.count).to eql(11)
      acks.each do |guid|
        expect(guid.size).to eql(22)
      end
    end
  end

  context 'with subscribe(start_at: :timedelta, time: $time)' do
    it 'should replay messages older than 2 sec' do
      nc = NATS::IO::Client.new
      nc.connect(:servers => ['nats://127.0.0.1:4222'])

      # Borrow the connection to NATS, meaning that we will
      # not be owning the connection.
      stan = STAN::Client.new

      # Discover cluster and send a message, and if block given
      # then we disconnect on exit.
      acks = []
      msgs = []
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

      expect(msgs.count).to eql(11)
      expect(acks.count).to eql(21)
      acks.each do |guid|
        expect(guid.size).to eql(22)
      end
    end
  end

  context 'with subscribe(start_at: :first)' do
    it 'should replay all the messages' do
      nc = NATS::IO::Client.new
      nc.connect(:servers => ['nats://127.0.0.1:4222'])

      # Borrow the connection to NATS, meaning that we will
      # not be owning the connection.
      stan = STAN::Client.new

      # Discover cluster and send a message, and if block given
      # then we disconnect on exit.
      acks = []
      msgs = []
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

      expect(msgs.count > 10).to eql(true)
      expect(msgs.count).to eql(21)
      expect(acks.count).to eql(21)
      acks.each do |guid|
        expect(guid.size).to eql(22)
      end
    end
  end
end
