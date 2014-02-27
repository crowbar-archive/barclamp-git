# -*- encoding : utf-8 -*-
name "git"
description "Git Role - does git repos hosting via ssh"
run_list(
        "recipe[git::install]",
        "recipe[git::config]"
)
default_attributes()
override_attributes()
