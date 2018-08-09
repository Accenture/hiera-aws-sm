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
    #allow(ctx).to receive(:explain) { |&block| puts(block.call()) }
    allow(ctx).to receive(:not_found).and_throw(:no_such_key)
    allow(ctx).to receive(:cache).with(String, anything) do |_, val|
      val
    end
    allow(ctx).to receive(:interpolate).with(anything) do |val|
      val + '/'
    end
    ctx
  end

  describe 'lookup_key' do
    before :each do
      Aws.config[:secretsmanager] = {
        stub_responses: {
          get_secret_value: 'ResourceNotFoundException',
        },
      }
    end
    it 'will run' do
      expect(function.lookup_key('test_key', options, context)).to be_nil
    end

    # Test parameters / options
    context 'when AWS options are set' do
      describe 'and region set' do
        let :options do
          { 'region' => 'us-east-1' }
        end
        it 'will run' do
          expect(function.lookup_key('test_key', options, context)).to be_nil
        end
      end
      describe 'and aws_access_key set' do
        let :options do
          { 'aws_access_key' => 'hunter2' }
        end
        it 'will run' do
          expect(function.lookup_key('test_key', options, context)).to be_nil
        end
      end
      describe 'and aws_secret_key set' do
        let :options do
          { 'aws_secret_key' => 'hunter2' }
        end
        it 'will run' do
          expect(function.lookup_key('test_key', options, context)).to be_nil
        end
      end
    end
    context 'when confine_to_keys is set' do
      describe 'and not an array' do
        let :options do
          { 'confine_to_keys' => 'foobar' }
        end

        it 'will raise ArgumentError' do
          expect { function.lookup_key('test_key', options, context) }
            .to raise_error(ArgumentError, '[hiera-aws-sm] confine_to_keys must be an array')
        end
      end
      describe 'with regex values' do
        before :each do
          Aws.config[:secretsmanager] = {
            stub_responses: {
              get_secret_value: {
                name: 'puppet_password',
                secret_string: 'password1',
              },
            },
          }
        end
        let :options do
          { 'confine_to_keys' => ['^puppet_.*'] }
        end

        it 'return context.not_found for non-matching keys' do
          expect { function.lookup_key('test_key', options, context) }.to throw_symbol(:no_such_key)
        end
        it 'return the expected result for matching keys' do
          expect(function.lookup_key('puppet_password', options, context)).to eq('password1')
          expect(function.lookup_key('puppet_password', options, context)).to be_a(String)
        end
      end
    end

    context 'when prefixes are set' do
      describe 'and not an array' do
        let :options do
          { 'prefixes' => 'some-prefix' }
        end

        it 'raise ArgumentError' do
          expect { function.lookup_key('test_key', options, context) }
            .to raise_error(ArgumentError, '[hiera-aws-sm] prefixes must be an array')
        end
      end

      describe 'with prefix values' do
        let :options do
          { 'prefixes' => [
            'puppet/mynode',
            'puppet/common',
            'dev-environment/mynode',
            'dev-environment/common',
          ] }
        end

        describe 'and matching secret' do
          before :each do
            Aws.config[:secretsmanager] = {
              stub_responses: {
                get_secret_value: {
                  name: 'puppet/common/password',
                  secret_string: 'password1',
                },
              },
            }
          end
          it 'return the expected result for matching keys' do
            expect(function.lookup_key('password', options, context)).to eq('password1')
            expect(function.lookup_key('password', options, context)).to be_a(String)
          end
          describe 'and invalid delimiter passed' do
            let :options do
              super().merge('delimiter' => %w[foo bar])
            end

            it 'raise ArgumentError' do
              expect { function.lookup_key('test_key', options, context) }
                .to raise_error(ArgumentError, '[hiera-aws-sm] delimiter must be a String')
            end
          end
        end
        describe 'and no matching secret' do
          before :each do
            Aws.config[:secretsmanager] = {
              stub_responses: {
                get_secret_value: 'ResourceNotFoundException',
              },
            }
          end
          it 'return nil' do
            expect(function.lookup_key('test_key', options, context)).to be_nil
          end
          describe 'with continue_if_not_found set' do
            let :options do
              super().merge('continue_if_not_found' => true)
            end

            it 'throw no_such_key' do
              expect { function.lookup_key('test_key', options, context) }.to throw_symbol(:no_such_key)
            end
          end
        end
      end
    end

    # Test behaviour
    context 'accessing non-existant key' do
      before :each do
        Aws.config[:secretsmanager] = {
          stub_responses: {
            get_secret_value: 'ResourceNotFoundException',
          },
        }
      end
      describe 'with continue_if_not_found' do
        let :options do
          { 'continue_if_not_found' => true }
        end

        it 'throw no_such_key' do
          expect { function.lookup_key('test_key', options, context) }.to throw_symbol(:no_such_key)
        end
      end
      describe 'without continue_if_not_found' do
        it 'return nil' do
          expect(function.lookup_key('test_key', options, context)).to be_nil
        end
      end
    end

    context 'when missing permissions' do
      before :each do
        Aws.config[:secretsmanager] = {
          stub_responses: {
            get_secret_value: 'UnrecognizedClientException',
          },
        }
      end
      it 'will crash' do
        expect { function.lookup_key('test_key', options, context) }
          .to raise_error(Puppet::DataBinding::LookupError, '[hiera-aws-sm] Skipping backend. No permission to access test_key')
      end
    end

    context 'on failing to call SecretsManager' do
      before :each do
        Aws.config[:secretsmanager] = {
          stub_responses: {
            get_secret_value: 'ServiceError',
          },
        }
      end
      it 'will crash when failing to call SecretsManager' do
        expect { function.lookup_key('test_key', options, context) }
          .to raise_error(Puppet::DataBinding::LookupError, /\[hiera-aws-sm\] Skipping backend. Failed to lookup test_key due to .*/)
      end
    end

    context 'when querying a simple secret' do
      before :each do
        Aws.config[:secretsmanager] = {
          stub_responses: {
            get_secret_value: {
              name: 'test_key',
              secret_string: 'password1',
            },
          },
        }
      end
      it 'will return a String' do
        expect(function.lookup_key('test_key', options, context))
          .to be_a(String)
      end
      it 'will be the correct value' do
        expect(function.lookup_key('test_key', options, context))
          .to eq('password1')
      end
    end

    context 'when querying a json encoded secret' do
      before :each do
        Aws.config[:secretsmanager] = {
          stub_responses: {
            get_secret_value: {
              name: 'test_key',
              secret_string: '{"key1": "value1", "key2": "value2"}',
            },
          },
        }
      end
      it 'will return a Hash' do
        expect(function.lookup_key('test_key', options, context))
          .to be_a(Hash)
      end
      it 'will be the correct value' do
        expect(function.lookup_key('test_key', options, context))
          .to eq(
            'key1' => 'value1',
            'key2' => 'value2',
          )
      end
    end
  end
end
