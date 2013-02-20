#!/usr/bin/env ruby
require 'yaml'

debug = true #if ENV['DEBUG']
errs = []
at_exit { p errs.join("\n") if errs.length > 0}

retr_count=20
retr=0

def check_errors
  exit 2 if retr>=retr_count
end


repo_data = {}

attr_file = "#{ENV['CROWBAR_DIR']}/barclamps/git/chef/cookbooks/git/attributes/default.rb"

Dir.glob("#{ENV['CROWBAR_DIR']}/barclamps/*/crowbar.yml").each do |yml|
  data = YAML.load_file(yml)
  next if data["git_repo"].nil?
  bc_name = yml.split('barclamps/').last.split('/').first
  repo_data[bc_name] = []
  data["git_repo"].each do |repo|
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
     tmp_cache_path = "#{pip_cache_path}/#{repo_name}"
     system "mkdir -p #{repos_path}"
     system "mkdir -p #{pip_cache_path}"
     base_name ="#{repos_path}/#{repo_name}"
     if File.exists? "#{base_name}.tar.bz2"
       # it seems that pre-cloned repo is already existing
       p "updating repo #{repo_name} from #{origin}" if debug
       system "cd #{repos_path} && tar xf #{repo_name}.tar.bz2"
       errs << "failed to expand #{repo_name}" unless ::File.exists? "#{base_name}.git"
       p "fetching origin #{origin}" if debug 
       ret = system "cd #{base_name}.git && git fetch origin"
       errs << "failed to fetch #{base_name}" unless ret
     else
       p "cloning #{origin} to #{repo_name}.git" if debug
       ret = system "git clone --mirror #{origin} #{repos_path}/#{repo_name}.git"
       errs << "failed to clone #{base_name}" unless ret
     end
     if branches.empty?
       raw_data = `cd #{repos_path}/#{repo_name}.git && git for-each-ref --format='%(refname)' refs/heads`
       branches = raw_data.split("\n").map{|x| x.split("refs/heads/").last}
     end
     p "caching pip requires packages from branches #{branches.join(' ')}" if debug
     system "git clone #{repos_path}/#{repo_name}.git tmp"
     errs << "failed to create working tree of #{base_name}" unless ret
     if File.exists? "tmp/tools/pip-requires"
       branches.each do |branch|
         system "cd tmp && git checkout origin/#{branch}"
         if $?.exitstatus != 0
           # failed to checkout branch, checkouting tag instead
           system "cd tmp && git checkout #{branch}"
           errs << "failed to checkout #{branch}" if $?.exitstatus != 0
         end         
         system "mkdir -p #{tmp_cache_path}"
         #TODO(agordeev): remove that ugly workaround of pip failures on swift's folsom branch
         system "sed -i '/^https/c\-e git+https://github.com/openstack/python-swiftclient#egg=python-swiftclient' tmp/tools/pip-requires" if repo_name == "swift"
         #glanceclient 0.7.0 now(19.02.2013) seems broken so lets fall back to 0.5.1
         #system "sed -i 's|python-glanceclient.*$|python-glanceclient==0.6.0|g' tmp/tools/pip-requires"
         #nor 0.5.1 or 0.6.0 seems suitable for tempest so leaving it to python-glanceclient or tempest maintainers cause this bug affect only tempest
         while system("export PIP_SRC=#{tmp_cache_path}/_pip2tgz_temp/build && pip2tgz #{tmp_cache_path} -r tmp/tools/pip-requires")!=0 and retr<retr_count
           retr += 1
           errs << "failed download pips for #{base_name}"
         end
         system "cp -a #{tmp_cache_path}/. #{pip_cache_path}"
         system "rm -fr #{tmp_cache_path}"
       end
     end
     system "rm -fr tmp"
     while system("dir2pi #{pip_cache_path}")!=0 and retr<retr_count
       retr += 1
       errs << "failed to package pip reqs" unless ret
     end
     p "packing #{repo_name}.git to #{repo_name}.tar.bz2" if debug
     system "cd #{repos_path} && tar cjf #{repo_name}.tar.bz2 #{repo_name}.git/"
     p "cleaning #{repo_name}.git" if debug
     system "rm -fr #{repos_path}/#{repo_name}.git"
   end
  end
end
check_errors
p "git repos staging is complete now" if debug
