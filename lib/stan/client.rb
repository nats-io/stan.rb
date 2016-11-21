require 'nats/io/client'
require 'securerandom'

module STAN

  # Errors
  class Error < StandardError; end

  # When we detect we cannot connect to the server
  class ConnectError < Error; end

  class Client
    attr_reader :nats

    def initialize(nc=nil)
      # Connection to NATS, either owned or borrowed
      @nats = nc

      # STAN subscriptions
      @subs = {}

      # Publish Ack (guid => ack)
      @pub_acks = {}

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

      # Subscription for processing heartbeat requests
      nats.subscribe(@hb_inbox) do |msg|
        # Received heartbeat message
        # p "--- Heartbeat: #{msg}"
      end

      # Acks processing
      nats.subscribe(@ack_subject) do |msg|
        # Process ack
        # p "--- Ack: #{msg}"
      end

      req = STAN::Protocol::ConnectRequest.new({
        clientID: @client_id,
        heartbeatInbox: @hb_inbox
      })

      # Connect request to discover subjects to communicate with STAN.
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
        raw = nats.request(@close_req_subject, req.to_proto, max: 1)

        resp = STAN::Protocol::CloseResponse.decode(raw.data)
        unless resp.error.empty?
          raise Error.new("stan: close response error: #{resp.error}")
        end
      end
    end

    # Publish will publish to the cluster and wait for an ack
    def publish(subject, payload, &blk)
      subject = "#{@pub_prefix}.#{subject}"
      guid = STAN.create_guid

      pe = STAN::Protocol::PubMsg.new({
        clientID: @client_id,
        guid: guid,
        subject: subject,
        data: payload
      })

      # This should be on a fiber as well
      @ack_map[guid] = proc do
        blk.call if blk
      end

      nats.publish(subject, pe.to_proto, @ack_subject) do
        # Published, so next wait for the ack to be processed
      end
    end

    def subscribe(subject)
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
