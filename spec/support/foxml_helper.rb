# frozen_string_literal: true

def item_from_foxml(foxml, item_class = Dor::Abstract)
  foxml = Nokogiri::XML(foxml) unless foxml.is_a?(Nokogiri::XML::Node)
  xml_streams = foxml.xpath('//foxml:datastream')
  properties = Hash[foxml.xpath('//foxml:objectProperties/foxml:property').collect do |node|
    [node['NAME'].split(/#/).last, node['VALUE']]
  end]
  result = item_class.new(pid: foxml.root['PID'])
  result.label    = properties['label']
  result.owner_id = properties['ownerId']
  xml_streams.each do |stream|
    xml_content = if stream.xpath('.//foxml:xmlContent/*').any?
                    stream.xpath('.//foxml:xmlContent/*').first
                  elsif stream.xpath('.//foxml:binaryContent').any?
                    Nokogiri::XML(Base64.decode64(stream.xpath('.//foxml:binaryContent').first.text))
                  end

    content = xml_content.to_xml
    dsid = stream['ID']
    ds = result.datastreams[dsid]
    if ds.nil?
      ds = ActiveFedora::OmDatastream.new(result, dsid)
      result.add_datastream(ds)
    end

    case ds
    when ActiveFedora::OmDatastream
      result.datastreams[dsid] = ds.class.from_xml(Nokogiri::XML(content), ds)
    when ActiveFedora::RelsExtDatastream
      result.datastreams[dsid] = ds.class.from_xml(content, ds)
    else
      result.datastreams[dsid] = ds.class.from_xml(ds, stream)
    end
  rescue StandardError
    # TODO: (?) rescue if 1 datastream failed
  end

  # stub item and datastream repo access methods
  result.datastreams.each_pair do |_dsid, ds|
    ds.instance_eval do
      def save
        true
      end
    end
  end
  result.instance_eval do
    def save
      true
    end
  end
  result
end
