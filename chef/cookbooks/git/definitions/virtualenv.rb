require 'find'

define :virtualenv, :action => :create, :where => nil, :owner => "root", :group => "root", :mode => 0755, :wrapped => [], :packages => {} do
  virtualenv_path = params[:where]
  if params[:action] == :create
    # Create VirtualEnv
    package("python-pip")
    package("python-virtualenv")
    puts "LOL"
    directory virtualenv_path do
      recursive true
      owner params[:owner]
      group params[:group]
      mode params[:mode]
    end
    execute "create virtualenv #{virtualenv_path}" do
      command "virtualenv #{virtualenv_path} --system-site-packages"
    end
    params[:packages].each do |package|
      pip = "#{virtualenv_path}/bin/pip"
      execute "{pip} install #{package} -> #{virtualenv_path}" do
        command "#{pip} install \"#{package}\""
        not_if "[ `#{pip} freeze | grep #{package}` ]"
      end
    end
  elsif params[:action] == :delete
    directory virtualenv_path do
      action :delete
      recursive true
    end
  end
end

define :virtualenv_wrapping, :where => nil, :to => "/usr/local/bin", :from => nil do
  if params[:where] and params[:from]
    env = File.join(params[:where],"bin")
    from = File.join(params[:from],"bin")
    to = params[:to]
    Find.find("#{from}/") do |file|
      next if FileTest.directory?(file)
      name = file.split("/").last
      template "#{to}/#{name}" do
        cookbook "git"
        source "virtualenv.erb"
        mode 0755
        owner "root"
        group "root"
        variables({
          :env => "#{env}",
          :from => "#{env}/#{name}",
          :to => "#{to}/#{name}"
        })
      end
    end
  else
    Chef::Log.fail "Not defined env or from params"
  end
end
