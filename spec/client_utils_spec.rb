# Copyright 2017-2018 The NATS Authors
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#


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
