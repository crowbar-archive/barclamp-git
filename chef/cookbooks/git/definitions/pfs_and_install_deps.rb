define :pfs_and_install_deps, :action => :create, :virtualenv => nil, :repo => nil, :system_site => false do
  #params:
  #  name: name of component to be installed in pull-from-source mode
  #  virtualenv: install using virtualenv if true
  #  wrap_bins ["<bin name>","<bin name>", ...]: create wrap for binaries
  #  path: path on the node's filesystem to clone git repo to [default: /opt/#{comp_name} ]
  #  cookbook: name of cookbook to use for pull-from-source [default: current cookbook ]
  #  cnode: node where all the pull-from-source attributes related to the current proposal are [default: current node ]
  #  reference: git_refspec (branch/tag/commit id) for the code check out 
  #    by default uses `git_refspec` from `cookbook`'s proposal which was applied to `cnode`
  #    actually used only to deploy keystone libs for glance/nova/horizon/cinder

  #  without_setup: if evals to true the 'python setup.py develop' command is not executed when deploying the component [default: nil]
  #    
  #  every pull-from-sourced component has additional proposal attributes:
  #    use_gitrepo: enable pull-from-source deployment mode [boolean: true/false]
  #    use_gitbarclamp: if true use barclamp-git deployed git repository as the origin
  #    git_instance: an instance of barclamp-git proposal to use when when use_gitbarclamp=true [str]
  #    gitrepo: custom git remote origin for the repo when use_gitbarclamp=false
  #    git_refspec: branch/tag/commit id [str]
  #    use_pip_cache: use pip package cache to install pypi pre-cached packages listed in component's tools/pip-requires
  #    pfs_deps: semicolon separated list of additional packages required for pull-from-sourced component deployment
  #      pypi packages should be specified with usual pip pkg syntax. eg 'pip://python-novaclient>=1.2<3'
  #      regular packages can have a version specification,  eg. 'kvm', 'qemu==0.6.2' 
  #
  comp_name = params[:name]
  repo_name = params[:repo] || params[:name]
  install_path = params[:path] || "/opt/#{comp_name}"
  cbook = params[:cookbook] || @cookbook_name
  cnode = params[:cnode] || node
  ref = params[:reference] || cnode[cbook][:git_refspec]

  ["git","python-setuptools","python-pip","python-dev","libxslt1-dev"].each do |pkg|
    package(pkg).run_action(:install)
  end

  if cnode[cbook][:use_gitbarclamp]
    env_filter = " AND git_config_environment:git-config-#{cnode[cbook][:git_instance]}"
    gitserver = search(:node, "roles:git#{env_filter}").first
    git_url = "git@#{gitserver[:fqdn]}:#{cbook}/#{repo_name}.git"
  else
    git_url = cnode[cbook][:gitrepo]
  end

  git install_path do
    repository git_url
    reference ref
  end.run_action(:sync)

  # prepare prefix to commands in using virtualenv
  prefix = params[:virtualenv] ? ". #{params[:virtualenv]}/bin/activate && " : nil

  if params[:virtualenv] and not File.exist?(params[:virtualenv])
    # prefix not nil and .venv not exist try create virtualenv
    package("python-virtualenv")
    if %w(redhat centos).include?(node.platform)
      package("python-devel")
    else
      package("python-dev")
    end
    directory params[:virtualenv] do
      recursive true
      owner "root"
      group "root"
      mode  0775
      action :create
    end
    execute "virtualenv #{params[:virtualenv]}#{" --system-site-packages" if params[:system_site] == true}"
  end

  pip_cmd = "#{prefix}pip install"
  if cnode[cbook][:use_pip_cache]
    provisioner = search(:node, "roles:provisioner-server").first
    proxy_addr = provisioner[:fqdn]
    proxy_port = provisioner[:provisioner][:web_port]
    pip_cmd = "#{prefix}pip install --index-url http://#{proxy_addr}:#{proxy_port}/files/pip_cache/simple/"
  else
    pip_cmd = "pip install"
  end

  if cnode[comp_name]
    unless cnode[comp_name][:pfs_deps].nil?
      deps = cnode[comp_name][:pfs_deps].dup
      apt_deps = deps.dup.delete_if{|x| x.include? "pip://"}
      pip_deps = deps - apt_deps
      pip_deps.map!{|x| x.split('//').last}

      #agordeev: add setuptools-git explicitly
      pip_deps.unshift("setuptools-git")

      pip_pythonclients = pip_deps.select{|x| x.include? "client"} || []
      apt_deps.each do |pkg|
        next if pkg.strip.empty?
        pkg_version = pkg.split("==").last
        package pkg do
          version pkg_version if pkg_version != pkg
        end
      end
      (pip_deps - pip_pythonclients).each do |pkg|
        execute "pip_install_#{pkg}" do
          command "#{pip_cmd} '#{pkg}'"
        end
      end
    end
  end

  unless params[:without_setup]
    require_file = ["#{install_path}/tools/pip-requires","#{install_path}/requirements.txt"].select{|file| File.exist?(file)}.first

    # workaround for swift
    execute "remove_https_from_pip_requires_for_#{comp_name}" do
      cwd install_path
      command "sed -i '/github/d' #{require_file}"
      only_if { comp_name == "swift" }
    end

    pips = File.read(require_file).split("\n").collect{|pip| pip.strip}.select{|pip| not pip.start_with?("-") or not pip.start_with?("#")}

    execute "pip_install_requirements_#{comp_name}" do
      cwd install_path
      command "#{pip_cmd} -r #{require_file}"
    end
    execute "setup_#{comp_name}" do
      cwd install_path
      command "#{prefix}python setup.py develop"
      creates "#{install_path}/#{comp_name == "nova_dashboard" ? "horizon":comp_name}.egg-info"
    end
    # post install clients
    pip_pythonclients.each do |pkg|
      execute "pip_install_clients_#{pkg}_for_#{comp_name}" do
        command "#{pip_cmd} '#{pkg}'"
      end
    end
  end

  #wrap for bins
  (params[:wrap_bins] || []).each do |bin|
    template "/usr/local/bin/#{bin}" do
      cookbook "git"
      source "virtualenv.erb"
      mode 0755
      owner "root"
      group "root"
      variables({:virtualenv => "#{params[:virtualenv]}", :bin => File.join(params[:virtualenv],"bin",bin) })
    end
  end
end

