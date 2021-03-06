# Encoding: utf-8
#
# Cookbook Name:: elkstack
# Recipe:: secrets
#
# Copyright 2014, Rackspace
#

# if there's a data bag, get the contents out, shove them in node.run_state
lumberjack_data_bag = node['elkstack']['config']['lumberjack_data_bag']

unless lumberjack_data_bag
  Chef::Log.warn("node['elkstack']['config']['lumberjack_data_bag'] was set to false. Not configuring lumberjack or secrets.")
  return
end

# try an encrypted data bag first
lumberjack_secrets = nil
begin
  lumberjack_secrets = Chef::EncryptedDataBagItem.load(lumberjack_data_bag, 'secrets')
  lumberjack_secrets.to_hash # access it to force an error to be raised
rescue
  Chef::Log.warn("Could not find encrypted data bag item #{lumberjack_data_bag}/secrets")
  lumberjack_secrets = nil
end

# try an unencrypted databag next
if lumberjack_secrets.nil?
  begin
    lumberjack_secrets = Chef::DataBagItem.load(lumberjack_data_bag, 'secrets')
    lumberjack_secrets.to_hash
  rescue
    Chef::Log.warn("Could not find un-encrypted data bag item #{lumberjack_data_bag}/secrets")
    lumberjack_secrets = nil
  end
end

# now try to use the data bag
if !lumberjack_secrets.nil? && lumberjack_secrets['key'] && lumberjack_secrets['certificate']
  node.run_state['lumberjack_decoded_key'] = Base64.decode64(lumberjack_secrets['key'])
  node.run_state['lumberjack_decoded_certificate'] = Base64.decode64(lumberjack_secrets['certificate'])
elsif !lumberjack_secrets.nil?
  Chef::Log.warn('Found a data bag for lumberjack secrets, but it was missing \'key\' and \'certificate\' data bag items')
elsif lumberjack_secrets.nil?
  Chef::Log.warn('Could not find an encrypted or unencrypted data bag to use as a lumberjack keypair')
else
  Chef::Log.warn('Unable to complete lumberjack keypair configuration')
end

logstash_basedir = node.deep_fetch('logstash', 'instance_default', 'basedir')
attribute_name = "node['logstash']['instance_default']['basedir']"
err_msg = "#{attribute_name} was not set; please ensure you are using the racker/chef-logstash version until lusis/chef-logstash/pull/336 is merged"
fail err_msg unless logstash_basedir

# if we had overrode basedir value, we'd need to use the new value here too
file "#{logstash_basedir}/lumberjack.key" do
  content node.run_state['lumberjack_decoded_key']
  owner node['logstash']['instance_default']['user']
  group node['logstash']['instance_default']['group']
  mode '0600'
  not_if { node.run_state['lumberjack_decoded_key'].nil? }
end

# if we had overrode basedir value, we'd need to use the new value here too
file "#{logstash_basedir}/lumberjack.crt" do
  content node.run_state['lumberjack_decoded_certificate']
  owner node['logstash']['instance_default']['user']
  group node['logstash']['instance_default']['group']
  mode '0600'
  not_if { node.run_state['lumberjack_decoded_certificate'].nil? }
end
