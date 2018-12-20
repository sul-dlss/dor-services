# frozen_string_literal: true

require 'moab'
module Sdr
  class Client
    class << self
      # @param [String] druid id of the object you want the version of
      # @return [Integer] the current version from SDR
      def current_version(druid)
        xml = client["objects/#{druid}/current_version"].get

        begin
          doc = Nokogiri::XML xml
          raise if doc.root.name != 'currentVersion'

          return Integer(doc.text)
        rescue StandardError
          raise "Unable to parse XML from SDR current_version API call: #{xml}"
        end
      end

      # @param [String] dsname The identifier of the metadata datastream
      # @return [String] The datastream contents from the previous version of the digital object (fetched from SDR storage)
      def get_sdr_metadata(druid, dsname)
        client["objects/#{druid}/metadata/#{dsname}.xml"].get
      rescue RestClient::ResourceNotFound
        nil
      end

      # @param [String] druid The object identifier
      # @return [Moab::SignatureCatalog] the catalog of all files previously ingested
      def get_signature_catalog(druid)
        response = client["objects/#{druid}/manifest/signatureCatalog.xml"].get
        Moab::SignatureCatalog.parse(response)
      rescue RestClient::ResourceNotFound
        Moab::SignatureCatalog.new(digital_object_id: druid, version_id: 0)
      end

      # @return [Moab::FileInventoryDifference] the differences for the given content and subset
      def get_content_diff(druid, current_content, subset = :all, version = nil)
        raise Dor::ParameterError, "Invalid subset value: #{subset}" unless %w(all shelve preserve publish).include?(subset.to_s)

        query_string = { subset: subset.to_s }
        query_string[:version] = version.to_s unless version.nil?
        query_string = URI.encode_www_form(query_string)
        sdr_query = "objects/#{druid}/cm-inv-diff?#{query_string}"
        response = client[sdr_query].post(current_content, content_type: 'application/xml')
        Moab::FileInventoryDifference.parse(response)
      end

      def get_preserved_file_content(druid, filename, version)
        client["objects/#{druid}/content/#{URI.encode(filename)}?version=#{version}"].get
      end

      def client
        if Dor::Config.sdr.url
          # dor-services-app takes this path
          Dor::Config.sdr.rest_client
        elsif Dor::Config.dor_services.url
          # Anything that is not dor-servics-app should be through here.
          Deprecation.warn(self, 'you are using dor-services to invoke calls to dor-services-app.  Use dor-services-client instead.')
          Dor::Config.dor_services.rest_client['v1/sdr']
        else
          raise Dor::ParameterError, 'Missing Dor::Config.sdr and/or Dor::Config.dor_services configuration'
        end
      end
    end
  end
end
