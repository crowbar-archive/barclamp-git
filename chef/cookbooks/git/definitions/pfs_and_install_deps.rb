define :pfs_and_install_deps, :action => :create do

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
