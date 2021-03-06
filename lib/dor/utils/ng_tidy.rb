# frozen_string_literal: true

class Nokogiri::XML::Text
  def normalize
    content =~ /\S/ ? content.gsub(/\s+/, ' ').strip : content
  end

  def normalize!
    self.content = normalize
  end
end

class Nokogiri::XML::Node
  def normalize_text!
    xpath('//text()').each(&:normalize!)
  end
end

class Nokogiri::XML::Document
  PRETTIFY_XSLT = Nokogiri::XSLT <<-EOC
    <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
      <xsl:output omit-xml-declaration="yes" indent="yes"/>
      <xsl:template match="node()|@*">
        <xsl:copy>
          <xsl:apply-templates select="node()|@*"/>
        </xsl:copy>
      </xsl:template>
    </xsl:stylesheet>
  EOC

  def prettify
    PRETTIFY_XSLT.transform(self).to_xml
  end
end
