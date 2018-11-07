
# hiera_aws_sm

#### Table of Contents

1. [Description](#description)
2. [Setup - The basics of getting started with hiera_aws_secrets_manager](#setup)
3. [Usage - Configuration options and additional functionality](#usage)
4. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
5. [Limitations - OS compatibility, etc.](#limitations)
6. [Development - Guide for contributing to the module](#development)

## Description

Backend for Hiera 5 which allows lookups against Amazon Secrets Manager.

Based on the design of [hiera-vault](https://github.com/davealden/hiera-vault/blob/master/lib/puppet/functions/hiera_vault.rb)

## Setup

Requires the `aws-sdk` gem to be installed and available to your
Puppetmaster.

```
package {'aws-sdk':
  ensure   => installed
  provider => puppetserver_gem
}
```

## Usage

The following is a reference of a Hiera hierarchy using hiera_aws_sm.

```
---

hierarchy:
  - name: "Hiera-AWS-SM lookup"
    lookup_key: hiera_aws_sm
    options:
      continue_if_not_found: false
      aws_access_key: <aws_access_key>
      aws_secret_key: <aws_secret_key>
      region: us-east-1
      delimiter: /
      prefixes: 
        - "%{::environment}/%{::trusted.certname}"
        - "%{::environment}/common/"
        - secret/puppet/%{::trusted.certname}/
        - secret/puppet/common/
      confine_to_keys:
        - '^aws_.*'

```

### Mandatory Option Keys

`name`: Human readable level name

`lookup_key`: Must be set to `hiera_aws_sm`

### Optional Option Keys

`continue_if_not_found`: Allow Puppet to lookup other data sources if the
key is not found in SecretsManager

`aws_access_key`: IAM access key to be used to connect to AWS. Should only
be used for Puppet masters running outside of AWS. Puppet masters running
within AWS should have their access to SecretsManager granted via IAM
roles.

`aws_secret_key`: IAM secret access key to be used to connect to AWS. 

`region`: AWS region to query against

`delimiter`: Character used to join prefixes and keys if specified.
Defaults to `/`. Not required if `prefixes` is not set.

`prefixes`: Optional array of prefixes to prepend to each lookup. For each
prefix, the function will perform a lookup of `[prefix, key].join(delimiter)` against
SecretsManager. This allows you to specify multiple paths in
SecretsManager for the function to explore, as described above.

`confine_to_keys`: List of regex expressions on which to search
SecretsManager. If specified, hiera_aws_sm will only query SecretsManager
for keys matching at least one specified regex. If none match, Puppet is
allowed to lookup against other data sources. 


## Limitations

This module is only compatible with Hiera 5 (Puppet 4.9+)

## Testing

```
pdk test unit
```

## Development

Author: David Hayes [d.hayes@accenture.com]

## License

See [LICENSE](LICENSE.md)

## Release Notes

## TBD

- Wrap secret values in Puppet's [sensitive data types](https://puppet.com/docs/puppet/5.5/lang_data_sensitive.html) in examples.
- Expand README on usage and installation

