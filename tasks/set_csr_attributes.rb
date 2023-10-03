#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

# Task whichs recreates the csr_attributes on a system from the existing certificate and merges a new set of trusted fact.
# Writes out a new CSR preservering any custom_attributes set.

require 'open3'
require 'puppet'
require 'openssl'
require 'yaml'
require 'json'

def get_cert_location
  if Gem.win_platform?
    command = "'C:\\Program Files\\Puppet Labs\\Puppet\\bin\\puppet.bat' config print hostcert"
  else
    command = '/opt/puppetlabs/bin/puppet config print hostcert'
  end
  output, status = Open3.capture2(command)
  if status.exitstatus != 0
    puts "failed to get cert location from puppet config command #{status}"
    exit 1
  end
  output.lstrip!
  output.rstrip!
end

def read_trusted_facts(cert_location, trusted_facts_oid)
  trusted_fact_results = {}
  cert_data = File.open cert_location
  certificate = OpenSSL::X509::Certificate.new cert_data
  certificate.extensions.each do |element|
    trusted_facts_oid.each do |name, oid|
      if element.oid == name or element.oid == oid
        trusted_fact_results[name] = element.value.to_s.gsub(/^\.\n/, '').gsub(/^\../, '')
      end
    end
  end
  trusted_fact_results
end

# set all known trusted facts
trusted_facts_oid = { 'pp_uuid' => '1.3.6.1.4.1.34380.1.1.1', 'pp_instance_id' => '1.3.6.1.4.1.34380.1.1.2', 'pp_image_name' => '1.3.6.1.4.1.34380.1.1.3', 'pp_preshared_key' => '1.3.6.1.4.1.34380.1.1.4', 'pp_cost_center' => '1.3.6.1.4.1.34380.1.1.5', 'pp_product' => '1.3.6.1.4.1.34380.1.1.6', 'pp_project' => '1.3.6.1.4.1.34380.1.1.7', 'pp_application' => '1.3.6.1.4.1.34380.1.1.8', 'pp_service' => '1.3.6.1.4.1.34380.1.1.9', 'pp_employee' => '1.3.6.1.4.1.34380.1.1.10', 'pp_created_by' => '1.3.6.1.4.1.34380.1.1.11', 'pp_environment' => '1.3.6.1.4.1.34380.1.1.12', 'pp_role' => '1.3.6.1.4.1.34380.1.1.13', 'pp_software_version' => '1.3.6.1.4.1.34380.1.1.14', 'pp_department' => '1.3.6.1.4.1.34380.1.1.15', 'pp_cluster' => '1.3.6.1.4.1.34380.1.1.16', 'pp_provisioner' => '1.3.6.1.4.1.34380.1.1.17', 'pp_region' => '1.3.6.1.4.1.34380.1.1.18', 'pp_datacenter' => '1.3.6.1.4.1.34380.1.1.19', 'pp_zone' => '1.3.6.1.4.1.34380.1.1.20', 'pp_network' => '1.3.6.1.4.1.34380.1.1.21', 'pp_securitypolicy' => '1.3.6.1.4.1.34380.1.1.22', 'pp_cloudplatform' => '1.3.6.1.4.1.34380.1.1.23', 'pp_apptier' => '1.3.6.1.4.1.34380.1.1.24', 'pp_hostname' => '1.3.6.1.4.1.34380.1.1.25' }

def csr_attribute_location
  if Gem.win_platform?
    'C:/ProgramData/PuppetLabs/puppet/etc/csr_attributes.yaml'
  else
    '/etc/puppetlabs/puppet/csr_attributes.yaml'
  end
end

def get_existing_csr(csr_attr_file_location)
  if File.exist?(csr_attr_file_location)
    begin
      data = YAML.safe_load(File.read(csr_attr_file_location))
    rescue => exception
      nil
    end
  else
    nil
  end
end

def merge_facts(existing_csr, new_trusted_facts)
  if existing_csr.keys.include?('extension_requests')
    combined_facts = existing_csr['extension_requests'].merge(new_trusted_facts)
    existing_csr['extension_requests'] = combined_facts
    existing_csr
  else
    existing_csr['extension_requests'] = {}
    combined_facts = existing_csr['extension_requests'].merge(new_trusted_facts)
    existing_csr['extension_requests'] = combined_facts
    existing_csr
  end
end

# Get certificate location
cert_location = get_cert_location

# Read trusted facts from certificate.
existing_facts = read_trusted_facts(cert_location, trusted_facts_oid)

# Get csr file location
csr_attr_file_location = csr_attribute_location

# Load existing rules
existing_csr = get_existing_csr(csr_attr_file_location)

# set existing facts, if csr attributes is nil. Create an new hash otherwise add to existing
if existing_csr == nil
  existing_csr = { 'extension_requests' => existing_facts }
else
  existing_csr['extension_requests'] = existing_facts
end

params = JSON.parse(STDIN.read)
new_trusted_facts = params['trusted_facts']
preserve_existing_facts = params['preserve_existing_facts']
# new_trusted_facts = {'pp_role' => 'doge', 'pp_environment' => 'dog', 'pp_department' => 'blah', 'pp_datacenter' => 'louie'}

puts "Existing facts are #{existing_csr}"
puts "New facts are #{new_trusted_facts}"

# Merge the hash
if existing_csr == nil or preserve_existing_facts == false
  merged_csr = { 'extension_requests' => new_trusted_facts }
else
  merged_csr = merge_facts(existing_csr, new_trusted_facts)
end

puts "Combined hash is #{merged_csr}"

File.write(csr_attr_file_location, merged_csr.to_yaml)
