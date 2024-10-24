# @summary PE plan to migrate nodes to another PE server
# 
# lint:ignore:140chars
#
# @param origin_pe_primary_server Puppet Primary server the node is being migrated from. Must match Primary server FQDN(Certname). Use to purge migrated nodes.
# @param target_pe_address Target Puppet server, either compiler address or FQDN of Primary server. Use array to specific multiple compilers.
# @param targets The targets to run on (note this must match the certnames used by Puppet / shown in PE console).
#    NOTE: you may ONLY specify target or fact_value. Specifying both will cause the plan to fail.
# @param fact_name Fact name to match nodes by.
# @param fact_value Fact value the fact must match.
#    NOTE: you may ONLY specify target or fact_value. Specifying both will cause the plan to fail.
# @param noop Run the plan in noop mode. Make no changes.
# @param bypass_connectivity_check Do not check for connectivity to target PE server.
#
plan migrate_nodes::migrate_node (
  Variant[String,Array] $target_pe_address,
  String                $origin_pe_primary_server  = undef,
  Optional[TargetSpec]  $targets                   = undef,
  Optional[String]      $fact_name                 = undef,
  Optional[String]      $fact_value                = undef,
  Boolean               $ignore_infra_status_error = false,
  Boolean               $noop                      = false,
  Boolean               $bypass_connectivity_check = false,
) {
  # check to ensure both fact value and target are not yet. Fail plan if so.
  if $targets != undef and $fact_value != undef {
    fail('Cannot set both target and existing_fact_value.')
  }

  if $fact_value != undef and $fact_name == undef {
    fail('Must set a fact_name if setting a fact_value.')
  }

  if $fact_value != undef {
    $puppetdb_results = puppetdb_query("inventory[certname] { facts.${fact_name} = \"${fact_value}\" }")
    $full_list = $puppetdb_results.map | Hash $node | { $node['certname'] }
  } elsif $targets != undef {
    $full_list = get_targets($targets)
  } else {
    fail('Target and fact_name are both unset.')
  }

  unless $full_list.empty {
    # Check connection to hosts. run_plan does not exit cleanly if there is a host which doesnt exist or isnt connected, We use this task
    # to check if hosts are valid and have a valid connection to PE. 
    $factresults = run_task(enterprise_tasks::test_connect, $full_list, _catch_errors => true)

    $full_list_failed = $factresults.error_set.names
    $full_list_success = $factresults.ok_set.names

    # Update facts
    without_default_logging() || { run_plan(facts, targets => $full_list_success) }

    # supported platforms
    $supported_platforms = ['Debian', 'RedHat', 'windows']

    $supported_targets = get_targets($full_list_success).filter | $target | {
      $target.facts['os']['family'] in $supported_platforms
    }
    # remove any pe servers from targets, we dont support migrating puppet enterprise components.
    $remove_any_pe_targets = get_targets($supported_targets).filter | $target | {
      $target.facts['is_pe'] == false
    }

    out::message("Supported targets are ${remove_any_pe_targets}")

    # Get primary server
    if $origin_pe_primary_server == undef {
      $pe_status_results = puppetdb_query('inventory[certname] { facts.pe_status_check_role = "primary" }')
      if $pe_status_results.length != 1 {
        fail("Could not identify the primary server. Confirm pe_status_check_role fact is working correctly. Alternatively the priamry server can be set via the pe_primary_server parameter. Results: ${pe_role_results}")
      } else {
        # We found a single primary server :)
        $pe_target_certname = $pe_status_results.map | Hash $node | { $node['certname'] }
        $origin_pe_primary_target = get_target($pe_target_certname)
      }
    } else {
      $origin_pe_primary_target = get_target($origin_pe_primary_server)
    }

    $windows_hosts = get_targets($remove_any_pe_targets).filter | $target | {
      $target.facts['os']['name'] == 'windows'
    }

    # Enable long file path support on Windows.
    run_task('migrate_nodes::set_long_paths_windows', $windows_hosts,
      '_noop'          => $noop,
    '_catch_errors'  => true )

    # Confirm the origin_pe_primary_server provided is in fact the Primary server for this Puppet installation.
    $confirm_pe_primary_server_results = run_task('migrate_nodes::confirm_primary_server', $origin_pe_primary_target,
      'pe_primary_server'         => $origin_pe_primary_target.name,
      'ignore_infra_status_error' => $ignore_infra_status_error,
    '_catch_errors'               => true )
    $ok_set_length = length("${confirm_pe_primary_server_results.ok_set}")
    if length("${confirm_pe_primary_server_results.ok_set}") <= 2 {
      fail_plan("Primary server provided not the primary server for this Puppet Enterprise installation: ${pe_server_target.name} ")
    }

    # Check if target pe address is an array. If so we test the first address only.
    if $target_pe_address =~ Array {
      $target_pe_first_address = $target_pe_address[0]
      $target_pe_merged = join($target_pe_address, ', ')
    } else {
      # We are a string
      $target_pe_first_address = $target_pe_address
      $target_pe_merged = $target_pe_address
    }

    # Test connection to new PE server
    $connection_check_results = run_task('migrate_nodes::check_pe_connection', $remove_any_pe_targets, { 'target_pe_server' => $target_pe_first_address, 'bypass_connectivity_check' => $bypass_connectivity_check, '_catch_errors' => true })
    $successful_connection_test_targets = $connection_check_results.ok_set.names
    $failed_connection_test_targets = $connection_check_results.error_set.names

    # Generate new csr file for host.
    $set_csr_attriubes_results = run_task('migrate_nodes::set_csr_attributes', $successful_connection_test_targets,
      'trusted_facts'           => {},
      'preserve_existing_facts' => true,
    '_catch_errors'             => true )
    $set_csr_attriubes_done = $set_csr_attriubes_results.ok_set
    $set_csr_attriubes_done_names = $set_csr_attriubes_results.ok_set.names
    $set_csr_attriubes_failed = $set_csr_attriubes_results.error_set.names
    $set_csr_attriubes_successful_targets = $successful_connection_test_targets - get_targets(set_csr_attriubes_failed)

    # Update Puppet.conf
    $update_puppet_config_results = apply($set_csr_attriubes_successful_targets,
      '_description' => "Apply block: update Puppet agent settings (noop: ${noop})",
      '_catch_erros' => true,
    '_noop'          => $noop) {
      if $facts['os']['family'] == 'Windows' {
        $puppet_conf = 'C:\ProgramData\PuppetLabs\puppet\etc\puppet.conf'
      } else {
        $puppet_conf = '/etc/puppetlabs/puppet/puppet.conf'
      }

      ini_setting { 'set server_list':
        ensure  => present,
        path    => $puppet_conf,
        section => 'main',
        setting => 'server_list',
        value   => $target_pe_merged,
      }

      ini_setting { 'remove server main option':
        ensure  => absent,
        path    => $puppet_conf,
        section => 'main',
        setting => 'server',
        require => Ini_setting['set server_list'],
      }

      ini_setting { 'remove server agent option':
        ensure  => absent,
        path    => $puppet_conf,
        section => 'agent',
        setting => 'server',
      }

      ini_setting { 'remove server_list agent option':
        ensure  => absent,
        path    => $puppet_conf,
        section => 'agent',
        setting => 'server_list',
      }
    }
    $successful_update_puppet_config = $update_puppet_config_results.ok_set.names
    $failed_update_puppet_config = $update_puppet_config_results.error_set.names

    # Clear ssl certs
    $clear_ssl_cert_results = run_task('migrate_nodes::clear_ssl_certs', $successful_update_puppet_config, { '_catch_errors' => true, '_noop' => $noop, 'noop' => $noop })
    $successful_clear_ssl_cert = $clear_ssl_cert_results.ok_set.names
    $failed_clear_ssl_cert = $clear_ssl_cert_results.error_set.names

    # Purge nodes on PE master
    $origin_pe_target = get_targets($origin_pe_primary_server)
    $node_to_purge = $successful_clear_ssl_cert.reduce | String $orig, String $node | { "${orig} ${node} " }
    out::message("Nodes to purge are: ${node_to_purge}")
    if $node_to_purge != undef {
      if $noop != true {
        run_command("puppet node purge ${node_to_purge}", $origin_pe_target)
      }
    }

    $original_full_list_failed = defined('$full_list_failed') ? {
      true    => $full_list_failed,
      default => {},
    }
    $original_connection_test_failed = defined('$failed_connection_test_targets') ? {
      true    => $failed_connection_test_targets,
      default => {},
    }
    $original_set_csr_attriubes_failed = defined('$set_csr_attriubes_failed') ? {
      true    => $set_csr_attriubes_failed,
      default => {},
    }
    $original_failed_update_puppet_config = defined('$failed_update_puppet_config') ? {
      true    => $failed_update_puppet_config,
      default => {},
    }
    $original_failed_clear_ssl_cert = defined('$failed_clear_ssl_cert') ? {
      true    => $failed_clear_ssl_cert,
      default => {},
    }

    if $supported_targets.empty {
      $plan_result = 'fail'
    } else {
      if $supported_targets.length == $successful_clear_ssl_cert.length {
        $plan_result = 'success'
      } else {
        $plan_result = 'fail'
      }
    }

    $summary_results = {
      'all_nodes'                    => $full_list,
      'failed_or_non_existent_nosts' => $original_full_list_failed,
      'pe_connection_check_failed'   => $original_connection_test_failed,
      'set_csr_attributes_failed'    => $original_set_csr_attriubes_failed,
      'failed_update_puppet_config'  => $original_failed_update_puppet_config,
      'failed_clear_ssl_cert'        => $original_failed_clear_ssl_cert,
    }

    if ( $plan_result == 'fail' ) {
      fail_plan('Plan fail on some or all nodes', 'errors-found', { 'result' => $summary_results })
    } else {
      return($summary_results)
    }
  }
  else {
    fail('No valid nodes specified')
  }
}

# lint:endignore
