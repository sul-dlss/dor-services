# frozen_string_literal: true

module Dor
  class RightsMetadataDS < ActiveFedora::OmDatastream
    require 'dor/rights_auth'

    # This is separate from default_object_rights because
    # (1) we cannot default to such a permissive state
    # (2) this is real, not default
    #
    # Ultimately, default_object_rights should go away and APOs also use an instantation of this class

    set_terminology do |t|
      t.root path: 'rightsMetadata', index_as: [:not_searchable]
      t.copyright path: 'copyright/human', index_as: [:symbol]
      t.use_statement path: '/use/human[@type=\'useAndReproduction\']', index_as: [:symbol]

      t.use do
        t.machine
        t.human
      end

      t._read(path: 'access', attributes: { type: 'read' }) do
        t.machine do
          t.embargo_release_date(path: 'embargoReleaseDate', type: :time)
        end
      end

      t.embargo_release_date(proxy: %i[_read machine embargo_release_date])

      t.creative_commons path: '/use/machine[@type=\'creativeCommons\']', type: 'creativeCommons' do
        t.uri path: '@uri'
      end
      t.creative_commons_human path: '/use/human[@type=\'creativeCommons\']'
      t.open_data_commons path: '/use/machine[@type=\'openDataCommons\']', type: 'openDataCommons' do
        t.uri path: '@uri'
      end
      t.open_data_commons_human path: '/use/human[@type=\'openDataCommons\']'
    end

    def self.xml_template
      Nokogiri::XML::Builder.new do |xml|
        xml.rightsMetadata do
          xml.access(type: 'discover') do
            xml.machine { xml.none }
          end
          xml.access(type: 'read') do
            xml.machine { xml.none } # dark default
          end
          xml.use do
            xml.human(type: 'useAndReproduction')
            xml.human(type: 'creativeCommons')
            xml.machine(type: 'creativeCommons', uri: '')
            xml.human(type: 'openDataCommons')
            xml.machine(type: 'openDataCommons', uri: '')
          end
          xml.copyright { xml.human }
        end
      end.doc
    end

    RIGHTS_TYPE_CODES = {
      'world' => 'World',
      'world-nd' => 'World (no-download)',
      'stanford' => 'Stanford',
      'stanford-nd' => 'Stanford (no-download)',
      'loc:spec' => 'Location: Special Collections',
      'loc:music' => 'Location: Music Library',
      'loc:ars' => 'Location: Archive of Recorded Sound',
      'loc:art' => 'Location: Art Library',
      'loc:hoover' => 'Location: Hoover Library',
      'loc:m&m' => 'Location: Media & Microtext',
      'dark' => 'Dark (Preserve Only)',
      'none' => 'Citation Only'
    }.freeze

    # just a wrapper to invalidate @dra_object
    def content=(xml)
      @dra_object = nil
      super
    end

    def dra_object
      @dra_object ||= Dor::RightsAuth.parse(ng_xml, true)
    end

    # key is the rights type code, used by e.g. RightsMetadataDS#set_read_rights and AdminPolicyObject#default_rights=
    # value is the human-readable string, used for indexing, and for things like building select lists in the argo UI.
    def self.valid_rights_types
      RIGHTS_TYPE_CODES.keys
    end

    def self.valid_rights_type?(rights)
      RightsMetadataDS.valid_rights_types.include? rights
    end

    # a helper method for setting up well-structured rights_xml based on a rights type code
    # @param rights_xml [ng_xml] a nokogiri xml (ruby) object that represents the rights xml for a DOR object
    # @param rights_type [string] a recognized rights type code ('world', 'dark', 'loc:spec', etc)
    def self.upd_rights_xml_for_rights_type(rights_xml, rights_type)
      label = rights_type == 'dark' ? 'none' : 'world'
      rights_xml.search('//rightsMetadata/access[@type=\'discover\']/machine').each do |node|
        node.children.remove
        node.add_child Nokogiri::XML::Node.new(label, rights_xml)
      end

      rights_xml.search('//rightsMetadata/access[@type=\'read\']').each do |node|
        node.children.remove
        machine_node = Nokogiri::XML::Node.new('machine', rights_xml)
        node.add_child(machine_node)
        if rights_type.start_with?('world')
          world_node = Nokogiri::XML::Node.new('world', rights_xml)
          world_node.set_attribute('rule', 'no-download') if rights_type.end_with?('-nd')
          machine_node.add_child(world_node)
        elsif rights_type.start_with?('stanford')
          group_node = Nokogiri::XML::Node.new('group', rights_xml)
          group_node.content = 'stanford'
          group_node.set_attribute('rule', 'no-download') if rights_type.end_with?('-nd')
          machine_node.add_child(group_node)
        elsif rights_type.start_with?('loc:')
          loc_node = Nokogiri::XML::Node.new('location', rights_xml)
          loc_node.content = rights_type.split(':').last
          machine_node.add_child(loc_node)
        else # we know it is none or dark by the argument filter (first line)
          machine_node.add_child Nokogiri::XML::Node.new('none', rights_xml)
        end
      end
    end

    # @param rights [string] archetypical rights to assign: 'world', 'stanford', 'none', 'dark', etc
    # slight misnomer: also sets discover rights!
    # TODO: convert xpath reads to dra_object calls
    def set_read_rights(rights)
      raise(ArgumentError, "Argument '#{rights}' is not a recognized value") unless RightsMetadataDS.valid_rights_type? rights

      rights_xml = ng_xml
      if rights_xml.search('//rightsMetadata/access[@type=\'read\']').length == 0
        raise('The rights metadata stream doesnt contain an entry for machine read permissions. Consider populating it from the APO before trying to change it.')
      end

      ng_xml_will_change!
      RightsMetadataDS.upd_rights_xml_for_rights_type(rights_xml, rights)

      @dra_object = nil # until TODO complete, we'll expect to have to reparse after modification
    end

    def to_solr(solr_doc = {}, *args)
      solr_doc = super(solr_doc, *args)
      dra = dra_object
      solr_doc['rights_primary_ssi'] = dra.index_elements[:primary]
      solr_doc['rights_errors_ssim'] = dra.index_elements[:errors] if dra.index_elements[:errors].size > 0
      solr_doc['rights_characteristics_ssim'] = dra.index_elements[:terms] if dra.index_elements[:terms].size > 0

      solr_doc['rights_descriptions_ssim'] = [
        dra.index_elements[:primary],

        (dra.index_elements[:obj_locations_qualified] || []).map do |rights_info|
          rule_suffix = rights_info[:rule] ? " (#{rights_info[:rule]})" : ''
          "location: #{rights_info[:location]}#{rule_suffix}"
        end,
        (dra.index_elements[:file_locations_qualified] || []).map do |rights_info|
          rule_suffix = rights_info[:rule] ? " (#{rights_info[:rule]})" : ''
          "location: #{rights_info[:location]} (file)#{rule_suffix}"
        end,

        (dra.index_elements[:obj_agents_qualified] || []).map do |rights_info|
          rule_suffix = rights_info[:rule] ? " (#{rights_info[:rule]})" : ''
          "agent: #{rights_info[:agent]}#{rule_suffix}"
        end,
        (dra.index_elements[:file_agents_qualified] || []).map do |rights_info|
          rule_suffix = rights_info[:rule] ? " (#{rights_info[:rule]})" : ''
          "agent: #{rights_info[:agent]} (file)#{rule_suffix}"
        end,

        (dra.index_elements[:obj_groups_qualified] || []).map do |rights_info|
          rule_suffix = rights_info[:rule] ? " (#{rights_info[:rule]})" : ''
          "#{rights_info[:group]}#{rule_suffix}"
        end,
        (dra.index_elements[:file_groups_qualified] || []).map do |rights_info|
          rule_suffix = rights_info[:rule] ? " (#{rights_info[:rule]})" : ''
          "#{rights_info[:group]} (file)#{rule_suffix}"
        end,

        (dra.index_elements[:obj_world_qualified] || []).map do |rights_info|
          rule_suffix = rights_info[:rule] ? " (#{rights_info[:rule]})" : ''
          "world#{rule_suffix}"
        end,
        (dra.index_elements[:file_world_qualified] || []).map do |rights_info|
          rule_suffix = rights_info[:rule] ? " (#{rights_info[:rule]})" : ''
          "world (file)#{rule_suffix}"
        end
      ].flatten.uniq

      # these two values are returned by index_elements[:primary], but are just a less granular version of
      # what the other more specific fields return, so discard them
      solr_doc['rights_descriptions_ssim'] -= %w[access_restricted access_restricted_qualified world_qualified]
      solr_doc['rights_descriptions_ssim'] += ['dark (file)'] if dra.index_elements[:terms].include? 'none_read_file'

      solr_doc['obj_rights_locations_ssim'] = dra.index_elements[:obj_locations] unless dra.index_elements[:obj_locations].blank?
      solr_doc['file_rights_locations_ssim'] = dra.index_elements[:file_locations] unless dra.index_elements[:file_locations].blank?
      solr_doc['obj_rights_agents_ssim'] = dra.index_elements[:obj_agents] unless dra.index_elements[:obj_agents].blank?
      solr_doc['file_rights_agents_ssim'] = dra.index_elements[:file_agents] unless dra.index_elements[:file_agents].blank?

      # suppress empties
      %w(use_statement_ssim copyright_ssim).each do |key|
        solr_doc[key] = solr_doc[key].reject(&:blank?).flatten unless solr_doc[key].nil?
      end
      add_solr_value(solr_doc, 'use_license_machine', use_license.first, :string, [:stored_sortable])
      add_solr_value(solr_doc, 'use_licenses_machine', use_license, :symbol, [:stored_searchable])

      solr_doc
    end

    def use_license
      use_license = []
      use_license += Array(creative_commons)
      use_license += Array(open_data_commons)

      use_license.reject(&:blank?)
    end

    # maintain AF < 8 indexing behavior
    def prefix
      ''
    end

    def rights
      xml = ng_xml
      if xml.search('//rightsMetadata/access[@type=\'read\']/machine/group').length == 1
        'Stanford'
      elsif xml.search('//rightsMetadata/access[@type=\'read\']/machine/world').length == 1
        'World'
      elsif xml.search('//rightsMetadata/access[@type=\'discover\']/machine/none').length == 1
        'Dark'
      else
        'None'
      end
    end
  end
end
