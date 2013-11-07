#!/bin/bash

bc_needs_build() {
    # we always running build script to gather pips from crowbar.yml
    true
}

bc_build() {
    sudo pip install pip2pi
    $BC_DIR/build/build.rb
}
