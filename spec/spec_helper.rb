# encoding: UTF-8
require 'chefspec'
require 'chefspec/berkshelf'

ChefSpec::Coverage.start! { add_filter 'openstack-orchestration' }

require 'chef/application'

LOG_LEVEL = :fatal
REDHAT_OPTS = {
  platform: 'redhat',
  version: '7.1',
  log_level: ::LOG_LEVEL
}
UBUNTU_OPTS = {
  platform: 'ubuntu',
  version: '14.04',
  log_level: ::LOG_LEVEL
}
SUSE_OPTS = {
  platform: 'suse',
  version: '11.3',
  log_level: ::LOG_LEVEL
}

shared_context 'orchestration_stubs' do
  before do
    allow_any_instance_of(Chef::Recipe).to receive(:rabbit_servers)
      .and_return '1.1.1.1:5672,2.2.2.2:5672'
    allow_any_instance_of(Chef::Recipe).to receive(:address_for)
      .with('lo')
      .and_return '127.0.1.1'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'openstack_identity_bootstrap_token')
      .and_return 'bootstrap-token'

    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('db', 'heat')
      .and_return 'heat'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'guest')
      .and_return 'mq-pass'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'admin-user')
      .and_return 'admin-pass'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('service', 'openstack-orchestration')
      .and_return 'heat-pass'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('user', 'admin')
      .and_return 'admin_pass'
    allow_any_instance_of(Chef::Recipe).to receive(:get_password)
      .with('token', 'orchestration_auth_encryption_key')
      .and_return 'auth_encryption_key_secret'
    allow(Chef::Application).to receive(:fatal!)
  end
end

shared_examples 'expect runs openstack orchestration common recipe' do
  it 'runs orchestration common recipe' do
    expect(chef_run).to include_recipe 'openstack-orchestration::common'
  end
end

shared_examples 'expect installs python keystoneclient' do
  it 'installs python-keystoneclient' do
    expect(chef_run).to upgrade_package 'python-keystoneclient'
  end
end

shared_examples 'expect runs openstack common logging recipe' do
  it 'runs logging recipe if node attributes say to' do
    expect(chef_run).to include_recipe 'openstack-common::logging'
  end
end

shared_examples 'expect installs common heat package' do
  it 'installs the openstack-heat common package' do
    expect(chef_run).to upgrade_package 'openstack-heat-common'
  end
end

shared_examples 'expect installs mysql package' do
  it 'installs mysql python packages by default' do
    expect(chef_run).to upgrade_package 'MySQL-python'
  end
end

shared_examples 'expect runs db migrations' do
  it 'runs db migrations' do
    expect(chef_run).to run_execute('heat-manage db_sync').with(user: 'heat', group: 'heat')
  end
end

shared_examples 'expects to create heat directories' do
  it 'creates /etc/heat' do
    expect(chef_run).to create_directory('/etc/heat').with(
      owner: 'heat',
      group: 'heat',
      mode: 0750
    )
  end

  it 'creates /etc/heat/environment.d' do
    expect(chef_run).to create_directory('/etc/heat/environment.d').with(
      owner: 'heat',
      group: 'heat',
      mode: 0750
    )
  end
end

shared_examples 'expects to create heat conf' do
  describe 'heat.conf' do
    let(:file) { chef_run.template('/etc/heat/heat.conf') }

    it 'creates the heat.conf file' do
      expect(chef_run).to create_template(file.name).with(
        owner: 'heat',
        group: 'heat',
        mode: 0640
      )
    end

    it 'sets auth_encryption_key' do
      expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', /^auth_encryption_key = auth_encryption_key_secret$/)
    end

    describe 'default values' do
      it 'has default conf values' do
        [
          %r{^heat_metadata_server_url = http://127.0.0.1:8000$},
          %r{^heat_waitcondition_server_url = http://127.0.0.1:8000/v1/waitcondition$},
          %r{^heat_watch_server_url = http://127.0.0.1:8003$},
          %r{^log_dir = /var/log/heat$},
          /^region_name_for_services = RegionOne$/
        ].each do |line|
          expect(chef_run).to render_config_file(file.name).with_section_content('DEFAULT', line)
        end
      end

      it 'has oslo_messaging_notifications conf values' do
        [
          /^driver = heat.openstack.common.notifier.rpc_notifier$/
        ].each do |line|
          expect(chef_run).to render_config_file(file.name).with_section_content('oslo_messaging_notifications', line)
        end
      end

      it 'has heat_api binding' do
        [
          /^bind_host = 127.0.0.1$/,
          /^bind_port = 8004$/
        ].each do |line|
          expect(chef_run).to render_config_file(file.name).with_section_content('heat_api', line)
        end
      end

      it 'has heat_api_cfn binding' do
        [
          /^bind_host = 127.0.0.1$/,
          /^bind_port = 8000$/
        ].each do |line|
          expect(chef_run).to render_config_file(file.name).with_section_content('heat_api_cfn', line)
        end
      end

      it 'has heat_api_cloudwatch binding' do
        [
          /^bind_host = 127.0.0.1$/,
          /^bind_port = 8003$/
        ].each do |line|
          expect(chef_run).to render_config_file(file.name).with_section_content('heat_api_cloudwatch', line)
        end
      end

      it 'sets database connection value' do
        expect(chef_run).to render_config_file(file.name).with_section_content(
          'database', %r{^connection = mysql://heat:heat@127.0.0.1:3306/heat\?charset=utf8$})
      end
    end

    describe 'has ec2authtoken values' do
      it 'has default ec2authtoken values' do
        expect(chef_run).to render_config_file(file.name).with_section_content('ec2authtoken', %r{^auth_uri = http://127.0.0.1:5000/v2.0$})
      end
    end

    describe 'has clients_keystone values' do
      it 'has default clients_keystone values' do
        expect(chef_run).to render_config_file(file.name).with_section_content('clients_keystone', %r{^auth_uri = http://127.0.0.1:5000/$})
      end
    end

    describe 'has oslo_messaging_rabbit values' do
      it 'has default oslo_messaging_rabbit values' do
        [
          /^rabbit_userid = guest$/,
          /^rabbit_password = mq-pass$/
        ].each do |line|
          expect(chef_run).to render_config_file(file.name).with_section_content('oslo_messaging_rabbit', line)
        end
      end
    end

    describe 'has keystone_authtoken values' do
      it 'has default keystone_authtoken values' do
        [
          %r{^auth_url = http://127.0.0.1:5000/v2.0$},
          /^auth_type = v2password$/,
          /^username = heat$/,
          /^tenant_name = service$/,
          /^password = heat-pass$/
        ].each do |line|
          expect(chef_run).to render_config_file(file.name).with_section_content('keystone_authtoken', line)
        end
      end
    end

    describe 'has trustee values' do
      it 'has default trustee values' do
        [
          %r{^auth_url = http://127.0.0.1:35357/v2.0$},
          /^auth_plugin = v2password$/,
          /^username = heat$/,
          /^password = heat-pass$/
        ].each do |line|
          expect(chef_run).to render_config_file(file.name).with_section_content('trustee', line)
        end
      end
    end
  end
end

shared_examples 'expects to create heat default.yaml' do
  describe 'default.yaml' do
    let(:file) { chef_run.template('/etc/heat/environment.d/default.yaml') }

    it 'creates the default.yaml file' do
      expect(chef_run).to create_template(file.name).with(
        owner: 'heat',
        group: 'heat',
        mode: 0644
      )
    end
  end
end

shared_examples 'logging' do
  context 'with logging enabled' do
    before do
      node.set['openstack']['orchestration']['syslog']['use'] = true
    end

    it 'runs logging recipe if node attributes say to' do
      expect(chef_run).to include_recipe 'openstack-common::logging'
    end
  end

  context 'with logging disabled' do
    before do
      node.set['openstack']['orchestration']['syslog']['use'] = false
    end

    it "doesn't run logging recipe" do
      expect(chef_run).not_to include_recipe 'openstack-common::logging'
    end
  end
end
