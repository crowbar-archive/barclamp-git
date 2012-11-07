#!/bin/bash

bc_needs_build() {
    # always update
    return 0
}

bc_build() {
    pip install pip2pi
    $BC_DIR/build/build.rb
}
