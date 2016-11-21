require 'nats/io/client'
require 'securerandom'
require 'monitor'

module STAN

  # Errors
  class Error < StandardError; end

  # When we detect we cannot connect to the server
  class ConnectError < Error; end

  # When we detect we have a request timeout
  class TimeoutError < Error; end

  class Client
    include MonitorMixin

    attr_reader :nats

    def initialize
      super

      # Connection to NATS, either owned or borrowed
      @nats = nil

      # STAN subscriptions
      @subs = {}

      # Publish Ack (guid => ack)
      @pub_ack_map = {}

      # Cluster to which we are connecting
      @cluster_id = nil
      @client_id = nil

      # Inbox for period heartbeat messages
      @heartbeat_inbox = nil

      # Connect options
      @options = {}

      # NATS Streaming subjects

      # Publish prefix set by stan to which we append our subject on publish.
      @pub_prefix        = nil
      @sub_req_subject   = nil
      @unsub_req_subject = nil
      @close_req_subject = nil

      # For initial connect request to discover subjects used by
      # the streaming server.
      @discover_subject = nil

      # For processing received acks from the server
      @ack_subject = nil
    end

    # Plugs into a NATS Streaming cluster, establishing a connection
    # to NATS in case there is not one available to be borrowed.
    def connect(cluster_id, client_id, options={}, &blk)
      @cluster_id = cluster_id
      @client_id  = client_id
      @options    = options

      # Prepare connect discovery request
      @discover_subject = "_STAN.discover.#{@cluster_id}".freeze

      # Prepare acks processing subscription
      @ack_subject = "_STAN.acks.#{STAN.create_guid}".freeze

      if @nats.nil?
        case options[:nats]
        when Hash
          # Custom NATS options in case borrowed connection not present
          # can be passed to establish a connection and have stan client
          # owning it.
          @nats = NATS::IO::Client.new
          nats.connect(options[:nats])
        when NATS::IO::Client
          @nats = options[:nats]
        end
      end

      # If no connection to NATS present at this point then bail already
      raise ConnectError.new("stan: invalid connection to nats") unless @nats

      # Heartbeat subscription
      @hb_inbox = (STAN.create_inbox).freeze

      # Setup acks and heartbeats processing callbacks
      nats.subscribe(@hb_inbox)    { |raw| process_heartbeats(raw) }
      nats.subscribe(@ack_subject) { |raw| process_ack(raw) }

      # Initial connect request to discover subjects to be used
      # for communicating with STAN.
      req = STAN::Protocol::ConnectRequest.new({
        clientID: @client_id,
        heartbeatInbox: @hb_inbox
      })

      # TODO: Check for error and bail if required
      raw = nats.request(@discover_subject, req.to_proto)
      resp = STAN::Protocol::ConnectResponse.decode(raw.data)
      @pub_prefix = resp.pubPrefix.freeze
      @sub_req_subject = resp.subRequests.freeze
      @unsub_req_subject = resp.unsubRequests.freeze
      @close_req_subject = resp.closeRequests.freeze

      # If callback given then we send a close request on exit
      # and wrap up session to STAN.
      if blk
        blk.call(self)

        # Close session to the STAN cluster
        req = STAN::Protocol::CloseRequest.new(clientID: @client_id)
        raw = nats.request(@close_req_subject, req.to_proto)

        resp = STAN::Protocol::CloseResponse.decode(raw.data)
        unless resp.error.empty?
          raise Error.new("stan: close response error: #{resp.error}")
        end
      end
    end

    # Publish will publish to the cluster and wait for an ack
    def publish(subject, payload, opts={}, &blk)
      subject = "#{@pub_prefix}.#{subject}"
      future = nil
      guid = STAN.create_guid

      pe = STAN::Protocol::PubMsg.new({
        clientID: @client_id,
        guid: guid,
        subject: subject,
        data: payload
      })

      if blk
        # Asynchronously handled
        synchronize do
          # Map ack to guid
          @pub_ack_map[guid] = proc do |ack|
            # If block is given, handle the result asynchronously
            case blk.arity
            when 0 then blk.call
            when 1 then blk.call(ack.guid)
            when 2 then blk.call(ack.guid, ack.error)
            end

            @pub_ack_map.delete(ack.guid)
          end
          nats.publish(subject, pe.to_proto, @ack_subject)
        end
      else
        # Waits for response before giving back control
        future = new_cond
        opts[:timeout] ||= 30 # Default Ack Wait
        synchronize do
          # Map ack to guid
          ack_response = nil
          @pub_ack_map[guid] = proc do |ack|
            ack_response = ack
            future.signal
          end

          # Send publish request and wait for the ack response
          nats.publish(subject, pe.to_proto, @ack_subject)
          start_time = NATS::MonotonicTime.now
          future.wait(opts[:timeout])
          end_time = NATS::MonotonicTime.now
          if (end_time - start_time) > opts[:timeout]
            raise TimeoutError.new("stan: timeout")
          end
          @pub_ack_map.delete(ack_response.guid)
          return ack_response
        end
      end

      # TODO: Processing of acks expiration
    end

    def subscribe(subject)
    end

    private

    def process_ack(data)
      # Process ack
      pub_ack = STAN::Protocol::PubAck.decode(data)
      unless pub_ack.error.empty?
        raise Error.new("stan: pub ack error: #{pub_ack.error}")
      end

      synchronize do
        if cb = @pub_ack_map[pub_ack.guid]
          cb.call(pub_ack)
        end
      end

      # FIXME: This should handle errors asynchronously
    end

    def process_heartbeats(data)
      # Received heartbeat message
    end
  end

  class << self
    def create_guid
      SecureRandom.hex(11)
    end

    def create_inbox
      SecureRandom.hex(13)
    end
  end
end
