#!/usr/bin/ruby

require 'rubygems'
require 'aws-sdk'
require 'base64'
require 'timeout'
require 'yaml'

@config = YAML.load_file('config/config.yml')

Aws.config.update({
  :credentials => Aws::Credentials.new(@config[:aws_access_key_id], @config[:aws_secret_access_key])
})

def fire_region_nodes(region, count, key_pair_name, ami_id, subnet_id)
  ec2 = Aws::EC2::Resource.new(:region => region)
  instances = ec2.create_instances({
    :image_id => ami_id,
    :min_count => count,
    :max_count => count,
    :key_name => key_pair_name,
    :instance_type => @config[:instance_type],
    :subnet_id => subnet_id,
    :iam_instance_profile => {
      :name => @config[:ssm_role]
    },
    tag_specifications: [
      {
        resource_type: "instance",
        tags: [
          {
            key: "type",
            value: "load_testing",
          }
        ]
      }
    ]
    # :user_data => Base64.encode64("sudo apt-get --assume-yes install apache2-utils && cd /tmp && wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb && sudo dpkg -i amazon-ssm-agent.deb && sudo systemctl start amazon-ssm-agent")
    })
end

def fire_commands(region, instances, commands)
  ssm = Aws::SSM::Client.new(:region => region)
  resp = ssm.send_command({
    instance_ids: instances,
    document_name: "AWS-RunShellScript",
    timeout_seconds: @config[:command_timeout],
    parameters: {
      "commands" => commands,
    },
    max_concurrency: "100%"
  })
  return resp.command.command_id
end

def print_command_output(command_id, region, instance)
  puts "\nTrying to fetch output from instance id #{instance}..."
  ssm = Aws::SSM::Client.new(:region => region)
  res = ssm.get_command_invocation({:command_id => command_id, :instance_id => instance})

  while ["pending", "inprogress", "delayed"].include?(res.status_details.downcase)
    loader2(10)
    res = ssm.get_command_invocation({:command_id => command_id, :instance_id => instance})
  end

  puts "*"*80
  puts "Output on instance id #{instance} from region #{region}"
  puts "*"*80
  if(res.status_details.downcase == "success")
    puts res.standard_output_content
  else
    print_error("Request failed with status: #{res.status_details}! Debug manually!")
    puts res.standard_output_content if res.standard_output_content
  end
  puts "#"*80
end

def print_error(message)
  puts "\e[#31m#{message}\e[0m"
end

def terminate_instances(region, instances)
  ec2 = Aws::EC2::Resource.new(:region => region)
  ec2.instances.each do |i|
    if instances.include?(i.id)
      i.terminate
      puts "Terminating instance #{i.id}  ︻デ┳═ー"
    end
  end
end

def loader1(duration)
  begin
    Timeout::timeout(duration) do
      while(true)
        75.times{ |i| f=rand(17); STDOUT.write "\r#{'~'*f}^o^#{'~'*(17-f)}#{'~'*(75-i)}\\___/#{'~'*i}"; sleep 0.2 }; STDOUT.write "\r#{'~'*17}^o^\\___/#{'~'*75}"; sleep 2; 20.times{ |i| STDOUT.write "\r#{'~'*(19-i)}\\___/#{'~'*(i+76)}"; sleep 0.2 }
      end
    end
  rescue
  end
end

def loader2(duration)
  begin
    Timeout::timeout(duration) do
      ["|", "/", "-", "\\"].each{|v| STDOUT.write "\r#{v}"; sleep 0.5} while 1
    end
  rescue
  end
end

region_data = @config[:region_data]

region_data.each do |data|
  next if data[:node_count] < 1
  instance_objects = fire_region_nodes(data[:region], data[:node_count], data[:key], data[:ami_id], data[:subnet_id])
  data[:instances] = instance_objects.map {|i| i.id}

  puts "#{data[:region]} Instances:"
  puts "-"*80
  instance_objects.each {|i| puts "#{i.id} - #{i.state.name}"}
  puts "-"*80
end

puts "Sleeping for 5 minutes to make sure instances are ready..."
loader2(300)

region_data.each do |data|
  next if data[:node_count] < 1
  data[:command_id] = fire_commands(data[:region], data[:instances], data[:commands])
  puts "Master command id for #{data[:region]}: #{data[:command_id]}"
end

puts "Sleeping for 1 minute to make sure command invocation has reached the EC2 instances..."
loader1(60)

region_data.each do |data|
  next if data[:node_count] < 1
  data[:instances].each do |instance|
    print_command_output(data[:command_id], data[:region], instance)
  end
end

puts "Sleeping for 2 minutes before terminating EC2 instances. In case you do not want this press <ctrl> c ..."
loader2(120)

region_data.each do |data|
  next if data[:node_count] < 1
  terminate_instances(data[:region], data[:instances])
end
