# frozen_string_literal: true

require 'confstruct/configuration'
require 'rsolr'
require 'yaml'
require 'dor/certificate_authenticated_rest_resource_factory'
require 'dor/services/client'

module Dor
  class Configuration < Confstruct::Configuration
    include ActiveSupport::Callbacks
    define_callbacks :initialize
    define_callbacks :configure

    def initialize(*args)
      super *args
      run_callbacks(:initialize) {}
    end

    # Call the super method with callbacks and with $VERBOSE temporarily disabled
    def configure(*args)
      result = self
      temp_verbose = $VERBOSE
      $VERBOSE = nil
      begin
        run_callbacks :configure do
          result = super(*args)
        end
      ensure
        $VERBOSE = temp_verbose
      end
      result
    end

    def sanitize
      dup
    end

    def make_solr_connection(add_opts = {})
      opts = Dor::Config.solr.opts.merge(add_opts).merge(
        url: Dor::Config.solr.url
      )
      ::RSolr.connect(opts)
    end

    set_callback :initialize, :after do |config|
      config.deep_merge!(
        fedora: {
          client: Confstruct.deferred { |_c| CertificateAuthenticatedRestResourceFactory.create(:fedora) },
          safeurl: Confstruct.deferred do |_c|
            begin
              fedora_uri = URI.parse(config.fedora.url)
              fedora_uri.user = fedora_uri.password = nil
              fedora_uri.to_s
            rescue URI::InvalidURIError
              nil
            end
          end
        },
        dor_services: {
          rest_client: Confstruct.deferred { |_c| RestResourceFactory.create(:dor_services) }
        },
        purl_services: {
          rest_client: Confstruct.deferred { |_c| RestResourceFactory.create(:purl_services) }
        },
        sdr: {
          rest_client: Confstruct.deferred { |_c| RestResourceFactory.create(:sdr) }
        },
        workflow: {
          client: Confstruct.deferred do |c|
            Dor::WorkflowService.configure c.url, logger: c.client_logger, timeout: c.timeout, dor_services_url: config.dor_services.url
            Dor::WorkflowService
          end,
          client_logger: Confstruct.deferred do |c|
                           if c.logfile && c.shift_age
                             Logger.new(c.logfile, c.shift_age)
                           elsif c.logfile
                             Logger.new(c.logfile)
                           end
                         end
        }
      )
      true
    end

    set_callback :configure, :after do |config|
      configure_client!(config)

      if config.solr.url.present?
        ActiveFedora::SolrService.register
        ActiveFedora::SolrService.instance.instance_variable_set :@conn, make_solr_connection
      end
    end

    def configure_client!(config)
      # Do not configure client if URL not specified
      return if config.dor_services&.url.blank?

      params = {
        url: config.dor_services.url
      }
      params[:username] = config.dor_services.user if config.dor_services&.user.present?
      params[:password] = config.dor_services.pass if config.dor_services&.pass.present?

      Dor::Services::Client.configure(params)
    end

    # Act like an ActiveFedora.configurator
    def init(*args); end

    def fedora_config
      fedora_uri = URI.parse(fedora.url)
      connection_opts = { url: fedora.safeurl, user: fedora_uri.user, password: fedora_uri.password }
      connection_opts[:ssl_client_cert] = OpenSSL::X509::Certificate.new(File.read(ssl.cert_file)) if ssl.cert_file.present?
      connection_opts[:ssl_client_key] = OpenSSL::PKey::RSA.new(File.read(ssl.key_file), ssl.key_pass) if ssl.key_file.present?
      connection_opts[:ssl_cert_store] = default_ssl_cert_store
      connection_opts
    end

    def solr_config
      { url: solr.url }
    end

    def predicate_config
      YAML.load(File.read(File.expand_path('../../config/predicate_mappings.yml', __dir__)))
    end

    def default_ssl_cert_store
      @default_ssl_cert_store ||= RestClient::Request.default_ssl_cert_store
    end
  end

  Config = Configuration.new(YAML.load(File.read(File.expand_path('../../config/config_defaults.yml', __dir__))))
  ActiveFedora.configurator = Config
end
