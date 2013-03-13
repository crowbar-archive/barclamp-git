#!/usr/bin/env ruby
require 'yaml'

debug = true #if ENV['DEBUG']
@errs = []
at_exit { puts @errs.join("\n") if @errs.length > 0}

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

p repo_data if debug
             # populate git cookbook attributes
File.open(attr_file, 'w') {|f| f.write("default[:git][:repo_data] = #{repo_data.inspect}") }

# method try repeat execute code and if can't done he generate exception
def repeat_unless repeats, message = nil, &block
  error = nil
  repeats.times do
    begin
      raise (message || "execute a command failed") unless yield
      break
    rescue => error
    end
  end
  @errs << error.to_s
end

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
        puts "updating repo #{repo_name} from #{origin}" if debug
        system "cd #{repos_path} && tar xf #{repo_name}.tar.bz2"
        @errs << "failed to expand #{repo_name}" unless ::File.exists? "#{base_name}.git"
        puts "fetching origin #{origin}" if debug
        ret = system "cd #{base_name}.git && git fetch origin"
        @errs << "failed to fetch #{base_name}" unless ret
      else
        puts "cloning #{origin} to #{repo_name}.git" if debug
        repeat_unless 10, "failed to clone #{base_name}" do
          system "git clone --mirror #{origin} #{repos_path}/#{repo_name}.git"
        end
      end
      puts ">>> #{repo_name}"
      if branches.empty?
        raw_data = `cd #{repos_path}/#{repo_name}.git && git for-each-ref --format='%(refname)' refs/heads`
        branches = raw_data.split("\n").map{|x| x.split("refs/heads/").last}
      end
      puts "caching pip requires packages from branches #{branches.join(' ')}" if debug
      repeat_unless 10, "failed to create working tree of #{base_name}" do
        system "git clone #{repos_path}/#{repo_name}.git tmp"
      end
      if File.exists? "tmp/tools/pip-requires"
        branches.each do |branch|
          puts ">>> #{branch}"
          system "cd tmp && git checkout #{branch}"
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
          #horizon seems broken with django 1.5, so lets try to freeze 1.4.5
          system "sed -i 's|Django[<>=]*.*$|Django==1.4.5|g' tmp/tools/pip-requires"
          repeat_unless 10, "failed download pips for #{base_name}" do
            puts "export PIP_SRC=#{tmp_cache_path}/_pip2tgz_temp/build && pip2tgz #{tmp_cache_path} -r tmp/tools/pip-requires"
            system("export PIP_SRC=#{tmp_cache_path}/_pip2tgz_temp/build && pip2tgz #{tmp_cache_path} -r tmp/tools/pip-requires")
          end
          system "cp -a #{tmp_cache_path}/. #{pip_cache_path}"
          system "rm -fr #{tmp_cache_path}"
        end
      end
      system "rm -fr tmp"
      repeat_unless 10, "failed to package pip reqs" do
        system("dir2pi #{pip_cache_path}")
      end
      puts "packing #{repo_name}.git to #{repo_name}.tar.bz2" if debug
      system "cd #{repos_path} && tar cjf #{repo_name}.tar.bz2 #{repo_name}.git/"
      puts "cleaning #{repo_name}.git" if debug
      system "rm -fr #{repos_path}/#{repo_name}.git"
    end
  end
end
exit 2 if @errs.any?
puts "git repos staging is complete now" if debug
