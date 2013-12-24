#!/bin/bash

bc_needs_build() {
    # always update
    [[ $UPDATE_GIT_REPOS = true ]]
}

bc_build() {
    sudo pip install pip2pi
    $BC_DIR/build/build.rb
}
