Puppet::Functions.create_function(:hiera_aws_secrets_manager) do

  begin
    require 'json'
  rescue LoadError => e
    raise Puppet::DataBinding::LookupError, "[hiera-aws-secrets-manager] Must install json gem to use hiera-aws-secrets-manager backend"
  end
  begin
    require 'aws-sdk'
  rescue LoadError => e
    raise Puppet::DataBinding::LookupError, "[hiera-aws-secrets-manager] Must install aws-sdk gem to use hiera-aws-secrets-manager backend"
  end


  dispatch :lookup_key do
    param 'Variant[String, Numeric]', :key
    param 'Hash', :options
    param 'Puppet::LookupContext', :context
  end

end
