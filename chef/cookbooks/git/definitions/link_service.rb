define :link_service, :action => :create, :virtualenv => nil do

  service_name = params[:name]
  service_user = params[:user] || service_name.split('-').first

  template "/etc/init/#{service_name}.conf" do
    cookbook "git"
    source "upstart.conf.erb"
    mode 0644
    variables({
        :service_name => service_name,
        :bin_name => params[:bin_name] || service_name,
        :user => service_user,
        :opt_params => params[:opt_params],
        :opt_path => params[:opt_path],
        :prefix => params[:virtualenv] ? ". #{params[:virtualenv]}/bin/activate && " : nil
    })
  end
  execute "link_service_#{service_name}" do
    command "ln -s /lib/init/upstart-job /etc/init.d/#{service_name}"
    creates "/etc/init.d/#{service_name}"
  end
end
