require 'spec_helper'

describe 'Client - Specification' do

  it 'should connect and close on block exit' do
    NATS.start do |nc|
      # Borrow the connection to NATS, meaning that we will
      # not be owning the connection.
      stan = STAN::Client.new(nc)

      # Discover cluster and send a message, and if block given
      # then we disconnect on exit.
      client_id = "client-#{rand(100)}"
      stan.connect("test-cluster", client_id) do |sc|
        sc.subscribe("hello") do |msg|
          # Message has been received
        end

        sc.publish("hello", "world") do
          # Message has been published
          puts "published message!!!!"

          # Though should be received ack
        end
      end

      EM.add_timer(1) do
        EM.stop
      end
    end
  end

  it 'should connect to NATS if not borrowing connection and disconnect on block exit' do
    stan = STAN::Client.new(nc)
    stan.connect("test-cluster", "client-123", :nats => {
        :servers => ["nats://127.0.0.1:4222"]
      }) do |sc|
      # sc.subscribe("hello") do |msg|
      #   # Message has been received
      # end

      sc.publish("hello", "world") do
        # Message has been published
      end
    end
  end
end
