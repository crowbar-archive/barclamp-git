define :pfs_and_install_deps, :action => :create do

  #params:
  #  name: name of comptonent to install
  #  path: a path where to clone git repo [default: /opt/#{comp_name} ]
  #  cookbook: a name of cookbook to use for PFS [default: current cookbook ]
  #  cnode: a node where PFS will take all PFS related attrs [default: current node ]
  #  reference: git_refspec (branch,tag,commit hashsum) for checkouting the code
  #    defaultly uses `git_refspec` from `cookbook`'s proposal which was applied to `cnode`
  #    actually used only to deploy keystone libs for glance/nova/horizon/cinder
  #  without_setup: set it to true for skipping 'python setup.py develop' [default: nil]
  #    
  #  every PFS-ed component should contain some attrs:
  #    use_gitrepo: enable PFS [boolean: true/false]
  #    git_instance: instance of git proposal [str]
  #    git_refspec: a kind of checkouting `reference` [str]
  #    gitrepo: user defined (external) git repo remote origin
  #    use_gitbarclamp: pull code from node where `git_instance` proposal applied if true, otherwize `gitrepo` be used
  #    use_pip_cache: use pip-cache from git node for installing pypi pre-cached packages for tools/pip-requires
  #    pfs_deps: a semicolon separated list of additional packages needed for PFS-ed component deployment
  #      for pypi packages prefix 'pip://' should be specified with usual pip pkg syntax. eg 'pip://python-novaclient>=1.2<3'
  #      no prefix for deb packages, but package version can be specified after == sign. eg. 'kvm', 'qemu==0.6.2' 
  #
  comp_name = params[:name]
  install_path = params[:path] || "/opt/#{comp_name}"
  cbook = params[:cookbook] || @cookbook_name
  cnode = params[:cnode] || node
  ref = params[:reference] || cnode[cbook][:git_refspec] 
  package("git")
  package("python-setuptools")
  package("python-pip")
  if cnode[cbook][:use_gitbarclamp]
    env_filter = " AND git_config_environment:git-config-#{cnode[cbook][:git_instance]}"
    gitserver = search(:node, "roles:git#{env_filter}").first
    git_url = "git@#{gitserver[:fqdn]}:#{cbook}/#{comp_name}.git"
  else
    git_url = cnode[cbook][:gitrepo]
  end
  if cnode[cbook][:use_pip_cache]
    provisioner = search(:node, "roles:provisioner-server").first
    proxy_addr = provisioner[:fqdn]
    proxy_port = provisioner[:provisioner][:web_port]
    pip_cmd = "pip install --index-url http://#{proxy_addr}:#{proxy_port}/files/pip_cache/simple/"
  else
    pip_cmd = "pip install"
  end
  git install_path do
    repository git_url 
    reference ref
    action :sync
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
    execute "pip_install_requirements_#{comp_name}" do
      cwd install_path
      command "#{pip_cmd} -r tools/pip-requires"
    end
    execute "setup_#{comp_name}" do
      cwd install_path
      command "python setup.py develop"
      creates "#{install_path}/#{comp_name == "nova_dashboard" ? "horizon":comp_name}.egg-info"
    end
    # post install clients
    pip_pythonclients.each do |pkg| 
      execute "pip_install_clients_#{pkg}_for_#{comp_name}" do
        command "#{pip_cmd} '#{pkg}'"
      end
    end
  end
end
