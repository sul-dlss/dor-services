# frozen_string_literal: true

module Dor
  # Represents the Fedora 3 datastream that hold provenance metadata
  class ProvenanceMetadataDS < ActiveFedora::OmDatastream
    # This provides the prefix for the solr fields generated by ActiveFedora.
    # Since we don't want a prefix, we override this to return an empty string.
    def prefix
      ''
    end
  end
end
