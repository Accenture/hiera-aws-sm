Puppet::Functions.create_function(:hiera_aws_sm) do

  begin
    require 'json'
  rescue LoadError => e
    raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Must install json gem to use hiera-aws-sm backend"
  end
  begin
    require 'aws-sdk-core'
  rescue LoadError => e
    raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Must install aws-sdk-core gem to use hiera-aws-sm backend"
  end
  begin
    require 'aws-sdk-secretsmanager'
  rescue LoadError => e
    raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Must install aws-sdk-secretsmanager gem to use hiera-aws-sm backend"
  end


  dispatch :lookup_key do
    param 'Variant[String, Numeric]', :key
    param 'Hash', :options
    param 'Puppet::LookupContext', :context
  end


  ##
  # lookup_key
  #
  # Determine whether to lookup a given key in secretsmanager, and if so, return the result of the lookup
  #
  # @param key Key to lookup
  # @param options Options hash
  # @param context Puppet::LookupContext
  def lookup_key(key, options, context)
    # Filter out keys that do not match a regex in `confine_to_keys`, if it's specified
    if confine_keys = options["confine_to_keys"]
      raise ArgumentError, "[hiera-aws-sm] confine_to_keys must be an array" unless confine_keys.is_a?(Array)

      begin
        confine_keys = confine_keys.map{ |r| Regexp.new(r) }
      rescue StandardError => err
        raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Failed to create regexp with error #{err}"
      end
      re_match = Regexp.union(confine_keys)
      unless key[re_match] == key
        context.explain("[hiera-aws-sm] Skipping secrets manager as #{key} doesn't match confine_to_keys")
        context.not_found
      end
    end

    # Query SecretsManager for the secret data
    result = get_secret(key, options, context)

    continue_if_not_found = options["continue_if_not_found"] || false

    if result.nil? and continue_if_not_found
      context.not_found
    end
    return result
  end

  ##
  # get_secret
  #
  # Lookup a given key in AWS Secrets Manager
  #
  # @param key Key to lookup
  # @param options Options hash
  # @param context Puppet::LookupContext
  #
  # @return One of Hash, String, (Binary?) depending on the value returned
  # by AWS Secrets Manager. If a secret_binary is present in the response,
  # it is returned directly. If secret_string is set, and can be co-erced
  # into a Hash, it is returned, otherwise a String is returned.
  def get_secret(key, options, context)

    secretsmanager = Aws::SecretsManager::Client.new
    secret_key = secret_key_name(key, options)

    response = nil
    secret = nil

    context.explain("[hiera-aws-sm] Looking up #{secret_key}")
    begin
      response = secretsmanager.get_secret_value(secret_id: secret_key)
    rescue Aws::SecretsManager::Errors::ResourceNotFoundException
      context.explain("[hiera-aws-sm] No data found for #{secret_key}")
    rescue Aws::SecretsManager::Errors::UnrecognizedClientException
      raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Skipping backend. No permission to access #{secret_key}"
    rescue Aws::SecretsManager::Errors::ServiceError
      raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Skipping backend. Failed to lookup #{secret_key}"
    end

    if ! response.nil?
      if ! response.secret_binary.nil?
        context.explain("[hiera-aws-sm] #{secret_key} is a binary")
        secret = response.secret_binary
      else
        # Do our processing in here
        secret = process_secret_string(response.secret_string, options, context)
      end
    end

    return secret
  end

  ##
  # Get the secret name to lookup, applying a prefix if
  # one is set in the options
  def secret_key_name(key, options)
    if options.key?('prefix')
      [options.prefix, key].join('/')
    else
      key
    end
  end

  ##
  # Process the response secret string by attempting to coerce it
  def process_secret_string(secret_string, options, context)
    # Attempt to process this string as a JSON object
    begin
      result = JSON.parse(secret_string)
    rescue JSON::ParserError
      context.explain("[hiera-aws-sm] Not a hashable result")
      result = secret_string
    end

    return result
  end

end
