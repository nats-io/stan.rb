require 'ostruct'

describe 'Client - Utils' do
  context "#to_s" do
    it "should work in STAN::Client" do
      stan = STAN::Client.new
      expect do
        stan.to_s
      end.to_not raise_error
    end

    it "should work in STAN::Subscription" do
      sub = STAN::Subscription.new("foo", {})
      expect do
        sub.to_s
      end.to_not raise_error
    end

    it "should work in STAN::Msg" do
      proto = OpenStruct.new
      proto.timestamp = Time.now.to_f * 1_000_000_000.0
      msg = STAN::Msg.new(proto, nil)
      expect do
        msg.to_s
      end.to_not raise_error
    end
  end
end
