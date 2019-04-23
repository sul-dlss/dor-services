# frozen_string_literal: true

module Dor
  class IdentityMetadataDS < ActiveFedora::OmDatastream
    include SolrDocHelper

    # ids for previous and current catkeys
    CATKEY_TYPE_ID = 'catkey'
    PREVIOUS_CATKEY_TYPE_ID = 'previous_catkey'

    set_terminology do |t|
      t.root(path: 'identityMetadata')
      t.objectId   index_as: [:symbol]
      t.objectType index_as: [:symbol]
      t.objectLabel
      t.citationCreator
      t.sourceId
      t.otherId(path: 'otherId') do
        t.name_(path: { attribute: 'name' })
      end
      t.agreementId index_as: %i[stored_searchable symbol]
      t.tag index_as: [:symbol]
      t.citationTitle
      t.objectCreator index_as: %i[stored_searchable symbol]
      t.adminPolicy   index_as: [:not_searchable]
    end

    define_template :value do |builder, name, value, attrs|
      builder.send(name.to_sym, value, attrs)
    end

    def self.xml_template
      Nokogiri::XML('<identityMetadata/>')
    end

    def add_value(name, value, attrs = {})
      ng_xml_will_change!
      add_child_node(ng_xml.root, :value, name, value, attrs)
    end

    def objectId
      find_by_terms(:objectId).text
    end

    def sourceId
      node = find_by_terms(:sourceId).first
      node ? [node['source'], node.text].join(':') : nil
    end
    alias source_id sourceId

    # @param  [String, Nil] value The value to set or a nil/empty string to delete sourceId node
    # @return [String, Nil] The same value, as per Ruby convention for assignment operators
    # @note The actual values assigned will have leading/trailing whitespace stripped.
    def sourceId=(value)
      ng_xml_will_change!
      node = find_by_terms(:sourceId).first
      unless value.present? # so setting it to '' is the same as removal: worth documenting maybe?
        node&.remove
        return nil
      end
      parts = value.split(':', 2).map(&:strip)
      raise ArgumentError, "Source ID must follow the format 'namespace:value', not '#{value}'" unless
        parts.length == 2 && parts[0].present? && parts[1].present?

      node ||= ng_xml.root.add_child('<sourceId/>').first
      node['source'] = parts[0]
      node.content = parts[1]
    end
    alias source_id= sourceId=

    def tags
      ng_xml.search('//tag').collect(&:content)
    end

    # helper method to get just the content type tag
    def content_type_tag
      content_tag = tags.select { |tag| tag.include?('Process : Content Type') }
      content_tag.size == 1 ? content_tag[0].split(':').last.strip : ''
    end

    def otherId(type = nil)
      result = find_by_terms(:otherId).to_a
      if type.nil?
        result.collect { |n| [n['name'], n.text].join(':') }
      else
        result.select { |n| n['name'] == type }.collect(&:text)
      end
    end

    def add_otherId(other_id)
      ng_xml_will_change!
      (name, val) = other_id.split(/:/, 2)
      node = ng_xml.root.add_child('<otherId/>').first
      node['name'] = name
      node.content = val
      node
    end

    def add_other_Id(type, val)
      raise 'There is an existing entry for ' + type + ', consider using update_other_Id().' if otherId(type).length > 0

      add_otherId(type + ':' + val)
    end

    def update_other_Id(type, new_val, val = nil)
      ng_xml.search('//otherId[@name=\'' + type + '\']')
            .select { |node| val.nil? || node.content == val }
            .each { ng_xml_will_change! }
            .each { |node| node.content = new_val }
            .any?
    end

    def remove_other_Id(type, val = nil)
      ng_xml.search('//otherId[@name=\'' + type + '\']')
            .select { |node| val.nil? || node.content == val }
            .each { ng_xml_will_change! }
            .each(&:remove)
            .any?
    end

    # Convenience method to get the current catkey
    # @return [String] current catkey value (or nil if none found)
    def catkey
      otherId(CATKEY_TYPE_ID).first
    end

    # Convenience method to set the catkey
    # @param  [String] val the new source identifier
    # @return [String] same value, as per Ruby assignment convention
    def catkey=(val)
      # if there was already a catkey in the record, store that in the "previous" spot (assuming there is no change)
      add_otherId("#{PREVIOUS_CATKEY_TYPE_ID}:#{catkey}") if val != catkey && !catkey.blank?

      if val.blank? # if we are setting the catkey to blank, remove the node from XML
        remove_other_Id(CATKEY_TYPE_ID)
      elsif catkey.blank? # if there is no current catkey, then add it
        add_other_Id(CATKEY_TYPE_ID, val)
      else # if there is a current catkey, update the current catkey to the new value
        update_other_Id(CATKEY_TYPE_ID, val)
      end

      val
    end

    # Convenience method to get the previous catkeys (will be an array)
    # @return [Array] previous catkey values (empty array if none found)
    def previous_catkeys
      otherId(PREVIOUS_CATKEY_TYPE_ID)
    end

    def to_solr(solr_doc = {}, *args)
      solr_doc = super(solr_doc, *args)

      if digital_object.respond_to?(:profile)
        digital_object.profile.each_pair do |property, value|
          add_solr_value(solr_doc, property.underscore, value, (property =~ /Date/ ? :date : :symbol), [:stored_searchable])
        end
      end

      if sourceId.present?
        (name, id) = sourceId.split(/:/, 2)
        add_solr_value(solr_doc, 'dor_id', id, :symbol, [:stored_searchable])
        add_solr_value(solr_doc, 'identifier', sourceId, :symbol, [:stored_searchable])
        add_solr_value(solr_doc, 'source_id', sourceId, :symbol, [])
      end
      otherId.compact.each do |qid|
        # this section will solrize barcode and catkey, which live in otherId
        (name, id) = qid.split(/:/, 2)
        add_solr_value(solr_doc, 'dor_id', id, :symbol, [:stored_searchable])
        add_solr_value(solr_doc, 'identifier', qid, :symbol, [:stored_searchable])
        add_solr_value(solr_doc, "#{name}_id", id, :symbol, [])
      end

      # do some stuff to make tags in general and project tags specifically more easily searchable and facetable
      find_by_terms(:tag).each do |tag|
        (prefix, rest) = tag.text.split(/:/, 2)
        prefix = prefix.downcase.strip.gsub(/\s/, '_')
        unless rest.nil?
          # this part will index a value in a field specific to the tag, e.g. registered_by_tag_*,
          # book_tag_*, project_tag_*, remediated_by_tag_*, etc.  project_tag_* and registered_by_tag_*
          # definitley get used, but most don't.  we can limit the prefixes that get solrized if things
          # get out of hand.
          add_solr_value(solr_doc, "#{prefix}_tag", rest.strip, :symbol, [])
        end

        # solrize each possible prefix for the tag, inclusive of the full tag.
        # e.g., for a tag such as "A : B : C", this will solrize to an _ssim field
        # that contains ["A",  "A : B",  "A : B : C"].
        tag_parts = tag.text.split(/:/)
        progressive_tag_prefix = ''
        tag_parts.each_with_index do |part, index|
          progressive_tag_prefix += ' : ' if index > 0
          progressive_tag_prefix += part.strip
          add_solr_value(solr_doc, 'exploded_tag', progressive_tag_prefix, :symbol, [])
        end
      end

      solr_doc
    end

    # maintain AF < 8 indexing behavior
    def prefix
      ''
    end
  end # class
end
