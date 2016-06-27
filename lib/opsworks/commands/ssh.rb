require 'aws-sdk'
require 'trollop'

require 'opsworks'

SSH_PREFIX  = "# --- OpsWorks ---"
SSH_POSTFIX = "# --- End of OpsWorks ---"

module OpsWorks::Commands
  class SSH
    def self.banner
      "Generate and update SSH configuration files"
    end

    def self.run
      options = Trollop::options do
        banner <<-EOS.unindent
          #{SSH.banner}

          Options:
        EOS
        opt :update, "Update ~/.ssh/config directly"
        opt :backup, "Backup old SSH config before updating"
        opt :quiet,  "Use SSH LogLevel quiet", default: true
        opt :key_checking,
            "Check SSH host keys (this can be annoying since dynamic " <<
            "instances often change IP number)", short: 'c', default: false
      end

      ssh_config = []

      config = OpsWorks.config

      config.accounts.each do |name|

        ssh_config << "\n\n# --- #{name} ---\n\n"
        config.use_account(name)
        instances = []


        client = Aws::OpsWorks::Client.new

        stack_ids = if config.stacks.empty?
                      stacks = client.describe_stacks[:stacks]
                      stacks.map{|s| s[:stack_id]}
                    else
                      config.stacks
                    end

        if stack_ids.empty?
          config.regions.each do |region|
            resources = Aws::EC2::Client.new(region: region)
            instances += resources.describe_instances.reservations.inject([]) do |res, reservation|
              res << reservation.instances.select { |i| i.state.name != "stopped" }
            end.flatten
          end
          instances = map_ec2_instances(instances)
        else
          stack_ids.each do |stack_id|
            result = client.describe_instances(stack_id: stack_id)
            instances += result.instances.select { |i| i[:status] != "stopped" }
          end
          instances = map_opsworks_instances(instances)
        end

        ssh_config << build_ssh_config(instances, options.merge(config.options))

      end

      new_contents = "\n\n#{SSH_PREFIX}\n" <<
                     "#{ssh_config.join("\n")}\n" <<
                     "#{SSH_POSTFIX}\n\n"

      if options[:update]
        ssh_config = "#{ENV['HOME']}/.ssh/config"
        old_contents = File.read(ssh_config)

        if options[:backup]
          base_name = ssh_config + ".backup"
          if File.exists? base_name
            number = 0
            file_name = "#{base_name}-#{number}"
            while File.exists? file_name
              file_name = "#{base_name}-#{number += 1}"
            end
          else
            file_name = base_name
          end
          File.open(file_name, "w") { |file| file.puts old_contents }
        end

        File.open(ssh_config, "w") do |file|
          file.puts old_contents.gsub(
            /\n?\n?#{SSH_PREFIX}.*#{SSH_POSTFIX}\n?\n?/m,
            ''
          )
          file.puts new_contents
        end

        puts "Successfully updated #{ssh_config} with " <<
             "#{ssh_config.length} instances!"
      else
        puts new_contents.strip
      end
    end

    def self.build_ssh_config(instances, options)
      puts options
      user_name = options['opsworks_ssh_user_name'] || options['ssh_user_name']

      instances.reject! { |i| i[:ip].nil? }
      instances.map! do |instance|
        parameters = {
          "Host"                  => "#{instance[:hostname]} #{instance[:ip]}",
          "HostName"              => instance[:ip],
          "User"                  => user_name,
        }
        parameters["IdentityFile"] = options['identity_file'] if options['identity_file']
        parameters.merge!({
          "StrictHostKeyChecking" => "no",
          "UserKnownHostsFile"    => "/dev/null",
        }) unless options[:host_checking]
        parameters["LogLevel"] = "quiet" if options[:quiet]
        parameters.map{ |param| param.join(" ") }.join("\n  ")
      end
    end

    def self.map_opsworks_instances(instances)
      instances.inject([]) do |mapped, instance|
        mapped << {
          ip: instance.elastic_ip || instance.public_ip,
          hostname: instance.hostname
        }
      end
    end

    def self.map_ec2_instances(instances)
      instances.inject([]) do |mapped, instance|
        mapped << {
          ip: instance.public_ip_address,
          hostname: instance.tags.select {|v| v.key == "Name"}.first.value
        }
      end
    end

  end
end
