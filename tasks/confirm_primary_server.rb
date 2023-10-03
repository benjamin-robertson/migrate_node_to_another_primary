#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

# Task to verify if the server its running on is in fact the Puppet Primary server

require 'open3'
require 'json'

def get_primary_hostname(ignore_infra_status_error)
  output, status = Open3.capture2('puppet infrastructure status')
  if ignore_infra_status_error == false
    if status.exitstatus != 0
      puts "puppet infrastructure status exited uncleanly #{status}"
      exit 1
    end
  end
  output.each_line do |line|
    if line.match(/^Primary: /)
      primary = line.gsub(/^Primary: /, '').lstrip.rstrip
      return [ primary, 'Primary' ]
    elsif line.match(/^Master: /)
      master = line.gsub(/^Master: /, '').lstrip.rstrip
      return [ master, 'Master' ]
    end
  end
  puts 'No Primary server found in output. Are you sure you specified the correct server as primary?'
  exit 1
end

# Get parameters
params = JSON.parse(STDIN.read)
ignore_infra_status_error = params['ignore_infra_status_error']
pe_primary_server = params['pe_primary_server']

# Get primary server hostname
primary = get_primary_hostname(ignore_infra_status_error)

# Confirm primary server matches
if primary[0] == pe_primary_server
  puts "#{primary[1]} server match successful"
  exit 0
else
  puts "Primary server did not match as expected, recieved #{primary} expected #{pe_primary_server}"
  exit 1
end
