define :create_user_and_dirs, :action => :enable do

  user_name = params[:user_name] || params[:name]
  comp_name = params[:comp_name] || params[:name]
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
  
  dirs.each do |d|
    directory d do
      owner user_name
      group "root"
    end
  end
end
