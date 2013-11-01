#!/usr/bin/env ruby
require 'yaml'
require 'fileutils'
require 'rubygems'

pip_cache_path = "#{ENV['BC_CACHE']}/files/pip_cache"

barclamps = {}
pip_requires = []
pip_options = []

def pip_downloaded?(pip, cache = "./")
  pip = pip.strip
  name, requires = pip.scan(/^([\w\.-]*)(.*)$/).flatten
  requires = requires.split(",")
  in_cache = false
  FileUtils.cd(cache) do
    packages = (Dir.glob("#{name}*") + Dir.glob("#{name.gsub('_','-')}*")).uniq
    versions = packages.collect{|package| package.scan(/([0-9a-zA-Z\.]+)\.tar\.gz/).flatten.first}
    begin
      in_cache = versions.select do |version|
        requires.select { |require| not Gem::Dependency.new(name,require.gsub(/[a-zA-Z]/,"")).match?(name,version.gsub(/[a-zA-Z]/,"")) }.empty?
      end.any?
    rescue
      in_cache = false
    end
  end
  in_cache
end


puts ">>> Starting build cache for barclamps"
# Collect git_repo from all crowbar.yml
Dir.glob("#{ENV['CROWBAR_DIR']}/barclamps/*/crowbar.yml").each do |file|
  crowbar = YAML.load_file(file)
  next if crowbar["git_repo"].nil? and crowbar["pips"].nil?
  barclamp = file.split("/")[-2]
  barclamps[barclamp] ||= []
  # add pips from crowbar.yml
  unless crowbar["pips"].nil?
    pip_requires += crowbar["pips"].collect{|i| i.strip}
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
        require_file = ["tools/pip-requires","requirements.txt"].select{|file| File.exist? file}.first
        next unless require_file
        File.read(require_file).split("\n").collect{|pip| pip.strip}.each do |line|
          if line.start_with?("-")
            pip_options << line
          elsif not line.start_with?("#")
            pip_requires << line
          end
        end
      end
    end
    FileUtils.cd(repos_path) do
      system("rm -rf #{repo_name}")
      system("rm -rf #{repo_name}.git")
    end
  end
end

pip_requires = pip_requires.select{|i| not i.strip.start_with?("#") and not i.strip.empty? }
puts ">>> Total invoked packages: #{pip_requires.size}"
pip_requires = pip_requires.uniq.sort
pip_options = pip_options.uniq.join(" ")
puts ">>> Total unique packages: #{pip_requires.size}"
puts ">>> Pip options: #{pip_options}" if pip_options.any?
puts ">>> Pips to download: #{pip_requires.join(", ")}"

system("mkdir -p #{pip_cache_path}")
pip_requires.each do |pip|
  10.times do |attempt|
    if pip_downloaded?(pip,pip_cache_path)
      puts ">>> Skip #{pip}, already in cache"
      break
    end
    puts ">>> Try download pip: #{pip} (attempt: #{attempt+1})"
    unless system("pip2tgz #{pip_cache_path} #{pip_options} '#{pip}'")
      if attempt >= 9
        exit(1)
      else
        puts ">>> Retry exec pip2tgz"
      end
    else
      break
    end
  end
end

if File.directory?(pip_cache_path)
  raise "failed to package pip reqs" unless system("dir2pi #{pip_cache_path}")
end
puts ">>> Success build pips cache"
