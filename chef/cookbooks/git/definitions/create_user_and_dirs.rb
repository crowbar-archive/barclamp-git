define :create_user_and_dirs, :action => :enable, :user_name => nil, :group_name => nil do
  # params:
  #   user_name - name of the user to create  [default: name]
  #   group_name - name of the group to create  [default: name]
  #   comp_name - name of component to deploy (eg. glance) [default: name]
  #   home_dir - home directory for the user [default: /var/lib/#{comp_name}]
  #   user_gid - existing group id for the user [default: nil] 
  #   dir_group - an existing group id for the directories to be created [default: root]
  #   opt_dirs - list of additional dirs to create [default: nil]
  #   

  user_name = params[:user_name] || params[:name]
  group_name = params[:group_name] || params[:name]
  comp_name = params[:comp_name] || params[:name]
  dir_group = params[:dir_group] || "root"
  dirs = ["/var/lib", "/var/log", "/var/lock", "/etc"]
  dirs.map! { |d| d += "/" + comp_name }
  dirs.concat(params[:opt_dirs]) if params[:opt_dirs]

  user user_name do
    comment "crowbar #{user_name}"
    home dirs.first || params[:home_dir]
    gid params[:user_gid] if params[:user_gid]
    system true
    shell "/bin/false"
  end
 
  group group_name do
    members user_name
    system true
  end
 
  dirs.each do |d|
    directory d do
      owner user_name
      group dir_group
    end
  end
end
