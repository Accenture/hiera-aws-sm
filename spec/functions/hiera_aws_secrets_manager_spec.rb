require 'spec_helper'
require 'puppet/functions/hiera_aws_secrets_manager'

describe FakeFunction do

  let :function do
    described_class.new
  end

  let :context do
    ctx = instance_double('Puppet::LookupContext')
    allow(ctx).to receive(:cache_has_key).and_return(false)
    #allow(ctx).to receive(:explain).and_return(:nil)
    allow(ctx).to receive(:explain) { |&block| puts(block.call()) }
    allow(ctx).to receive(:not_found).and_throw(:no_such_key)
    allow(ctx).to receive(:cache).with(String, anything) do |_, val|
      val
    end
    allow(ctx).to receive(:interpolate).with(anything) do |val|
      val + '/'
    end
    ctx
  end

  let :asm_options do
    # options passed to the asm function, confine to keys etc
    {

    }
  end

  describe "#lookup_key" do

    it 'should run' do
      expect( function.lookup_key( 'test_key', asm_options, context ) ).to be_nil
    end

  end

end
