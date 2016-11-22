require 'spec_helper'
require 'securerandom'
require 'monitor'

describe 'Client - Subscriptions' do

  let(:client_id) {
    "scid-#{SecureRandom.hex(5)}"
  }

  context 'with subscribe(start_at: time, time: 1.hour.ago)' do
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
      client_id = "client-#{SecureRandom.hex(5)}"
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
end
