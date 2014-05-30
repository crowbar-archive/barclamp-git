#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class GitService < ServiceObject

  def initialize(thelogger)
    @bc_name = "git"
    @logger = thelogger
  end

  class << self
    def role_constraints
      {
        "git" => {
          "unique" => false,
          "count" => 1
        }
      }
    end
  end

  def create_proposal
    # TODO: ensure that only one proposal can be applied to a node
    @logger.debug("Git create_proposal: entering")
    base = super
    @logger.debug("Git create_proposal: leaving base part")

    nodes = NodeObject.all
    nodes.delete_if { |n| not n.admin? }
    unless nodes.empty?
      base["deployment"]["git"]["elements"] = {
        "git" => [ nodes.first.name ]
      }
    end

    @logger.debug("Git create_proposal: exiting")
    base
  end

end

