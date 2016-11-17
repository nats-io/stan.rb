require 'nats/client'
require 'fiber'

module STAN

  # Errors
  class Error < StandardError; end

  # When we detect we cannot connect to the server
  class ConnectError < Error; end

  class Client

    def initialize(nc=nil)
      # Connection to NATS, either owned or borrowed
      @nats = nc

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
    end

    # Plugs into a NATS Streaming cluster, establishing a connection
    # to NATS in case there is not one available to be borrowed.
    def connect(cluster_id, client_id, options={})
      @cluster_id = cluster_id
      @client_id  = client_id
      @options    = options

      # Prepare connect discovery request
      @discover_subject = "_STAN.discover.#{@cluster_id}".freeze

      case options[:nats]
      when Hash
        # Custom NATS options in case borrowed connection not present
        # can be passed to establish a connection and have stan client
        # owning it.
        # TODO: Synchronously establish connection to NATS here
        opts = options[:nats] || {}
      when NATS::EM_CONNECTION_CLASS
        # Check for case when connection is of type NATS client
        # and throw an error here instead.
        @nats = options[:nats]
      end

      # If no connection to NATS present at this point then bail already
      raise ConnectError.new("stan: invalid connection to NATS") unless @nats

      # Heartbeat subscription
      @hb_inbox = (NATS.create_inbox).freeze

      # Subscription for processing heartbeat requests
      @nats.subscribe(@hb_inbox) do |msg|
        # Received heartbeat message
        p "--- Heartbeat: #{msg}"
      end


      req = STAN::Protocol::ConnectRequest.new({
        clientID: @client_id,
        heartbeatInbox: @hb_inbox
      })

      # Connect request to discover subjects to communicate with STAN.
      Fiber.new do
        # TODO: Check for error and bail if required
        f = Fiber.current
        sid = @nats.request(@discover_subject, req.to_proto, max: 1) do |raw|
          f.resume(raw)
        end

        # Timeout the request within a second in case failing to connect
        # to STAN cluster.
        @nats.timeout(sid, 1, :expected => 1) { f.resume(nil) }

        raw = Fiber.yield
        resp = STAN::Protocol::ConnectResponse.decode(raw)
        @pub_prefix = resp.pubPrefix.freeze
        @sub_req_subject = resp.subRequests.freeze
        @unsub_req_subject = resp.unsubRequests.freeze
        @close_req_subject = resp.closeRequests.freeze
      end.resume

      # If callback given then we send a close request on exit
      if block_given?
        yield self

        # Close connection to 
        result = STAN::Protocol::CloseRequest.new(clientID: @client_id)
        p req
        sid = @nats.request(@close_req_subject, req.to_proto, max: 1) do |raw|
          p raw
        end
        p "result: #{result} || #{sid}"
      end
    end

    def publish(subject, payload)
    end

    def subscribe(subject)
    end
  end
end
