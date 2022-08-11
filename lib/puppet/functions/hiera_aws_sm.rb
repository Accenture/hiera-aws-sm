Puppet::Functions.create_function(:hiera_aws_sm) do
  begin
    require 'json'
  rescue LoadError
    raise Puppet::DataBinding::LookupError, '[hiera-aws-sm] Must install json gem to use hiera-aws-sm backend'
  end
  begin
    require 'aws-sdk-core'
  rescue LoadError
    raise Puppet::DataBinding::LookupError, '[hiera-aws-sm] Must install aws-sdk-core gem to use hiera-aws-sm backend'
  end
  begin
    require 'aws-sdk-secretsmanager'
  rescue LoadError
    raise Puppet::DataBinding::LookupError, '[hiera-aws-sm] Must install aws-sdk-secretsmanager gem to use hiera-aws-sm backend'
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
    if confine_keys = options['confine_to_keys']
      raise ArgumentError, '[hiera-aws-sm] confine_to_keys must be an array' unless confine_keys.is_a?(Array)

      begin
        confine_keys = confine_keys.map { |r| Regexp.new(r) }
      rescue StandardError => err
        raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Failed to create regexp with error #{err}"
      end
      re_match = Regexp.union(confine_keys)
      unless key[re_match] == key
        context.explain { "[hiera-aws-sm] Skipping secrets manager as #{key} doesn't match confine_to_keys" }
        context.not_found
      end
    end

    # Optional patterns to strip from keys prior to lookup
    if strip_from_keys = options['strip_from_keys']
      raise ArgumentError, '[hiera-aws-sm] strip_from_keys must be an array' unless strip_from_keys.is_a?(Array)

      strip_from_keys.each do |prefix|
        key = key.gsub(Regexp.new(prefix), '')
      end
    end

    # Handle prefixes if supplied
    if prefixes = options['prefixes']
      raise ArgumentError, '[hiera-aws-sm] prefixes must be an array' unless prefixes.is_a?(Array)
      if delimiter = options['delimiter']
        raise ArgumentError, '[hiera-aws-sm] delimiter must be a String' unless delimiter.is_a?(String)
      else
        delimiter = '/'
      end

      # Remove trailing delimters from prefixes
      prefixes = prefixes.map { |prefix| (prefix[prefix.length-1] == delimiter) ? prefix[0..prefix.length-2] : prefix }
      # Merge keys and prefixes
      keys = prefixes.map { |prefix| [prefix, key].join(delimiter) }
    else
      keys = [key]
    end

    result = nil

    # Query SecretsManager for the secret data, stopping once we find a match
    if result.nil?
      keys.each do |secret_key|
        result = get_secret(secret_key, options, context)
        unless result.nil?
          context.explain { "[hiera-aws-sm] Caching key #{key}" }
          context.cache(key, result)
          break
        end
      end
    end

    continue_if_not_found = options['continue_if_not_found'] || false

    if result.nil? and continue_if_not_found
      context.not_found
    end

    result
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
    # Return Cached Value if Present
    if context.cache_has_key(key)
      context.explain { "[hiera-aws-sm] Returning #{key} from cache..." }
      return context.cached_value(key)
    end

    # Allow Client Config Options Hash. Default to Empty Hash for Backwards Compatibility
    client_opts = options.key?('aws_client_options') ? options['aws_client_options'].transform_keys(&:to_sym) : {}

    # Allow Credential Loading From External File (Allowing for Easier Credential Rotation Outside of Puppet as Needed)
    # ref: https://github.com/aws/aws-sdk-ruby/blob/version-3/gems/aws-sdk-core/lib/aws-sdk-core/shared_credentials.rb
    if options.key?('shared_credentials')
      client_opts[:credentials] = Aws::SharedCredentials.new(options['shared_credentials'].transform_keys(&:to_sym))
    else
      client_opts[:access_key_id] = options['aws_access_key'] if options.key?('aws_access_key')
      client_opts[:secret_access_key] = options['aws_secret_key'] if options.key?('aws_secret_key')
    end

    client_opts[:region] = options['region'] if options.key?('region')

    secretsmanager = Aws::SecretsManager::Client.new(client_opts)

    response = nil
    secret = nil

    context.explain { "[hiera-aws-sm] Looking up #{key}" }
    begin
      response = secretsmanager.get_secret_value(secret_id: key)
    rescue Aws::SecretsManager::Errors::ResourceNotFoundException
      context.explain { "[hiera-aws-sm] No data found for #{key}" }
    rescue Aws::SecretsManager::Errors::UnrecognizedClientException
      raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Skipping backend. No permission to access #{key}"
    rescue Aws::SecretsManager::Errors::ServiceError => e
      raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Skipping backend. Failed to lookup #{key} due to #{e.message}"
    end

    unless response.nil?
      # rubocop:disable Style/NegatedIf
      if !response.secret_binary.nil?
        context.explain { "[hiera-aws-sm] #{key} is a binary" }
        secret = response.secret_binary
      else
        # Do our processing in here
        secret = process_secret_string(response.secret_string, options, context)
      end
      # rubocop:enable Style/NegatedIf
    end

    secret
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
  def process_secret_string(secret_string, _options, context)
    # Attempt to process this string as a JSON object
    begin
      result = JSON.parse(secret_string)
    rescue JSON::ParserError
      context.explain { '[hiera-aws-sm] Not a hashable result' }
      result = secret_string
    end

    result
  end
end
