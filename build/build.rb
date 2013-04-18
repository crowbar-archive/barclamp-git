#!/usr/bin/env ruby
require 'yaml'
require 'fileutils'

debug = true #if ENV['DEBUG']

repo_data = {}

def die(msg)
  STDERR.puts msg
  exit(1)
end

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

# Try n times to do something and then die if we cannot.
def repeat_unless repeats, message = nil, &block
  error = nil
  repeats.times do
    return if yield
  end
  die (message || "Could not do something!")
end

pip_cache_path = "#{ENV['BC_CACHE']}/files/pip_cache"
tmp_cache_path = "#{pip_cache_path}/all_pips"
#lets seek for pips in crowbar.yml
Dir.glob("#{ENV['CROWBAR_DIR']}/barclamps/*/crowbar.yml").each do |yml|
  data = YAML.load_file(yml)
  next if data["pips"].nil?
  FileUtils.mkdir_p(tmp_cache_path)
  FileUtils.mkdir_p(pip_cache_path)
  data["pips"].each do |pip_n|
    repeat_unless 2, "failed download pip #{pip_n}" do
      system "pip2tgz \"#{tmp_cache_path}\" \"#{pip_n}\""
    end
  end
  system "cp -a #{tmp_cache_path}/. #{pip_cache_path}"
  system "rm -fr #{tmp_cache_path}"
end


repo_data.each do |bc_name, repos|
  repos.each do |repo|
    repo.each do |repo_name, val|
      origin = val["origin"]
      branches = val["branches"]
      repos_path = "#{ENV['CACHE_DIR']}/barclamps/#{bc_name}/git_repos"
      tmp_cache_path = "#{pip_cache_path}/#{repo_name}"
      base_name ="#{repos_path}/#{repo_name}"
      die "Cannot find #{base_name}.tar.bz2" unless File.exists? "#{base_name}.tar.bz2"
      FileUtils.cd(repos_path) do %x(tar xf "#{repo_name}.tar.bz2") end
      die "failed to expand #{repo_name}" unless File.directory? "#{base_name}.git"
      puts ">>> #{repo_name}"
      FileUtils.cd("#{repos_path}/#{repo_name}.git") do
        branches = %x(git for-each-ref --format='%(refname)' refs/heads).split("\n").map{ |x| x.split("refs/heads/").last}
      end if branches.empty?
      FileUtils.cd(repos_path) do
        system "git clone #{repo_name}.git #{repo_name}"
        die "failed to create working tree of #{repo_name}" unless File.directory?(repo_name)
      end
      FileUtils.cd(base_name) do
        branches.each do |branch|
          puts "#{repo_name}: caching pip requires packages from #{branch}" if debug
          die "failed to checkout #{branch}" unless system "git checkout #{branch}"
          next unless File.exists? "tools/pip-requires"
          FileUtils.mkdir_p(tmp_cache_path)
          FileUtils.mkdir_p(pip_cache_path)
          #TODO(agordeev): remove that ugly workaround of pip failures on swift's folsom branch
          system "sed -i '/^https/c\-e git+https://github.com/openstack/python-swiftclient#egg=python-swiftclient' tools/pip-requires" if repo_name == "swift"
          #glanceclient 0.7.0 now(19.02.2013) seems broken so lets fall back to 0.5.1
          #system "sed -i 's|python-glanceclient.*$|python-glanceclient==0.6.0|g' tools/pip-requires"
          #nor 0.5.1 or 0.6.0 seems suitable for tempest so leaving it to python-glanceclient or tempest maintainers cause this bug affect only tempest
          #horizon seems broken with django 1.5, so lets try to freeze 1.4.5
          system "sed -i 's|Django[<>=]*.*$|Django==1.4.5|g' tools/pip-requires"
          puts "export PIP_SRC=#{tmp_cache_path}/_pip2tgz_temp/build && pip2tgz #{tmp_cache_path} -r tools/pip-requires"
          repeat_unless 2, "failed download pips for #{base_name}" do
            system("export PIP_SRC=#{tmp_cache_path}/_pip2tgz_temp/build && pip2tgz #{tmp_cache_path} -r tools/pip-requires")
          end
        end
      end
      system "rm -fr '#{base_name}'"
      puts "cleaning #{repo_name}.git" if debug
      system "rm -fr '#{repos_path}/#{repo_name}.git'"
      next unless File.directory?(tmp_cache_path)
      system "cp -a #{tmp_cache_path}/. #{pip_cache_path}"
      system "rm -fr #{tmp_cache_path}"
      # we should wrap only relative path for pips in repo
      # This cannot possibly work here.
      # system "sed -i 's|http://tarballs.openstack.org/oslo-config/oslo-config-2013.1b3.tar.gz#egg=oslo-config|oslo-config|g' tmp/tools/pip-requires"
    end
  end
end
if File.directory?(pip_cache_path)
  die "failed to package pip reqs" unless system("dir2pi #{pip_cache_path}")
end
puts "git repos staging is complete now" if debug
