# migrate_nodes

Module containing a plan to migrate nodes from one Puppet Primary server to another. Useful for migrations.

## Table of Contents

1. [Description](#description)
1. [Setup - The basics of getting started with migrate_nodes](#setup)
    * [What migrate_nodes affects](#what-migrate_nodes-affects)
    * [Beginning with migrate_nodes](#beginning-with-migrate_nodes)
1. [Usage - Configuration options and additional functionality](#usage)
1. [Limitations - OS compatibility, etc.](#limitations)
1. [Development - Guide for contributing to the module](#development)

## Description

There is currently no fully automated process to migrate Puppet nodes between Puppet Primary servers. This plan automates the process while preserving trusted facts contained on the nodes certificate.

## Setup

### What migrate_nodes affects

This modules plan affects the following

* Enables long file path support for Windows
* Updates csr_attributes.yaml with facts currently present on the agent certificate.
* Reconfigures puppet.conf on target nodes to point to the target Puppet primary.
* Deletes local agent certificate and ca.pem file.
* Reboots Puppet service on target.
* Purges target node from source primary server.

**Warning:** Do not migrate Puppet infrastructure components. This will break your Puppet installation. A built in check has been included to avoid this situation which relies on the 'is_pe' fact.

### Beginning with migrate_nodes

Include the module within your Puppetfile. 

`mod 'benjaminrobertson-migrate_nodes'`

## Usage

Run the plan **migrate_nodes::migrate_node** from the Puppet Enterprise console.

**Required parameters**
- origin_pe_primary_server (String - Puppet Primary server the node is being migrated from. Must match Primary server FQDN(Certname))
- target_pe_address (Array/Sting - either compiler address or FQDN of Primary server. Use array to specify multiple compilers.)

**Optional parameters**
- targets (TargetSpec - [see here](https://www.puppet.com/docs/bolt/latest/bolt_types_reference.html#targetspec))
- fact_name (String)
- fact_value (String)
- ignore_infra_status_error (Boolean - Ignore errors from puppet infrastructure status command. May allow the plan to operate if some Puppet infrastructure components are failing)
- bypass_connectivity_check (Boolean - Do not perform connectivity check to target Primary server)
- noop (Boolean - Run the plan in noop. csr_attributes.yaml will still be generated, however nodes will not be migrated.)

**Note:** Either targets or fact_name/fact_value must be specified. Cannot specify both.

To specific a trusted fact, use fact_name = `trusted.extensions.pp_role`.

## Limitations

Verified with the following OS\Primary combinations. 

Puppet Enterprise

* 2021.7.6

Puppet Nodes

* Windows 2019
* RHEL 8
* RHEL 9

Expected to work for all Windows 2016 or later, Enterprise Linux, Debian, Ubuntu versions.

Expected to work with all modern Puppet Enterprise releases.

## Development

If you find any issues with this module, please log them in the issues register of the GitHub project. [Issues][1]

PR glady accepted :)

[1]: https://github.com/benjamin-robertson/migrate_nodes/issues