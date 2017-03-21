require 'spec_helper'
require 'securerandom'

describe 'Client - Reconnection' do

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

  context "with clients using the same client ID" do

    it 'should prevent new client connecting if already connected one replied it is healthy' do
      opts = { :servers => [@s.uri] }

      scA = stale_client = STAN::Client.new
      scB = active_client = STAN::Client.new

      acks = []
      with_nats(opts) do |nc1, nc2|
        scA.connect("test-cluster", client_id, nats: nc1)

        10.times do |n|
          guid = scA.publish("hello", "world-#{n}")
          acks << guid
        end

        expect do
          scB.connect("test-cluster", client_id, nats: nc2)
        end.to raise_error(STAN::ConnectError)

        # Publishing will not work since we do not know the channel
        # against which we can make publish commands.
        expect do
          scB.publish("hello", "world-B", ack_wait: 1)
        end.to raise_error(STAN::BadConnectionError)

        expect do
          scB.subscribe("hello")
        end.to raise_error(STAN::BadConnectionError)
      end
      expect(acks.count).to eql(10)
    end

    it 'should replace original client connecting if server health check request fails' do
      opts = { :servers => [@s.uri] }
      consumer_client_id = "scid-#{SecureRandom.hex(5)}"

      # A will be replaced by B and C is actively receiving messages
      # being published by both from the beginning.
      scA = stale_client = STAN::Client.new
      scB = active_client = STAN::Client.new
      scC = consumer_client = STAN::Client.new
      acks_A, acks_B, acks_C = [[], [], []]
      msgs_A, msgs_B, msgs_C = [[], [], []]

      stale_client_msgs = []
      with_nats(opts) do |nc1, nc2, nc3|
        scC.connect("test-cluster", consumer_client_id, nats: nc3)
        scC.subscribe("hello") do |msg|
          msgs_C << msg
        end

        scA.connect("test-cluster", client_id, nats: nc1)
        scA.subscribe("hello") do |msg|
          msgs_A << msg
        end
        1.upto(10).each do |n|
          guid = scA.publish("hello", "world-#{n}")
          acks_A << guid
        end

        # Simulate client failing to reply fast enough to health check request
        # during the connection from the other client with the same name, which
        # could have occured during a partition of a NATS cluster...
        scA.instance_eval do
          def process_heartbeats(data, reply, subject)
            sleep 1
            nats.publish(reply, '')
          end
        end

        scB.connect("test-cluster", client_id, nats: nc2)
        scB.subscribe("hello") do |msg|
          msgs_B << msg
        end

        # Publishing will work since client has replaced the original client
        11.upto(20).each do |n|
          guid = scB.publish("hello", "world-#{n}", ack_wait: 1)
          acks_B << guid
        end

        # Publishing will _still_ work in older client even though it has been
        # replaced by another one, this behavior remains indefinitely and partitioned
        # client remains as a zombie since not participating in heartbeats
        # so it will never disconnect from a failure detector...
        #
        # The client that has gone away during the partition is also able to
        # just continue to publish commands and leaves off only when there has
        # been an error...
        #
        21.upto(30).each do |n|
          guid = scA.publish("hello", "world-#{n}", ack_wait: 1)
          acks_A << guid
        end

        # Subscribing will _still_ work in the partitioned zombie client and
        # can replay all the messages from scratch.
        sub = scA.subscribe("hello", start_at: :first) do |msg|
          stale_client_msgs << msg
        end
        sleep 1
        expect(stale_client_msgs.count).to eql(30)
      end
      expect(acks_A.count).to eql(20)
      expect(acks_B.count).to eql(10)
      expect(acks_C.count).to eql(0) # since did not publish anything

      # Client A which has been replaced will not be receiving
      # messages that were sent after the partition.
      expect(msgs_A.count).to eql(10)
      expect(msgs_B.count).to eql(20)
      expect(msgs_C.count).to eql(30)
    end
  end
end
