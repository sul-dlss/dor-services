require 'spec_helper'

class ReleaseableItem < ActiveFedora::Base
  include Dor::Releaseable
  include Dor::Governable
  include Dor::Identifiable
end

describe Dor::Releaseable, :vcr do
  before :each do
    stub_config

    @bryar_trans_am_druid = 'druid:bb004bn8654'
    @bryar_trans_am = instantiate_fixture('druid:bb004bn8654', Dor::Item)
    @bryar_trans_am_admin_tags   = @bryar_trans_am.tags
    @bryar_trans_am_release_tags = @bryar_trans_am.release_nodes
    @array_of_times = ['2015-01-06 23:33:47Z', '2015-01-07 23:33:47Z', '2015-01-08 23:33:47Z', '2015-01-09 23:33:47Z'].map{ |x| Time.parse(x).iso8601 }
  end

  after :each do
    Dor::Config.pop!
  end

  describe 'Tag sorting, combining, and comparision functions' do

    before :each do
      @dummy_tags = [
        {'when' => @array_of_times[0], 'tag' => "Project: Jim Harbaugh's Finest Moments At Stanford.", 'what' => 'self'},
        {'when' => @array_of_times[1], 'tag' => "Project: Jim Harbaugh's Even Finer Moments At Michigan.", 'what' => 'collection'}]
    end

    it 'should return the most recent tag from an array of release tags' do
      expect(@bryar_trans_am.newest_release_tag_in_an_array(@dummy_tags)).to eq(@dummy_tags[1])
    end

    it 'should return nil when no tags apply' do
      expect(@bryar_trans_am.latest_applicable_release_tag_in_array(@dummy_tags, @bryar_trans_am_admin_tags)).to be_nil
    end

    it 'should return a tag when it does apply' do
      valid_tag = {'when' => @array_of_times[3], 'tag' => 'Project : Revs'}
      expect(@bryar_trans_am.latest_applicable_release_tag_in_array(@dummy_tags << valid_tag, @bryar_trans_am_admin_tags)).to eq(valid_tag)
    end

    it 'should return a valid tag even if there are non applicable older ones in front of it' do
      valid_tag = {'when' => @array_of_times[2], 'tag' => 'Project : Revs'}
      newer_no_op_tag = {'when' => @array_of_times[3], 'tag' => "Jim Harbaugh's Nonexistent Moments With The Raiders"}
      expect(@bryar_trans_am.latest_applicable_release_tag_in_array(@dummy_tags + [valid_tag, newer_no_op_tag], @bryar_trans_am_admin_tags)).to eq(valid_tag)
    end

    it 'should return the most recent tag when there are two valid tags' do
      valid_tag = {'when' => @array_of_times[2], 'tag' => 'Project : Revs'}
      newer_valid_tag = {'when' => @array_of_times[3], 'tag' => 'tag : test1'}
      expect(@bryar_trans_am.latest_applicable_release_tag_in_array(@dummy_tags + [valid_tag, newer_valid_tag], @bryar_trans_am_admin_tags)).to eq(newer_valid_tag)
    end

    it 'should recongize at a release tag with no tag attribute applies' do
      local_dummy_tag = {'when' => @array_of_times[0], 'who' => 'carrickr' }
      expect(@bryar_trans_am.does_release_tag_apply(local_dummy_tag, @bryar_trans_am_admin_tags)).to be_truthy
    end

    it 'should not require admin tags to be passed in' do
      local_dummy_tag = {'when' => @array_of_times[0], 'who' => 'carrickr' }
      expect(@bryar_trans_am.does_release_tag_apply(local_dummy_tag)).to be_truthy
      expect(@bryar_trans_am.does_release_tag_apply(@dummy_tags[0])).to be_falsey
    end

    it 'should return the latest tag for each key/target in a hash' do
      dummy_hash = {'Revs' => @dummy_tags, 'FRDA' => @dummy_tags}
      expect(@bryar_trans_am.get_newest_release_tag(dummy_hash)).to eq({'Revs' => @dummy_tags[1], 'FRDA' => @dummy_tags[1]})
    end

    it 'should only return tags for the specific what value' do
      expect(@bryar_trans_am.get_tags_for_what_value({'Revs' => @dummy_tags}, 'self')).to eq({'Revs' => [@dummy_tags[0]]})
      expect(@bryar_trans_am.get_tags_for_what_value({'Revs' => @dummy_tags, 'FRDA' => @dummy_tags}, 'collection')).to eq({'Revs' => [@dummy_tags[1]], 'FRDA' => [@dummy_tags[1]]})
    end

    it 'should combine two hashes of tags without overwriting any data' do
      h_one = {'Revs' => [@dummy_tags[0]]}
      h_two = {'Revs' => [@dummy_tags[1]], 'FRDA' => @dummy_tags}
      expected_result = {'Revs' => @dummy_tags, 'FRDA' => @dummy_tags}
      expect(@bryar_trans_am.combine_two_release_tag_hashes(h_one, h_two)).to eq(expected_result)
    end

    it 'should only return self release tags' do
      expect(@bryar_trans_am.get_self_release_tags({'Revs' => @dummy_tags, 'FRDA' => @dummy_tags, 'BV' => [@dummy_tags[1]]})).to eq({'Revs' => [@dummy_tags[0]], 'FRDA' => [@dummy_tags[0]]})
    end

  end

  # Warning:  Exercise care when rerecording these cassette, as these items are set up to have specific tags on them at the time of recording.
  # Other folks messing around in the dev environment might add or remove release tags that cause failures on these tests.
  # TODO: rework all VCR recs into conventional fixtures or re-record them for AF6.
  # If these tests fail, check not just the logic, but also the specific tags
  describe 'handling tags on objects and determining release status' do

    it 'should use only the most recent self tag to determine if an item is released, with no release tags on the collection' do
      VCR.use_cassette('should_use_only_the_most_recent_self_tag_to_determine_if_an_item_is_released_with_no_release_tags_on_the_collection') do
        item = instantiate_fixture("druid:vs298kg2555", Dor::Item)
        expect(item.released_for['Kurita']['release']).to be_truthy 
      end
    end

    it 'should deal with a bad collection record that references itself and not end up in an infinite loop by skipping the tag check for itself' do
      collection_druid='druid:wz243gf4151'
      collection = instantiate_fixture(collection_druid, Dor::Item)
      allow(collection).to receive(:collections).and_return([collection]) # force it to return itself as a member
      expect(collection.collections.first.id).to eq collection.id # confirm it is a member of itself
      expect(collection.released_for['Kurita']['release']).to be_truthy # we can still get the tags without going into an infinite loop
    end


    # This test takes an object with a self tag that is older and opposite the tag on this object's collection and ensures the self tag still is the one that is used to decide release status
    it 'should use the self tag over the collection tag to determine if an item is released, even if the collection tag is newer' do
      skip 'VCR cassette recorded on only one (old) version of ActiveFedora.  Stub methods or record on both AF5 and AF6'
      VCR.use_cassette('releaseable_self_over_collection') do
        item = Dor::Item.find('druid:bb537hc4022')
        expect(item.released_for['Kurita']['release']).to be_falsey
      end
    end

    # This test looks at an item whose only tags are on the collection and ensures the most recent one wins
    it 'should use only most the recent collection tag if no self tags are present' do
      skip 'VCR cassette recorded on only one (old) version of ActiveFedora.  Stub methods or record on both AF5 and AF6'
      VCR.use_cassette('releaseable_most_recent_collection_tag_wins') do
        item = Dor::Item.find('druid:bc566xq6031')
        expect(item.release_tags).to eq({})
        expect(item.released_for['Kurita']['release']).to be_truthy
      end
    end

    # A collection whose only tag is to release a what=collection should also release the collection object itself
    it 'a tag with what=collection should release the collection item, assuming it is not blocked by a self tag' do
      skip 'VCR cassette recorded on only one (old) version of ActiveFedora.  Stub methods or record on both AF5 and AF6'
      VCR.use_cassette('releaseable_collection_tag_releases_collection_object') do
        item = Dor::Item.find('druid:wz243gf4151')
        expect(item.released_for['Kurita']['release']).to be_truthy
      end
    end

    # Here we have an object governed by both the Marcus Chambers, druid:wz243gf4151, Collection and the Revs Collection, druid:nt028fd5773
    # When determining if an item is released, it should look at both collections and pick the most recent timestamp
    it 'should look all collections and sets that an item is a member of' do
      skip 'VCR cassette recorded on only one (old) version of ActiveFedora.  Stub methods or record on both AF5 and AF6'
      VCR.use_cassette('releaseable_multiple_collections') do
        item = Dor::Item.find('druid:dc235vd9662')
        expect(item.released_for['Atago']['release']).to be_truthy
        chambers_collection = Dor::Item.find('druid:wz243gf4151')
        expect(chambers_collection.release_tags['Atago']).to eq [{'what' => 'collection', 'who' => 'carrickr', 'when' => Time.parse('2015-01-21 22:37:21Z').iso8601, 'release' => true}]
        revs_collection = Dor::Item.find('druid:nt028fd5773')
        expect(revs_collection.release_tags['Atago']).to eq([{'what' => 'collection', 'who' => 'carrickr', 'when' => Time.parse('2015-01-21 22:37:40Z').iso8601, 'release' => false}])
      end
    end

    # If an items release is controlled with the tag= attr, meaning that only items with that administrative tag are released, that should be respected
    it 'should respect the tag= attr and apply it when releasing' do
      skip 'VCR cassette recorded on only one (old) version of ActiveFedora.  Stub methods or record on both AF5 and AF6'
      VCR.use_cassette('releaseable_respect_admin_tagging') do
        chambers_collection = Dor::Item.find('druid:wz243gf4151')
        exp_result = [{'what' => 'collection', 'who' => 'carrickr', 'tag' => 'Project : ReleaseSpecTesting : Batch1', 'when' => Time.parse('2015-01-21 22:46:22Z').iso8601, 'release' => true}]
        expect(chambers_collection.release_tags['Mogami']).to eq exp_result
        item_with_this_admin_tag = Dor::Item.find('druid:dc235vd9662')
        expect(item_with_this_admin_tag.tags).to include 'Project : ReleaseSpecTesting : Batch1'
        expect(item_with_this_admin_tag.released_for['Mogami']['release']).to be_truthy
        item_without_this_admin_tag = Dor::Item.find('druid:bc566xq6031')
        expect(item_without_this_admin_tag.tags).not_to include('Project : ReleaseSpecTesting : Batch1')
        expect(item_without_this_admin_tag.released_for['Mogami']).to be_nil
      end
    end

    it 'should return release xml for an item as string of elements wrapped in a ReleaseDigestRoot' do
      skip 'VCR cassette recorded on only one (old) version of ActiveFedora.  Stub methods or record on both AF5 and AF6'
      VCR.use_cassette('releaseable_release_xml') do
        item = Dor::Item.find('druid:dc235vd9662')
        release_xml = item.generate_release_xml
        expect(release_xml).to be_a(String)
        true_or_false = %w(true false)
        xml_obj = Nokogiri(release_xml)
        xml_obj.xpath('//release').each do |release_node|
          expect(release_node.name).to eq('release') # Well, duh
          expect(release_node.attributes.keys).to eq(['to'])
          expect(release_node.attributes['to'].value).to be_a(String)
          expect(true_or_false.include?(release_node.children.text)).to be_truthy
        end
      end
    end

  end
end

describe 'Adding release nodes', :vcr do
  before :each do
    stub_config

    @item = instantiate_fixture('druid:bb004bn8654', Dor::Item)
    @release_nodes = @item.release_nodes
    @le_mans_druid = 'druid:dc235vd9662'
  end

  after :all do
    Dor::Config.pop!
  end

  describe 'Adding tags and workflows' do
    it 'should release an item with one release tag supplied' do
      allow(@item).to receive(:save).and_return(true) # stud out the true in that it we lack a connection to solr
      expect(@item).to receive(:create_workflow).with('releaseWF') # Make sure releaseWF is called
      expect(@item).to receive(:add_release_node).once
      expect(@item.add_release_nodes_and_start_releaseWF({:release => true, :what => 'self', :who => 'carrickr', :to => 'FRDA'})).to eq(nil) # Should run and return void
    end
    it 'should release an item with multiple release tags supplied' do
      allow(@item).to receive(:save).and_return(true) # stud out the true in that it we lack a connection to solr
      expect(@item).to receive(:create_workflow).with('releaseWF') # Make sure releaseWF is called
      expect(@item).to receive(:add_release_node).twice
      tags = [{:release => true, :what => 'self', :who => 'carrickr', :to => 'FRDA'}, {:release => true, :what => 'self', :who => 'carrickr', :to => 'Revs'}]
      expect(@item.add_release_nodes_and_start_releaseWF(tags)).to eq(nil) # Should run and return void
    end
  end

  describe 'valid_release_attributes' do
    before :each do
      @args = {:when => '2015-01-05T23:23:45Z', :who => 'carrickr', :to => 'Revs', :what => 'collection', :tag => 'Project:Fitch:Batch2'}
    end
    it 'should raise an error when :who, :to, :what are missing or are not strings' do
      expect{@item.valid_release_attributes(true,  @args.merge(:who  => nil ))}.to raise_error(ArgumentError)
      expect{@item.valid_release_attributes(false, @args.merge(:to   => nil ))}.to raise_error(ArgumentError)
      expect{@item.valid_release_attributes(true,  @args.merge(:what => nil ))}.to raise_error(ArgumentError)
      expect{@item.valid_release_attributes(true,  @args.merge(:who  => 1   ))}.to raise_error(ArgumentError)
      expect{@item.valid_release_attributes(true,  @args.merge(:to   => true))}.to raise_error(ArgumentError)
      expect{@item.valid_release_attributes(false, @args.merge(:what => %w(i am an array)))}.to raise_error(ArgumentError)
    end
    it 'should not raise an error when :what is self or collection' do
      expect(@item.valid_release_attributes(false, @args)).to be true
      expect(@item.valid_release_attributes(true,  @args.merge(:what => 'self'))).to be true
    end
    it 'raises an argument error when :what is a string, but is not self or collection' do
      expect{@item.valid_release_attributes(true, @args.merge(:what => 'foo'))}.to raise_error(ArgumentError)
    end
    it 'should add a tag when all attributes are properly provided, and drop the invalid <tag> attribute' do
      VCR.use_cassette('simple_release_tag_add_success_test') do
        tag_xml=@item.add_release_node(true, @args.merge(:what => 'self'))
        expect(tag_xml).to be_a_kind_of(Nokogiri::XML::Element)
        expect(tag_xml.to_xml).to eq("<release when=\"2015-01-05T23:23:45Z\" who=\"carrickr\" to=\"Revs\" what=\"self\">true</release>")
      end
    end
    it 'should fail to add a release node when there is an attribute error' do
      VCR.use_cassette('simple_release_tag_add_success_test') do
        expect{@item.add_release_node(true,  {:who => nil, :to => 'Revs', :what => 'self'})}.to raise_error(ArgumentError) # who is not a string
        expect{@item.add_release_node(true,  {:who => nil, :to => 'Revs', :what => 'unknown_value'})}.to raise_error(ArgumentError) # who is not a string
        expect{@item.add_release_node(1, @args)}.to raise_error(ArgumentError) # invalid release value
      end
    end
    it 'should drop all invalid attributes passed in' do
      VCR.use_cassette('simple_release_tag_add_success_test') do
        new_tag="<release when=\"2016-01-05T23:23:45Z\" who=\"petucket\" to=\"Revs\" what=\"self\">true</release>"
        expect(@item.identityMetadata.to_xml).to_not include new_tag
        @item.add_release_node(true,  {:when => '2016-01-05T23:23:45Z', :who => 'petucket', :to=> 'Revs', :what=> 'self', :blop => "something", :tag => 'Revs', 'something_else' => 'whatup'})
        expect(@item.identityMetadata.to_xml).to include new_tag
      end
    end    
    it 'should return true when valid_release_attributes is called with valid attributes and no tag attribute' do
      @args.delete :tag
      expect(@item.valid_release_attributes(true, @args)).to be true
    end
    it 'should return true when valid_release_attributes is called with valid attributes and tag attribute' do
      expect(@item.valid_release_attributes(true, @args)).to be true
    end
    it 'should raise an error when valid_release_attributes is called with a tag content that is not a boolean' do
      expect{@item.valid_release_attributes(1, @args)}.to raise_error(ArgumentError)
    end
  end

  it 'should return no release nodes for an item that does n0t have any' do
    no_release_nodes_item = instantiate_fixture('druid:qv648vd4392', Dor::Item)
    expect(no_release_nodes_item.release_nodes).to eq({})
  end

  it 'should return the releases for an item that has release tags' do
    expect(@release_nodes).to be_a_kind_of(Hash)
    exp_result = {'Revs' => [
      {'tag' => 'true', 'what' => 'collection', 'when' => Time.parse('2015-01-06 23:33:47Z'), 'who' => 'carrickr', 'release' => true},
      {'tag' => 'true', 'what' => 'self', 'when' => Time.parse('2015-01-06 23:33:54Z'), 'who' => 'carrickr', 'release' => true},
      {'tag' => 'Project : Fitch : Batch2', 'what' => 'self', 'when' => Time.parse('2015-01-06 23:40:01Z'), 'who' => 'carrickr', 'release' => false}]}
    expect(@release_nodes).to eq exp_result
  end

  it 'should return a hash created from a single release tag' do
    n = Nokogiri('<release to="Revs" what="collection" when="2015-01-06T23:33:47Z" who="carrickr">true</release>').xpath('//release')[0]
    exp_result = {:to => 'Revs', :attrs => {'what' => 'collection', 'when' => Time.parse('2015-01-06 23:33:47Z'), 'who' => 'carrickr', 'release' => true}}
    expect(@item.release_tag_node_to_hash(n)).to eq exp_result
    n = Nokogiri('<release tag="Project : Fitch: Batch1" to="Revs" what="collection" when="2015-01-06T23:33:47Z" who="carrickr">true</release>').xpath('//release')[0]
    exp_result = {:to => 'Revs', :attrs => {'tag' => 'Project : Fitch: Batch1', 'what' => 'collection', 'when' => Time.parse('2015-01-06 23:33:47Z'), 'who' => 'carrickr', 'release' => true}}
    expect(@item.release_tag_node_to_hash(n)).to eq exp_result
  end

  describe 'Getting XML From Purl' do
    it 'should return the full url for a druid' do
      expect(@item.form_purl_url).to eq("https://#{Dor::Config.stacks.document_cache_host}/bb004bn8654.xml")
    end

    it 'should get the purl xml for a druid' do
      VCR.use_cassette('fetch_purl_test_xml') do
        x = @item.get_xml_from_purl
        expect(x).to be_a(Nokogiri::HTML::Document)
        expect(x.at_xpath('//html/body/publicobject').attr('id')).to eq(@item.id)
      end
    end

    it 'should not raise an error for a 404 when attempted to obtain a purl' do
      VCR.use_cassette('purl_404') do
        expect(Dor.logger).to receive(:warn).once
        expect(@item).to receive(:id).and_return('druid:IAmABadDruid').at_least(:once)
        expect(@item.get_xml_from_purl).to be_a(Nokogiri::HTML::Document)
      end
    end

    it 'should add in release tags as false for targets that are listed on the purl but not in new tag generation' do
      VCR.use_cassette('fetch_le_mans_purl') do
        item = instantiate_fixture(@le_mans_druid, Dor::Item)
        x = item.get_xml_from_purl
        generated_tags = {} # pretend no tags were found in the most recent dor object, so all tags in the purl should return false
        tags_currently_in_purl = item.get_release_tags_from_purl_xml(x)  # These are the tags currently in purl
        final_result_tags = item.add_tags_from_purl(generated_tags)      # Final result of dor and purl tags
        expect(final_result_tags.keys).to match(tags_currently_in_purl)  # all tags currently in purl should be reflected
        final_result_tags.keys.each do |tag|
          expect(final_result_tags[tag]).to match({'release' => false})  # all tags should be false for their releas
        end
      end
    end

    it 'should add in release tags as false for targets that are listed on the purl but not in new tag generation' do
      VCR.use_cassette('fetch_le_mans_purl') do
        item = instantiate_fixture(@le_mans_druid, Dor::Item)
        x = item.get_xml_from_purl
        generated_tags = {'Kurita' => {'release' => true}}              # only kurita has returned as true
        tags_currently_in_purl = item.get_release_tags_from_purl_xml(x) # These are the tags currently in purl
        final_result_tags = item.add_tags_from_purl(generated_tags)     # Final result of dor and purl tags
        expect(final_result_tags.keys).to match(tags_currently_in_purl) # all tags currently in purl should be reflected
        final_result_tags.keys.each do |tag|
          expect(final_result_tags[tag]).to match('release' => false) if tag != 'Kurita' # Kurita should still be true
        end
        expect(final_result_tags['Kurita']).to match('release' => true)
      end
    end
  end
end

describe 'to_solr' do
  before(:each) { stub_config   }
  after(:each)  { unstub_config }

  before :each do
    @rlsbl_item = instantiate_fixture('druid:ab123cd4567', ReleaseableItem)
  end

  it 'should solrize release tags' do
    released_for_info = {
      'Project' => {'release'=>true}, 'test_target' => {'release'=>true}, 'test_nontarget' => {'release'=>false}
    }
    allow(@rlsbl_item).to receive(:released_for).and_return(released_for_info)
    solr_doc = @rlsbl_item.to_solr
    released_to_field_name = Solrizer.solr_name('released_to', :symbol)
    expect(solr_doc).to match a_hash_including({released_to_field_name => %w(Project test_target)})
  end
end