#!/usr/bin/env ruby
require 'yaml'

debug = true #if ENV['DEBUG']

repo_data = {}

attr_file = "#{ENV['CROWBAR_DIR']}/barclamps/git/chef/cookbooks/git/attributes/default.rb"

Dir.glob("#{ENV['CROWBAR_DIR']}/barclamps/*/crowbar.yml").each do |yml|
  data = YAML.load_file(yml)
  next if data["git"].nil?
  bc_name = yml.split('barclamps/').last.split('/').first
  repo_data[bc_name] = []
  data["git"].each do |repo|
    repo_name, origin = repo.split(' ')
    branches = repo.split(' ').drop(2) || []
    repo_data[bc_name] << { repo_name => {"origin" => origin, "branches" => branches } }
  end
end

p repo_data.inspect if debug
# populate git cookbook attributes
File.open(attr_file, 'w') {|f| f.write("default[:git][:repo_data] = #{repo_data.inspect}") }

repo_data.each do |bc_name, repos|
  repos.each do |repo|
   repo.each do |repo_name, val|
     origin = val["origin"]
     branches = val["branches"]
     repos_path = "#{ENV['BC_CACHE']}/files/git_repos/#{bc_name}"
     pip_cache_path = "#{ENV['BC_CACHE']}/files/pip_cache"
     system "mkdir -p #{repos_path}"
     system "mkdir -p #{pip_cache_path}"
     if File.exists? "#{repos_path}/#{repo_name}.tar.bz2"
       # it seems that pre-cloned repo is already existing
       p "updating repo #{repo_name} from #{origin}" if debug
       system "cd #{repos_path} && tar xf #{repo_name}.tar.bz2"
       p "fetching origin #{origin}" if debug 
       system "cd #{repos_path}/#{repo_name}.git && git fetch origin"
     else
       p "cloning #{origin} to #{repo_name}.git" if debug
       system "git clone --mirror #{origin} #{repos_path}/#{repo_name}.git"
     end
     if branches.empty?
       raw_data = `cd #{repos_path}/#{repo_name}.git && git for-each-ref --format='%(refname)' refs/heads`
       branches = raw_data.split("\n").map{|x| x.split("refs/heads/").last}
     end
     p "caching pip requires packages from branches #{branches.join(' ')}" if debug
     system "git clone #{repos_path}/#{repo_name}.git tmp"
     if File.exists? "tmp/tools/pip-requires"
       branches.each do |branch|
         system "cd tmp && git checkout origin/#{branch}"
         system "pip2tgz #{pip_cache_path} -r tmp/tools/pip-requires"
       end
     end
     system "rm -fr tmp"
     system "dir2pi #{pip_cache_path}"
     p "packing #{repo_name}.git to #{repo_name}.tar.bz2" if debug
     system "cd #{repos_path} && tar cjf #{repo_name}.tar.bz2 #{repo_name}.git/"
     p "cleaning #{repo_name}.git" if debug
     system "rm -fr #{repos_path}/#{repo_name}.git"
   end
  end
end

p "git repos staging is complete now" if debug
