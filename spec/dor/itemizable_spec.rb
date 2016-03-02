require 'spec_helper'

class ItemizableItem < ActiveFedora::Base
  include Dor::Itemizable
  include Dor::Processable
end

describe Dor::Itemizable do

  before(:each) { stub_config   }
  after(:each)  { unstub_config }

  before :each do
    @item = instantiate_fixture('druid:ab123cd4567', ItemizableItem)
    @item.contentMetadata.content = '<contentMetadata/>'
  end

  it 'has a contentMetadata datastream' do
    expect(@item.datastreams['contentMetadata']).to be_a(Dor::ContentMetadataDS)
  end

  it 'will run get_content_diff' do
    expect(Sdr::Client).to receive(:get_content_diff).
      with(@item.pid, @item.datastreams['contentMetadata'].content, :all, nil)
    @item.get_content_diff
  end
end
