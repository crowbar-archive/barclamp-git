#!/usr/bin/env ruby
require 'yaml'
require 'fileutils'

pip_cache_path = "#{ENV['BC_CACHE']}/files/pip_cache"

barclamps = {}

pip_requires = ""

begin
  puts ">>> Starting build cache for barclamps"
  # Collect git_repo from all crowbar.yml
  Dir.glob("#{ENV['CROWBAR_DIR']}/barclamps/*/crowbar.yml").each do |file|
    crowbar = YAML.load_file(file)
    next if crowbar["git_repo"].nil? and crowbar["pips"].nil?
    barclamp = file.split("/")[-2]
    barclamps[barclamp] ||= []
    # add pips from crowbar.yml
    unless crowbar["pips"].nil?
      pip_requires += crowbar["pips"].join("\n")
    end
    # add barclamp for pip caching
    unless crowbar["git_repo"].nil?
      crowbar["git_repo"].each do |repo|
        (name,url,branches) = repo.split(" ", 3)
        barclamps[barclamp] << { name => {:origin => url, :branches => branches.split(" ")} }
      end
    end
  end

  # Run on each repos and collect pips from tools/pip-requires
  barclamps.each do |barclamp, repos|
    repos = repos.collect{|i| i.first}
    repos.each do |repo_name,repo|
      puts ">>> Collect pip requires from: #{repo_name} (#{repo[:branches].empty? ? "?" : repo[:branches].join(", ")})"
      # TODO: #"barclamps/#{barclamp}/git_repos")
      repos_path = "#{ENV['CACHE_DIR']}/barclamps/#{barclamp}/git_repos"
      base_name ="#{repos_path}/#{repo_name}"
      file = "#{base_name}.tar.bz2"
      raise "cannot find #{file}" unless File.exists? file
      FileUtils.cd(repos_path) do %x(tar xf "#{repo_name}.tar.bz2") end
      raise "failed to expand #{file}" unless File.directory? "#{base_name}.git"

      FileUtils.cd("#{repos_path}/#{repo_name}.git") do
        repo[:branches] = %x(git for-each-ref --format='%(refname)' refs/heads).split("\n").map{ |x| x.split("refs/heads/").last}
      end if repo[:branches].empty?

      FileUtils.cd(repos_path) do
        system("rm -rf #{repo_name}")
        unless system("git clone #{repo_name}.git #{repo_name}")
          raise "failed to clone repo #{repo_name}"
        end
      end

      repo[:branches].each do |branch|
        puts ">>> Branch: #{branch}"
        FileUtils.cd("#{repos_path}/#{repo_name}") do
          raise "failed to checkout #{branch}" unless system "git checkout #{branch}"
          next unless File.exists? "tools/pip-requires"

          #glanceclient 0.7.0 now(19.02.2013) seems broken so lets fall back to 0.5.1
          #system "sed -i 's|python-glanceclient.*$|python-glanceclient==0.6.0|g' tools/pip-requires"
          #nor 0.5.1 or 0.6.0 seems suitable for tempest so leaving it to python-glanceclient or tempest maintainers cause this bug affect only tempest
          #horizon seems broken with django 1.5, so lets try to freeze 1.4.5
          system "sed -i 's|Django[<>=]*.*$|Django==1.4.5|g' tools/pip-requires"

          pip_requires += File.read("tools/pip-requires") + "\n"
        end
      end
      FileUtils.cd(repos_path) do
        system("rm -rf #{repo_name}")
        system("rm -rf #{repo_name}.git")
      end
    end
  end

  pip_requires = pip_requires.split("\n").select{|i| not i.start_with?("#") and not i.strip.empty? }
  puts ">>> Total invoked packages: #{pip_requires.size}"
  pip_requires = pip_requires.uniq.sort
  puts ">>> Total unique packages: #{pip_requires.size}"

  system("mkdir -p #{pip_cache_path}")
  pip_requires.each do |pip|
    10.times do
      puts ">>> Try download pip: #{pip}"
      if system("pip2tgz #{pip_cache_path} '#{pip}'")
        break
      end
      puts ">>> Retry exec pip2tgz"
    end
  end
  if File.directory?(pip_cache_path)
    raise "failed to package pip reqs" unless system("dir2pi #{pip_cache_path}")
  end
  puts ">>> Success build cache pips packages for all barclamps"
rescue => e
  puts "!!! #{e.message}"
  exit(1)
end
