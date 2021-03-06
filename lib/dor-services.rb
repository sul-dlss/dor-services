# frozen_string_literal: true

require 'active_fedora'
require 'active_fedora/version'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/object/blank'
require 'deprecation'

module Dor
  extend ActiveSupport::Autoload
  @@registered_classes = {}
  mattr_reader :registered_classes

  class << self
    def configure(*args, &block)
      Dor::Config.configure *args, &block
    end

    # Load an object and inspect its identityMetadata to figure out what class
    # to adapt it to.
    # @param [String] pid The object's PID
    # @return [Object] the ActiveFedora-modeled object
    def find(pid, _opts = {})
      Dor::Abstract.find pid, cast: true
    end

    def logger
      require 'logger'
      @logger ||= if defined?(::Rails) && ::Rails.respond_to?(:logger)
                    Rails.logger
                  else
                    Logger.new($stdout)
                  end
    end
  end

  require 'dor/version'
  require 'dor/static_config'
  require 'dor/config'
  require 'dor/exceptions'

  # patches, utilities and helpers
  require 'dor/utils/ng_tidy'
  require 'dor/utils/solr_doc_helper'
  require 'dor/utils/predicate_patch'
  require 'dor/utils/pid_utils'

  require 'dor/datastreams/datastream_spec_solrizer'

  # datastreams
  autoload_under 'datastreams' do
    autoload :AdministrativeMetadataDS
    autoload :ContentMetadataDS
    autoload :DefaultObjectRightsDS
    autoload :DescMetadataDS
    autoload :EmbargoMetadataDS
    autoload :EventsDS
    autoload :GeoMetadataDS
    autoload :IdentityMetadataDS
    autoload :ProvenanceMetadataDS
    autoload :RightsMetadataDS
    autoload :RoleMetadataDS
    autoload :TechnicalMetadataDS
    autoload :VersionMetadataDS
  end

  # DOR Concerns
  autoload_under 'models/concerns' do
    autoload :Embargoable
  end

  eager_autoload do
    # ActiveFedora Classes
    autoload_under 'models' do
      autoload :Abstract
      autoload :AdminPolicyObject
      autoload :Agreement
      autoload :Collection
      autoload :Etd
      autoload :Item
      autoload :Part
      autoload :Set
    end
  end

  # Services
  autoload_under 'services' do
    autoload :CollectionService
    autoload :CreativeCommonsLicenseService
    autoload :EmbargoService
    autoload :Ontology
    autoload :OpenDataLicenseService
    autoload :SearchService
    autoload :SuriService
  end

  eager_load!

  require 'dor/utils/hydrus_shims'
end
