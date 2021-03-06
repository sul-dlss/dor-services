# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dor::Item do
  describe '#add_collection' do
    let(:item) { instantiate_fixture('druid:oo201oo0001', described_class) }
    let(:service) { instance_double(Dor::CollectionService, add: true) }

    before do
      allow(Dor::CollectionService).to receive(:new).and_return(service)
    end

    it 'delegates to the CollectionService' do
      item.add_collection('druid:oo201oo0002')
      expect(service).to have_received(:add).with('druid:oo201oo0002')
    end
  end

  describe '#remove_collection' do
    let(:item) { instantiate_fixture('druid:oo201oo0001', described_class) }
    let(:service) { instance_double(Dor::CollectionService, remove: true) }

    before do
      allow(Dor::CollectionService).to receive(:new).and_return(service)
    end

    it 'deletes a collection' do
      item.remove_collection('druid:oo201oo0002')
      expect(service).to have_received(:remove).with('druid:oo201oo0002')
    end
  end

  describe '#reapply_admin_policy_object_defaults' do
    let(:item) { instantiate_fixture('druid:oo201oo0001', described_class) }
    let(:apo) { instantiate_fixture('druid_zt570tx3016', Dor::AdminPolicyObject) }

    before do
      allow(item).to receive(:admin_policy_object).and_return(apo)
    end

    it 'updates rightsMetadata from the APO defaultObjectRights' do
      expect(item.rightsMetadata.ng_xml.search('//rightsMetadata/access[@type=\'read\']/machine/group').length).to eq(1)
      item.reapply_admin_policy_object_defaults
      expect(item.rightsMetadata.ng_xml.search('//rightsMetadata/access[@type=\'read\']/machine/group').length).to eq(0)
      expect(item.rightsMetadata.ng_xml.search('//rightsMetadata/access[@type=\'read\']/machine/world').length).to eq(1)
    end
  end

  describe '#read_rights=' do
    subject(:set_read_rights) { item.read_rights = rights }

    let(:item) { instantiate_fixture('druid:bb046xn0881', described_class) }

    context 'when set to dark' do
      let(:rights) { 'dark' }

      it 'unshelves and unpublishes content metadata' do
        expect(item).to receive(:unshelve_and_unpublish)
        set_read_rights
      end
    end
  end

  describe '#unshelve_and_unpublish' do
    subject(:unshelve_and_unpublish) { item.send(:unshelve_and_unpublish) }

    let(:item) { instantiate_fixture('druid:bb046xn0881', described_class) }

    it 'notifies that the XML will change' do
      expect(item.contentMetadata).to receive(:ng_xml_will_change!).once
      unshelve_and_unpublish
    end

    it 'sets publish and shelve to no for all files' do
      unshelve_and_unpublish
      new_metadata = item.contentMetadata
      expect(new_metadata.ng_xml.xpath('/contentMetadata/resource//file[@publish="yes"]').length).to eq(0)
      expect(new_metadata.ng_xml.xpath('/contentMetadata/resource//file[@shelve="yes"]').length).to eq(0)
    end

    context 'when there is no contentMetadata' do
      let(:item) { instantiate_fixture('druid:bb004bn8654', described_class) }

      it 'does nothing' do
        expect(item).not_to receive(:ng_xml_will_change!)
        unshelve_and_unpublish
      end
    end
  end

  describe 'datastreams' do
    let(:item) { described_class.new(pid: 'foo:123') }

    describe '#geoMetadata' do
      it 'has a geoMetadata datastream' do
        expect(item.geoMetadata).to be_a Dor::GeoMetadataDS
      end
    end

    describe '#rightsMetadata' do
      it 'has a rightsMetadata datastream' do
        expect(item.rightsMetadata).to be_a Dor::RightsMetadataDS
      end
    end

    describe '#descMetadata' do
      it 'has a descMetadata datastream' do
        expect(item.descMetadata).to be_a Dor::DescMetadataDS
      end
    end

    describe '#contentMetadata' do
      it 'has a contentMetadata datastream' do
        expect(item.contentMetadata).to be_a Dor::ContentMetadataDS
      end
    end

    describe '#identityMetadata' do
      it 'has an identityMetadata datastream' do
        expect(item.identityMetadata).to be_a Dor::IdentityMetadataDS
      end
    end
  end

  describe '#stanford_mods' do
    let(:item) { described_class.new(pid: 'foo:123') }

    before do
      item.descMetadata.content = read_fixture('ex1_mods.xml')
    end

    it 'fetches Stanford::Mods object' do
      expect(item.methods).to include(:stanford_mods)
      sm = nil
      expect { sm = item.stanford_mods }.not_to raise_error
      expect(sm).to be_kind_of(Stanford::Mods::Record)
      expect(sm.format_main).to eq(['Book'])
      expect(sm.pub_year_sort_str).to eq('1911')
    end

    it 'allows override argument(s)' do
      sm = nil
      nk = Nokogiri::XML('<mods><genre>ape</genre></mods>')
      expect { sm = item.stanford_mods(nk, false) }.not_to raise_error
      expect(sm).to be_kind_of(Stanford::Mods::Record)
      expect(sm.genre.text).to eq('ape')
      expect(sm.pub_year_sort_str).to be_nil
    end
  end

  describe '#source_id' do
    let(:item) { instantiate_fixture('druid:ab123cd4567', described_class) }

    it 'source_id fetches from IdentityMetadata' do
      expect(item.source_id).to eq('google:STANFORD_342837261527')
      expect(item.source_id).to eq(item.identityMetadata.sourceId)
    end
  end

  describe '#source_id= (AKA set_source_id)' do
    let(:item) { instantiate_fixture('druid:ab123cd4567', described_class) }

    it 'raises on unsalvageable values' do
      expect { item.source_id = 'NotEnoughColons' }.to raise_error ArgumentError
      expect { item.source_id = ':EmptyFirstPart' }.to raise_error ArgumentError
      expect { item.source_id = 'WhitespaceSecondPart:   ' }.to raise_error ArgumentError
    end

    it 'sets the source_id' do
      item.source_id = 'fake:sourceid'
      expect(item.identityMetadata.sourceId).to eq('fake:sourceid')
    end

    it 'replaces the source_id if one exists' do
      item.source_id = 'fake:sourceid'
      expect(item.identityMetadata.sourceId).to eq('fake:sourceid')
      item.source_id = 'new:sourceid2'
      expect(item.identityMetadata.sourceId).to eq('new:sourceid2')
    end

    it 'does normalization via identityMetadata.sourceID=' do
      item.source_id = ' SourceX :  Value Y  '
      expect(item.source_id).to eq('SourceX:Value Y')
    end

    it 'allows colons in the value' do
      item.source_id = 'one:two:three'
      expect(item.source_id).to eq('one:two:three')
      item.source_id = 'one::two::three'
      expect(item.source_id).to eq('one::two::three')
    end

    it 'deletes the sourceId node on nil or empty-string' do
      item.source_id = nil
      expect(item.source_id).to be_nil
      item.source_id = 'fake:sourceid'
      expect(item.source_id).to eq('fake:sourceid')
      item.source_id = ''
      expect(item.source_id).to be_nil
    end
  end

  describe '#catkey' do
    let(:item) { instantiate_fixture('druid:ab123cd4567', described_class) }

    let(:current_catkey) { '129483625' }
    let(:new_catkey) { '999' }

    it 'gets the current catkey with the convenience method' do
      expect(item.catkey).to eq(current_catkey)
    end

    it 'gets the previous catkeys with the convenience method' do
      expect(item.previous_catkeys).to eq([])
    end

    it 'updates the catkey when one exists, and store the previous value (when there is no current history yet)' do
      expect(item.identityMetadata.otherId('catkey').length).to eq(1)
      expect(item.catkey).to eq(current_catkey)
      expect(item.previous_catkeys).to be_empty
      item.catkey = new_catkey
      expect(item.identityMetadata.otherId('catkey').length).to eq(1)
      expect(item.catkey).to eq(new_catkey)
      expect(item.previous_catkeys.length).to eq(1)
      expect(item.previous_catkeys).to eq([current_catkey])
    end

    it 'adds the catkey when it does not exist and never did' do
      item.identityMetadata.remove_other_Id('catkey')
      expect(item.identityMetadata.otherId('catkey').length).to eq(0)
      expect(item.catkey).to be_nil
      expect(item.previous_catkeys).to be_empty
      item.catkey = new_catkey
      expect(item.identityMetadata.otherId('catkey').length).to eq(1)
      expect(item.catkey).to eq(new_catkey)
      expect(item.previous_catkeys).to be_empty
    end

    it 'adds the catkey when it does not currently exist and there is a previous history (not touching that)' do
      item.identityMetadata.remove_other_Id('catkey')
      expect(item.identityMetadata.otherId('catkey').length).to eq(0)
      expect(item.catkey).to be_nil
      item.identityMetadata.add_otherId('previous_catkey:123') # add a couple previous catkeys
      item.identityMetadata.add_otherId('previous_catkey:456')
      expect(item.previous_catkeys.length).to eq(2)
      item.catkey = new_catkey
      expect(item.identityMetadata.otherId('catkey').length).to eq(1)
      expect(item.catkey).to eq(new_catkey)
      expect(item.previous_catkeys.length).to eq(2) # still two entries, nothing changed in the history
      expect(item.previous_catkeys).to eq(%w[123 456])
    end

    it 'removes the catkey from the XML when it is set to blank, but store the previously set value in the history' do
      expect(item.identityMetadata.otherId('catkey').length).to eq(1)
      expect(item.catkey).to eq(current_catkey)
      expect(item.previous_catkeys).to be_empty
      item.catkey = ''
      expect(item.identityMetadata.otherId('catkey').length).to eq(0)
      expect(item.catkey).to be_nil
      expect(item.previous_catkeys.length).to eq(1)
      expect(item.previous_catkeys).to eq([current_catkey])
    end

    it 'updates the catkey when one exists, and add the previous catkey id to the list' do
      previous_catkey = '111'
      item.identityMetadata.add_other_Id('previous_catkey', previous_catkey)
      expect(item.identityMetadata.otherId('catkey').length).to eq(1)
      expect(item.catkey).to eq(current_catkey)
      expect(item.previous_catkeys.length).to eq(1)
      expect(item.previous_catkeys.first).to eq(previous_catkey)
      item.catkey = new_catkey
      expect(item.identityMetadata.otherId('catkey').length).to eq(1)
      expect(item.catkey).to eq(new_catkey)
      expect(item.previous_catkeys.length).to eq(2)
      expect(item.previous_catkeys).to eq([previous_catkey, current_catkey])
    end

    it 'does not do anything if there is a previous catkey and you set the catkey to the same value' do
      expect(item.identityMetadata.otherId('catkey').length).to eq(1)
      expect(item.catkey).to eq(current_catkey)
      expect(item.previous_catkeys).to be_empty # no previous catkeys
      item.catkey = current_catkey
      expect(item.identityMetadata.otherId('catkey').length).to eq(1)
      expect(item.catkey).to eq(current_catkey)
      expect(item.previous_catkeys).to be_empty # still empty, we haven't updated the previous catkey since it was the same
    end
  end

  describe '#objectId=' do
    let(:item) { described_class.new }

    it 'is settable and gettable' do
      item.objectId = 'foo'
      expect(item.objectId).to eq 'foo'
    end
  end

  describe '#objectCreator=' do
    let(:item) { described_class.new }

    it 'is settable and gettable' do
      item.objectCreator = 'foo'
      expect(item.objectCreator).to eq ['foo']
    end
  end

  describe '#objectLabel=' do
    let(:item) { described_class.new }

    it 'is settable and gettable' do
      item.objectLabel = 'foo'
      expect(item.objectLabel).to eq ['foo']
    end
  end

  describe '#objectType=' do
    let(:item) { described_class.new }

    it 'is settable and gettable' do
      item.objectType = 'foo'
      expect(item.objectType).to eq ['foo']
    end
  end

  describe '#other_ids=' do
    let(:item) { described_class.new }

    it 'is settable and gettable' do
      item.other_ids = ['catkey:123', 'other:566']
      expect(item.otherId).to eq ['catkey:123', 'other:566']
    end
  end

  describe '#adapt_to_cmodel' do
    context 'for a Hydrus collection' do
      let(:item) { instantiate_fixture('druid:kq696sh3014', Dor::Abstract) }

      it 'adapts to the object type asserted in the identityMetadata' do
        expect(item.adapt_to_cmodel.class).to eq Dor::Collection
      end
    end

    context 'for a Hydrus item' do
      let(:item) { instantiate_fixture('druid:bb004bn8654', Dor::Abstract) }

      it 'adapts to the object type asserted in the identityMetadata' do
        expect(item.adapt_to_cmodel.class).to eq described_class
      end
    end

    context 'for a Dor item' do
      let(:item) { instantiate_fixture('druid:dc235vd9662', Dor::Abstract) }

      it 'adapts to the object type asserted in the identityMetadata' do
        expect(item.adapt_to_cmodel.class).to eq described_class
      end
    end

    context 'for an agreement' do
      let(:item) { instantiate_fixture('druid:dd327qr3670', Dor::Abstract) }

      it 'adapts to the object type asserted in the identityMetadata' do
        expect(item.adapt_to_cmodel.class).to eq Dor::Agreement
      end
    end

    context 'for an object without identityMetadata or a RELS-EXT model' do
      let(:item) { item_from_foxml(read_fixture('foxml_empty.xml'), Dor::Abstract) }

      it 'defaults to Dor::Item' do
        expect(item.adapt_to_cmodel.class).to eq described_class
      end
    end
  end
end
