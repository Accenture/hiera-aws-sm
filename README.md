
# hiera_aws_sm

#### Table of Contents

1. [Description](#description)
2. [Setup - The basics of getting started with hiera_aws_secrets_manager](#setup)
    * [What hiera_aws_secrets_manager affects](#what-hiera_aws_secrets_manager-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with hiera_aws_secrets_manager](#beginning-with-hiera_aws_secrets_manager)
3. [Usage - Configuration options and additional functionality](#usage)
4. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
5. [Limitations - OS compatibility, etc.](#limitations)
6. [Development - Guide for contributing to the module](#development)

## Description

Backend for Hiera 5 which allows lookups against Amazon Secrets Manager.

## Setup

### Setup Requirements **OPTIONAL**

Requires the `aws-sdk` gem to be installed and available to your
Puppetmaster.

```
package {'aws-sdk':
  ensure   => installed
  provider => puppetserver_gem
}
```

### Beginning with hiera_aws_sm

## Usage

The following is a reference of a Hiera hierarchy using hiera_aws_sm

## Reference

Users need a complete list of your module's classes, types, defined types providers, facts, and functions, along with the parameters for each. You can provide this list either via Puppet Strings code comments or as a complete list in the README Reference section.

* If you are using Puppet Strings code comments, this Reference section should include Strings information so that your users know how to access your documentation.

* If you are not using Puppet Strings, include a list of all of your classes, defined types, and so on, along with their parameters. Each element in this listing should include:

  * The data type, if applicable.
  * A description of what the element does.
  * Valid values, if the data type doesn't make it obvious.
  * Default value, if any.

## Limitations

This module is only compatible with Hiera 5 (Puppet 4.9+)

## Development


## Release Notes/Contributors/Etc. **Optional**



options:
 prefix: "myprefix"
 confine_to_keys:
   - key1
   - "^key2.*"
 continue_if_not_found: true
