require 'inifile'

module OpsWorks
  def self.config
    @config ||= Config.new
  end

  class Config
    attr_reader :stacks, :accounts, :regions, :options

    def initialize
      file = ENV["AWS_CONFIG_FILE"] || "#{ENV['HOME']}/.aws/config"
      raise "AWS config file not found" unless File.exists? file
      @ini = IniFile.load(file)
      @accounts = ['default']
      if users = @ini['opsworks']['IAM']
        @accounts = users.split(',').map(&:strip)
      else
        #support old config
        @ini['default'] = {
          'aws_access_key_id' => @ini['default']['aws_access_key_id'],
          'aws_secret_access_key' => @ini['default']['aws_secret_access_key'],
          'opsworks-stack-id' => @ini['opsworks']['stack-id'],
          'opsworks-ssh-user-name' => @ini['opsworks']['ssh-user-name']
        }
      end
    end

    def use_account(account)
      aws_config = @ini[account]
      Aws.config.update(
        region: 'us-east-1',
        credentials: Aws::Credentials.new(
          aws_config["aws_access_key_id"],
          aws_config["aws_secret_access_key"],
        )
      )
      @options = @ini[account]
      @regions = aws_config['aws_region'].split(',').map(&:strip) rescue []
      @stacks = aws_config['opsworks-stack-id'].split(',').map(&:strip) rescue []
    end
  end
end
