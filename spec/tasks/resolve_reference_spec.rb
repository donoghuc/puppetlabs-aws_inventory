# frozen_string_literal: true

require 'spec_helper'
require_relative '../../tasks/resolve_reference.rb'

describe AwsInventory do
  let(:ip1) { '255.255.255.255' }
  let(:ip2) { '127.0.0.1' }
  let(:name1) { 'test-instance-1' }
  let(:name2) { 'test-instance-2' }
  let(:test_instances) {
    [
      { instance_id: name1,
        public_ip_address: ip1,
        public_dns_name: name1,
        state: { name: 'running' } },
      { instance_id: name2,
        public_ip_address: ip2,
        public_dns_name: name2,
        state: { name: 'running' } }
    ]
  }

  let(:test_client) {
    ::Aws::EC2::Client.new(
      stub_responses: { describe_instances: { reservations: [{ instances: test_instances }] } }
    )
  }

  let(:opts) do
    {
      name: 'public_dns_name',
      uri: 'public_ip_address',
      filters: [{ name: 'tag:Owner', values: ['foo'] }]
    }
  end

  context "with fake client" do
    before(:each) do
      subject.client = test_client
    end

    describe "#resolve_reference" do
      it 'matches all running instances' do
        targets = subject.resolve_reference(opts)
        expect(targets).to contain_exactly({ 'name' => name1, 'uri' => ip1 },
                                           'name' => name2, 'uri' => ip2)
      end

      it 'sets only name if uri is not specified' do
        opts.delete(:uri)
        targets = subject.resolve_reference(opts)
        expect(targets).to contain_exactly({ 'name' => name1 },
                                           'name' => name2)
      end

      it 'returns nothing if neither name nor uri are specified' do
        targets = subject.resolve_reference({})
        expect(targets).to be_empty
      end

      it 'builds a config map from the inventory' do
        config_template = { 'ssh' => { 'host' => 'public_ip_address' } }
        targets = subject.resolve_reference(opts.merge(config: config_template))

        config1 = { 'ssh' => { 'host' => ip1 } }
        config2 = { 'ssh' => { 'host' => ip2 } }
        expect(targets).to contain_exactly({ 'name' => name1, 'uri' => ip1, 'config' => config1 },
                                           'name' => name2, 'uri' => ip2, 'config' => config2)
      end
    end
  end

  describe "#config_client" do
    it 'raises a validation error when credentials file path does not exist' do
      config_data = { credentials: '~/foo/credentials' }
      expect { subject.config_client(opts.merge(config_data)) }.to raise_error(%r{foo/credentials})
    end
  end

  describe "#task" do
    it 'returns the list of targets' do
      targets = [
        { "uri": "1.2.3.4", "name": "my-instance" },
        { "uri": "1.2.3.5", "name": "my-other-instance" }
      ]
      allow(subject).to receive(:resolve_reference).and_return(targets)

      result = subject.task(opts)
      expect(result).to have_key(:value)
      expect(result[:value]).to eq(targets)
    end

    it 'returns an error if one is raised' do
      error = TaskHelper::Error.new('something went wrong', 'bolt.test/error')
      allow(subject).to receive(:resolve_reference).and_raise(error)
      result = subject.task({})

      expect(result).to have_key(:_error)
      expect(result[:_error]['msg']).to match(/something went wrong/)
    end
  end
end