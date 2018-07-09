require 'spec_helper'
require 'puppet/functions/hiera_aws_sm'

describe FakeFunction do

  let :function do
    described_class.new
  end

  let :options do
    {}
  end

  let :context do
    ctx = instance_double('Puppet::LookupContext')
    allow(ctx).to receive(:cache_has_key).and_return(false)
    allow(ctx).to receive(:explain)
    allow(ctx).to receive(:not_found).and_throw(:no_such_key)
    allow(ctx).to receive(:cache).with(String, anything) do |_, val|
      val
    end
    allow(ctx).to receive(:interpolate).with(anything) do |val|
      val + '/'
    end
    ctx
  end


  describe "lookup_key" do

    it 'should run' do
      expect(function.lookup_key('test_key', options, context)).to be_nil
    end

    # Test parameters / options

    # Test behaviour
    context 'accessing non-existant key' do
      before do
        Aws.config[:secretsmanager] = {
          stub_responses: {
            get_secret_value: 'ResourceNotFoundException'
          }
        }
      end
      describe "with continue_if_not_found" do
        let :options do
          { "continue_if_not_found" => true }
        end
        it 'should throw no_such_key' do
          expect{function.lookup_key('test_key', options, context)}.to throw_symbol(:no_such_key)
        end
      end
      describe "without continue_if_not_found" do
        it 'should return nil' do
          expect(function.lookup_key('test_key', options, context)).to be_nil
        end
      end
    end

    context "when missing permissions" do
      before do
        Aws.config[:secretsmanager] = {
          stub_responses: {
            get_secret_value: 'UnrecognizedClientException'
          }
        }
      end
      it 'should crash' do
        expect{function.lookup_key('test_key', options, context)}
          .to raise_error(Puppet::DataBinding::LookupError, "[hiera-aws-sm] Skipping backend. No permission to access test_key")
      end
    end

    context "on failing to call SecretsManager" do
      before do
        Aws.config[:secretsmanager] = {
          stub_responses: {
            get_secret_value: 'ServiceError'
          }
        }
      end
      it 'should crash when failing to call SecretsManager' do
        expect{function.lookup_key('test_key', options, context)}
          .to raise_error(Puppet::DataBinding::LookupError, "[hiera-aws-sm] Skipping backend. Failed to lookup test_key")
      end
    end

    context "when querying a simple secret" do
      before do
        Aws.config[:secretsmanager] = {
          stub_responses: {
            get_secret_value: {
              name: 'test_key',
              secret_string: 'password1'
            }
          }
        }
      end
      it 'should return a String' do
        expect(function.lookup_key('test_key', options, context))
          .to be_a(String)
      end
      it 'should be the correct value' do
        expect(function.lookup_key('test_key', options, context))
          .to eq('password1')
      end
    end

    context "when querying a json encoded secret" do
      before do
        Aws.config[:secretsmanager] = {
          stub_responses: {
            get_secret_value: {
              name: 'test_key',
              secret_string: "{\"key1\": \"value1\", \"key2\": \"value2\"}"
            }
          }
        }
      end
      it 'should return a Hash' do
        expect(function.lookup_key('test_key', options, context))
          .to be_a(Hash)
      end
      it 'should be the correct value' do
        expect(function.lookup_key('test_key', options, context))
          .to eq({
            "key1" => "value1",
            "key2" => "value2"
          })
      end
    end
  end
end
