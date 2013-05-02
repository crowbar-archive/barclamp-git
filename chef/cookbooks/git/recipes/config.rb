#
# Cookbook Name:: git
# Recipe:: config
#
# Copyright 2011, Dell, Inc.
# Copyright 2012, Dell, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

git_username = "git"
home_dir = "/home/#{git_username}"
dst_dir = "/tmp"

user git_username do
  comment "Git user"
  home home_dir
  shell "/usr/bin/git-shell"
end

directory home_dir do
  owner git_username
  group git_username
end

directory "#{home_dir}/.ssh" do
  owner git_username
  group git_username
end

ssh_keys = []

all_nodes = search(:node, "*:*")
all_nodes.each do |a_node|
  #agordeev: This is work around to avoid inconsistency
  # among node[:crowbar][:ssh][:root_pub_key] attributes
  # but it works only if git be deployed on admin node
  ssh_keys << %x{ssh root@#{a_node[:fqdn]} cat /root/.ssh/id_rsa.pub}.strip
end

template "#{home_dir}/.ssh/authorized_keys" do
  source "authorized_keys.erb"
  owner git_username
  variables :key_list => ssh_keys
end

provisioner = search(:node, "roles:provisioner-server").first
proxy_addr = provisioner[:fqdn]
proxy_port = provisioner[:provisioner][:web_port]

data_bag("barclamps").each do |bc|
  data_bag_item("barclamps",bc).each do |k,v|
    next unless k == "git_repo"
    node[:git] ||= Mash.new
    node[:git][:repo_data] ||= Mash.new
    node[:git][:repo_data][bc] = Array.new
    v.each do |repo|
      repo_name, repo_url, branches = repo.split(' ',3)
      branches = branches.split
      node[:git][:repo_data][bc] << {repo_name => {"origin" => repo_url, "branches" => branches}}
      file_url = "http://#{proxy_addr}:#{proxy_port}/git_repos/#{bc}/#{repo_name}.tar.bz2"
      file_path = "#{dst_dir}/#{bc}/#{repo_name}.tar.bz2"
      repo_dir = "#{home_dir}/#{bc}/#{repo_name}.git"
      directory "#{dst_dir}/#{bc}" do
        owner git_username
      end
      remote_file file_url do
        source file_url
        path file_path
        owner git_username
        action :create_if_missing
        # If we cannot download the file we will just skip to the nest one.
        ignore_failure true
      end
      directory "#{home_dir}/#{bc}" do
        owner git_username
        group git_username
      end 
      execute "untar_#{repo_name}.tar.bz2" do
        cwd "#{home_dir}/#{bc}"
        user git_username
        command "tar xf #{file_path}"
        creates repo_dir
        only_if do File.exists? file_path end
      end
      execute "git_fetch_#{repo_url}" do
        command "git fetch origin"
        cwd repo_dir
        user git_username
        only_if do
          if node[:git][:update_origins] && File.directory?(repo_dir)
            require 'ping'
            if repo_url.include?('@')
              repo_host = repo_url.split('@')[1].split(':').first
            else
              repo_host = repo_url.split('/')[2]
            end
            begin
              Ping.pingecho repo_host, 5
            rescue Exception => msg
              false
            end
          else
            false
          end
        end
      end
    end
  end
end
node.save
