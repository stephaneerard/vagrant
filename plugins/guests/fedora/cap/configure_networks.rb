require "tempfile"

require_relative "../../../../lib/vagrant/util/retryable"
require_relative "../../../../lib/vagrant/util/template_renderer"

module VagrantPlugins
  module GuestFedora
    module Cap
      class ConfigureNetworks
        extend Vagrant::Util::Retryable
        include Vagrant::Util

        def self.configure_networks(machine, networks)
          comm = machine.communicate

          network_scripts_dir = machine.guest.capability(:network_scripts_dir)

          interfaces = []
          commands   = []

          comm.sudo("/sbin/ip -o -0 addr | grep -v LOOPBACK | awk '{print $2}' | sed 's/://'") do |_, stdout|
            interfaces = stdout.split("\n")
          end

          networks.each.with_index do |network, i|
            network[:device] = interfaces[network[:interface]]

            # Render a new configuration
            entry = TemplateRenderer.render("guests/fedora/network_#{network[:type]}",
              options: network,
            )

            # Upload the new configuration
            remote_path = "/tmp/vagrant-network-entry-#{network[:device]}-#{Time.now.to_i}-#{i}"
            Tempfile.open("vagrant-fedora-configure-networks") do |f|
              f.binmode
              f.write(entry)
              f.fsync
              f.close
              machine.communicate.upload(f.path, remote_path)
            end

            # Add the new interface and bring it back up
            final_path = "#{network_scripts_dir}/ifcfg-#{network[:device]}"
            commands << <<-EOH.gsub(/^ {14}/, '')
              # Down the interface before munging the config file. This might
              # fail if the interface is not actually set up yet so ignore
              # errors.
              /sbin/ifdown '#{network[:device]}' || true

              # Move new config into place
              mv '#{remote_path}' '#{final_path}'

              # Bring the interface up
              ARPCHECK=no /sbin/ifup '#{network[:device]}'
            EOH
          end

          comm.sudo(commands.join("\n"))
        end
      end
    end
  end
end
