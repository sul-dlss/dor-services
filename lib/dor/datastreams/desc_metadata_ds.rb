# frozen_string_literal: true

require 'stanford-mods'

module Dor
  # Descriptive metadata
  class DescMetadataDS < ActiveFedora::OmDatastream
    MODS_NS = 'http://www.loc.gov/mods/v3'
    MODS_HEADER_CONFIG = {
      'xmlns' => MODS_NS,
      'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
      version: '3.6',
      'xsi:schemaLocation' => 'http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-6.xsd'
    }.freeze

    set_terminology do |t|
      t.root path: 'mods', xmlns: MODS_NS, index_as: [:not_searchable]
      t.originInfo  index_as: [:not_searchable] do
        t.publisher index_as: [:stored_searchable]
        t.date_created path: 'dateCreated', index_as: [:stored_searchable]
        t.place index_as: [:not_searchable] do
          t.placeTerm attributes: { type: 'text' }, index_as: [:stored_searchable]
        end
      end
      t.subject(index_as: [:not_searchable]) do
        t.geographic index_as: %i[symbol stored_searchable]
        t.topic      index_as: %i[symbol stored_searchable]
        t.temporal   index_as: [:stored_searchable]
      end
      t.title_info(path: 'titleInfo') do
        t.main_title(index_as: [:symbol], path: 'title', label: 'title') do
          t.main_title_lang(path: { attribute: 'xml:lang' })
        end
      end
      t.language do
        t.languageTerm attributes: { type: 'code', authority: 'iso639-2b' }, index_as: [:not_searchable]
      end
      t.coordinates index_as: [:symbol]
      t.extent      index_as: [:symbol]
      t.scale       index_as: [:symbol]
      t.topic       index_as: %i[symbol stored_searchable]
      t.abstract    index_as: [:stored_searchable]

      # 'identifier' conflicts with identityMetadata indexing. Explicitly namespace this one value
      # until we use #prefix to automatically namespace them for us.
      t.mods_identifier path: 'identifier', index_as: %i[symbol stored_searchable]
    end

    def self.xml_template
      Nokogiri::XML::Builder.new do |xml|
        xml.mods(MODS_HEADER_CONFIG) do
          xml.titleInfo do
            xml.title
          end
        end
      end.doc
    end

    def mods_title
      term_values(:title_info, :main_title).first
    end

    def mods_title=(val)
      update_values(%i[title_info main_title] => val)
    end

    # intended for read-access, "as SearchWorks would see it", mostly for to_solr()
    # @param [Nokogiri::XML::Document] content Nokogiri descMetadata document (overriding internal data)
    # @param [boolean] ns_aware namespace awareness toggle for from_nk_node()
    def stanford_mods(content = nil, ns_aware = true)
      @stanford_mods ||= begin
        m = Stanford::Mods::Record.new
        desc = content.nil? ? ng_xml : content
        m.from_nk_node(desc.root, ns_aware)
        m
      end
    end

    def full_title
      stanford_mods.sw_title_display
    end

    # maintain AF < 8 indexing behavior
    def prefix
      ''
    end
  end
end
