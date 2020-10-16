require 'logger'

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

    # Handle prefixes if suplied
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

    # Query SecretsManager for the secret data, stopping once we find a match
    result = nil
    keys.each do |secret_key|
      result = get_secret(secret_key, options, context)
      unless result.nil?
        break
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
    client_opts = {}
    client_opts[:access_key_id] = options['aws_access_key'] if options.key?('aws_access_key')
    client_opts[:secret_access_key] = options['aws_secret_key'] if options.key?('aws_secret_key')
    client_opts[:region] = options['region'] if options.key?('region')
    
    log = Logger.new(STDOUT)
    case options['log_level']
    when 'info'
      log.level = Logger::INFO
    when 'warn'
      log.level = Logger::WARN    
    when 'debug'
      log.level = Logger::DEBUG
    else
      log.level = Logger::ERROR
    end
    secretsmanager = Aws::SecretsManager::Client.new(client_opts)

    response = nil
    secret = nil

    context.explain { "[hiera-aws-sm] Looking up #{key}" }
    begin
      secret_formatted = key.gsub('::', '/')
      response = secretsmanager.get_secret_value(secret_id: secret_formatted)
      log.info("[hiera-aws-sm] secret #{key} provided by #{secret_formatted}")
    rescue Aws::SecretsManager::Errors::ResourceNotFoundException
      context.explain { "[hiera-aws-sm] No data found for #{key}" }
      if key.include? "common"
        log.warn("[hiera-aws-sm] secret #{key} not found in SM")
      else
        log.info("[hiera-aws-sm] secret #{key} not found in SM")
      end
    rescue Aws::SecretsManager::Errors::UnrecognizedClientException
      raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Skipping backend. No permission to access #{key}"
    rescue Aws::SecretsManager::Errors::ServiceError => e
      if e.message == 'You can\'t perform this operation on the secret because it was marked for deletion.' then
        context.explain { "[hiera-aws-sm] #{key} found but scheduled for deletion" }
        log.info("[hiera-aws-sm] #{key} found but scheduled for deletion")
      else
        raise Puppet::DataBinding::LookupError, "[hiera-aws-sm] Skipping backend. Failed to lookup #{key} due to #{e.message}"
      end
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
