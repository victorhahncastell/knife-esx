#
# Author:: Sergio Rubio, Massimo Maino (<maintux@gmail.com>)
# Copyright:: Sergio Rubio, Massimo Maino (c) 2011
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife'

class Chef
  class Knife
    module ESXBase

      class << self # create public static command_param attribute
        attr_accessor :command_param
      end
      self.command_param = Hash.new

      # :nodoc:
      # Would prefer to do this in a rational way, but can't be done b/c of
      # Mixlib::CLI's design :(
      def self.included(includer)
        includer.class_eval do

          deps do
            require 'net/ssh/multi'
            require 'esx'
            require 'readline'
            require 'chef/json_compat'
            require 'terminal-table/import'
          end

          option :esx_password,
            :long => "--esx-password PASSWORD",
            :description => "Your ESX password",
            :proc => Proc.new { |key| ESXBase.command_param[:key] = key }

          option :esx_username,
            :long => "--esx-username USERNAME",
            :default => "root",
            :description => "Your ESX username (default 'root')",
            :proc => Proc.new { |username| ESXBase.command_param[:user] = (username || 'root') }

          option :esx_host,
            :long => "--esx-host ADDRESS",
            :description => "Your ESX host address",
            :default => "127.0.0.1",
            :proc => Proc.new { |host| ESXBase.command_param[:host] = host }

          option :free_license,
            :long => "--free-license",
            :description => "If your Hypervisor has a free license",
            :boolean => true,
            :default => false

          option :insecure,
            :long => "--insecure",
            :description => "Insecure connection",
            :boolean => true,
            :default => true

          option :esx_templates_dir,
            :long => "--esx-templates-dir TEMPLATES_DIRECTORY",
            :description => "Your ESX Templates directory (full path on the ESX host, e.g. /vmfs/volumes/[datastore]/...)",
            :default => "",
            :proc => Proc.new { |templates_dir| ESXBase.command_param[:templates_dir] = templates_dir }

          ESXBase::commit_config # Apply config now, just in case it is needed now. Will re-apply when connecting.
        end
      end


      def self.commit_config()
        if ESXBase.command_param[:key] != nil then Chef::Config[:knife][:esx_password] = ESXBase.command_param[:key] end
        if ESXBase.command_param[:user] != nil then Chef::Config[:knife][:esx_username] = ESXBase.command_param[:user] end
        if ESXBase.command_param[:host] != nil then Chef::Config[:knife][:esx_host] = ESXBase.command_param[:host] end
        if ESXBase.command_param[:templates_dir] != nil then Chef::Config[:knife][:esx_templates_dir] = ESXBase.command_param[:templates_dir] end
        if ESXBase.command_param[:bootstrap_version] != nil then Chef::Config[:knife][:bootstrap_version] = ESXBase.command_param[:bootstrap_version] end
        if ESXBase.command_param[:distro] != nil then Chef::Config[:knife][:distro] = ESXBase.command_param[:distro] end
        if ESXBase.command_param[:template_file] != nil then Chef::Config[:knife][:template_file] = ESXBase.command_param[:template_file] end
      end


      def connection
        ESXBase.commit_config # write mixlib configuration now to ensure command line args override knife.rb settings
        if not @connection
          ui.info "#{ui.color("Connecting to ESX host #{Chef::Config[:knife][:esx_host]}... ", :magenta)}"
          @connection = ESX::Host.connect(Chef::Config[:knife][:esx_host],
                                          Chef::Config[:knife][:esx_username],
                                          Chef::Config[:knife][:esx_password] || '',
                                          config[:insecure],
                                          {:templates_dir => Chef::Config[:knife][:esx_templates_dir], :free_license=>config[:free_license]})
        else
          @connection
        end
      end


      def wait_for_ssh vm
        # wait for it to be ready to do stuff
        print "\n#{ui.color("Waiting for server... ", :magenta)}"
        timeout = 100
        found = connection.virtual_machines.find { |v| v.name == vm.name }
        loop do
          if not vm.ip_address.nil? and not vm.ip_address.empty?
            puts "\n#{ui.color("VM IP Address: #{vm.ip_address}", :cyan)}"
            break
          end
          timeout -= 1
          if timeout == 0
            ui.error "Timeout trying to reach the VM. Does it have vmware-tools installed?"
            return false
          end
          sleep 1
          found = connection.virtual_machines.find { |v| v.name == vm.name }
        end

        print "\n#{ui.color("Waiting for sshd... ", :magenta)}"
        print(".") until tcp_test_ssh(vm.ip_address) { sleep @initial_sleep_delay ||= 10; puts(" done") }
      end


      def tcp_test_ssh(hostname)
        if config[:ssh_gateway]
          print "\n#{ui.color("Can't test connection through gateway, sleeping 10 seconds... ", :magenta)}"
          sleep 10
        else
          tcp_socket = TCPSocket.new(hostname, 22)
          readable = IO.select([tcp_socket], nil, nil, 5)
          if readable
            Chef::Log.debug("sshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}")
            yield
            true
          else
            false
          end
        end
      rescue Errno::ETIMEDOUT, Errno::EPERM
        false
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH
        sleep 2
        false
      ensure
        tcp_socket && tcp_socket.close
      end



      def locate_config_value(key)
        key = key.to_sym
        Chef::Config[:knife][key] || config[key]
      end

    end
  end
end


