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

        # Publishes happen synchronously without a block
        5.times { acks << sc.publish("foo", "bar") }

        # Stop receiving messages in this subscription
        expect do
          sub.unsubscribe
        end.to_not raise_error

        # Should be acked but not received by this client
        5.times { acks << sc.publish("foo", "bar") }
      end
    end
    expect(msgs.count).to eql(5)
    expect(acks.count).to eql(10)
  end

  context 'with subscribe(start_at: :last_received)' do
    it "should be able to use durable name to start at last received on streaming reconnect" do
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      acks = []
      msgs = []
      queue_msgs = []
      non_durable_queue_msgs = []
      plain_sub_msgs = []
      sc = STAN::Client.new

      # Connect a and publish some messages
      with_nats(opts) do |nc|
        sc.connect("test-cluster", client_id, nats: nc)

        sc.subscribe("foo", durable_name: "quux") do |msg|
          msgs << msg
        end

        # Queue subscriptions can coexist with regular subscriptions
        sc.subscribe("foo", queue: "bar", durable_name: "quux") do |msg|
          queue_msgs << msg
        end
        sc.subscribe("foo", queue: "bar", durable_name: "quux") do |msg|
          queue_msgs << msg
        end
        sc.subscribe("foo", queue: "bar") do |msg|
          non_durable_queue_msgs << msg
        end
        sc.subscribe("foo") do |msg|
          plain_sub_msgs << msg
        end

        # We should not be able to create a second durable
        # on the same subject.
        expect do
          sc.subscribe("foo", durable_name: "quux") do |msg|
            msgs << msg
          end
        end.to raise_error(STAN::Error)

        0.upto(4).each {|n| acks << sc.publish("foo", n.to_s) }

        # Disconnect explicitly
        sc.close
      end
      expect(plain_sub_msgs.count).to eql(5)
      expect(non_durable_queue_msgs.count).to eql(5)
      expect(queue_msgs.count).to eql(5)
      expect(acks.count).to eql(5)
      expect(msgs.count).to eql(5)

      # Reconnect trying to fetch last received message
      non_durable_msgs = []
      with_nats(opts) do |nc|
        # Reconnect to STAN
        sc.connect("test-cluster", client_id, nats: nc)

        # Publish new messages and let subscription gather
        # then via durable name and start receive.
        5.upto(10).each {|n| acks << sc.publish("foo", n.to_s) }

        sc.subscribe("foo", durable_name: "quux", start_at: :last_received) do |msg|
          msgs << msg
        end

        # Regular subscription
        sc.subscribe("foo", start_at: :first) do |msg|
          non_durable_msgs << msg
        end

        11.upto(14).each {|n| acks << sc.publish("foo", n.to_s) }

        # We should not be able to create a second durable
        # on the same subject.
        expect do
          sc.subscribe("foo", durable_name: "quux") do |msg|
            msgs << msg
          end
        end.to raise_error(STAN::Error)

        sc.close
      end
      expect(acks.count).to eql(15)
      expect(msgs.count).to eql(15)

      seqs = {}
      msgs.each do |msg|
        seqs[msg.seq] = msg
      end
      0.upto(14).each do |n|
        expect(msgs[n].seq).to eql(n+1)
        expect(msgs[n].data).to eql(n.to_s)
      end
    end

    it "should be able to close durable subscriptions" do
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      acks = []
      durable_sub_msgs       = []
      plain_sub_msgs         = []
      durable_queue_sub_msgs = []
      plain_queue_sub_msgs   = []
      sc = STAN::Client.new

      # Connect a and publish some messages
      with_nats(opts) do |nc|
        sc.connect("test-cluster", client_id, nats: nc)

        durable_sub = sc.subscribe("foo", durable_name: "quux") do |msg|
          durable_sub_msgs << msg
        end
        plain_sub = sc.subscribe("foo") do |msg|
          plain_sub_msgs << msg
        end

        # Queue subscriptions can coexist with regular subscriptions
        durable_queue_sub = sc.subscribe("foo", queue: "bar", durable_name: "quux") do |msg|
          durable_queue_sub_msgs << msg
        end
        plain_queue_sub = sc.subscribe("foo", queue: "bar") do |msg|
          plain_queue_sub_msgs << msg
        end

        # Publish synchronously a batch of messages...
        0.upto(4).each {|n| acks << sc.publish("foo", n.to_s) }
        [durable_sub_msgs, plain_sub_msgs, durable_queue_sub_msgs, plain_queue_sub_msgs, acks].each do |n|
          expect(n.count).to eql(5)
        end

        # Remove the interest in the subscription
        [durable_sub, plain_sub, durable_queue_sub, plain_queue_sub].each do |sub|
          expect do
            sub.close
          end.to_not raise_error
        end

        5.upto(9).each {|n| acks << sc.publish("foo", n.to_s) }
        expect(acks.count).to eql(10)

        # Number of messages should have not increased since we are no longer subscribed
        [durable_sub_msgs, plain_sub_msgs, durable_queue_sub_msgs, plain_queue_sub_msgs].each do |n|
          expect(n.count).to eql(5)
        end

        # Then, replay all the durable subscriptions...
        durable_sub = sc.subscribe("foo", durable_name: "quux", start_at: :last_received) do |msg|
          durable_sub_msgs << msg
        end

        # Last receive here would replay us the first available message for us
        plain_sub = sc.subscribe("foo", start_at: :last_received) do |msg|
          plain_sub_msgs << msg
        end

        durable_queue_sub = sc.subscribe("foo", queue: "bar", durable_name: "quux", start_at: :last_received) do |msg|
          durable_queue_sub_msgs << msg
        end
        plain_queue_sub = sc.subscribe("foo", queue: "bar", start_at: :last_received) do |msg|
          plain_queue_sub_msgs << msg
        end

        # Confirm durable subscription does give us all the messages which we missed
        expect(durable_sub_msgs.count).to eql(10)
        expect(durable_sub_msgs.first.seq).to eql(1)
        expect(durable_sub_msgs.last.seq).to eql(10)
        expect(durable_queue_sub_msgs.count).to eql(10)
        expect(durable_queue_sub_msgs.first.seq).to eql(1)
        expect(durable_queue_sub_msgs.last.seq).to eql(10)

        # We get first available for the subscription here
        expect(plain_sub_msgs.count).to eql(6)
        expect(plain_sub_msgs.first.seq).to eql(1)
        expect(plain_sub_msgs.last.seq).to eql(10)

        # We don't get any newly available message here
        expect(plain_queue_sub_msgs.count).to eql(5)
        expect(plain_queue_sub_msgs.first.seq).to eql(1)
        expect(plain_queue_sub_msgs.last.seq).to eql(5)

        expect do
          sc.close
        end.to_not raise_error
      end
    end
  end

  context 'with a distribution queue group' do
    it "should be able to distribute messages" do
      clients = Hash.new {|h,k| h[k] = {} }
      opts = { :servers => ['nats://127.0.0.1:4222'] }

      # Prepare a few parallel connections to NATS
      ('A'...'E').each do |n|
        name = "#{client_id}-#{n}"
        nc = NATS::IO::Client.new
        nc.connect(opts.merge({ name: name }))
        clients[name][:nats] = nc
        clients[name][:stan] = STAN::Client.new
        clients[name][:acks] = []
        clients[name][:msgs] = []
      end

      begin
        # Connect each one of the clients to STAN
        clients.each_pair do |name, c|
          c[:stan].connect("test-cluster", name, nats: c[:nats])

          # Basic queue subscription
          c[:stan].subscribe("tasks", queue: "group") do |msg|
            c[:msgs] << msg
          end
        end
        name, client = clients.first

        # Publish without a block and wait for acks
        100.times do
          client[:acks] << client[:stan].publish("tasks", "help")
        end

        result = clients.reduce(0) do |total, c|
          name, client = c
          expect(client[:msgs].count).to eql(25)
          total + client[:msgs].count
        end
        expect(result).to eql(100)
      ensure
        # Wait for all clients to unplug from Streaming and NATS
        clients.each_pair do |name, c|
          c[:stan].close
          c[:nats].close
        end
      end
    end
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

    it 'should receive all messages capped by max inflight with auto acks' do
      opts = { :servers => ['nats://127.0.0.1:4222'] }
      acks = []
      msgs = []
      with_nats(opts) do |nc|
        stan = STAN::Client.new
        stan.connect("test-cluster", client_id, nats: nc) do |sc|
          to_send = 50

          1.upto(to_send).each do |n|
            guid = sc.publish("hello", "world-#{n}")
            acks << guid
          end

          # Acks should be occuring automatically but capped to inflight setting
          sub_opts = {
            deliver_all_available: true,
            ack_wait: 1,  # seconds
            max_inflight: 10
          }
          sc.subscribe("hello", sub_opts) do |msg|
            msgs << msg
          end

          # Dummy subscription
          sc.subscribe("hi", sub_opts) do |msg|
            msgs << msg
          end

          # Wait a bit for the messages to have been published
          sleep 2
        end

        # Confirm internal state to check that no other subscriptions remained
        subs = nc.instance_variable_get("@subs")
        expect(subs.count).to eql(0)
      end

      expect(acks.count).to eql(50)
      expect(msgs.count).to eql(50)
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

    it "should redeliver the messages from start on ack timeout" do
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

    it "should redeliver the messages without processed acks on ack timeout" do
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
            ack_wait: 1 # seconds
          }

          # Test we only receive max inflight if we do not ack
          allow_seq_1 = false
          allow_seq_2 = false
          sc.subscribe("hello", sub_opts) do |msg|
            if msg.seq == 1 and not allow_seq_1
              allow_seq_1 = true
              next
            end
            if msg.seq == 2 and not allow_seq_2
              allow_seq_2 = true
              next
            end

            # Allow all others
            msgs << msg

            # Need to process acks manually here
            expect(msg.sub.options[:manual_acks]).to eql(true)

            # receives 100, but first couple not acked manually so redelivered until the end
            sc.ack(msg)
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

      expect(msgs.count).to eql(100)
      expect(acks.count).to eql(100)

      expect(msgs[-4].seq).to eql(99)
      expect(msgs[-3].seq).to eql(100)
      expect(msgs[-2].seq).to eql(1)
      expect(msgs[-1].seq).to eql(2)
    end
  end
end
