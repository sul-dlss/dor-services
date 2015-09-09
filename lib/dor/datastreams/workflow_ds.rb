module Dor
  # TODO: class docs
  class WorkflowDs < ActiveFedora::OmDatastream
    include SolrDocHelper

    set_terminology do |t|
      t.root(:path => 'workflows')
      t.workflow {
        t.workflowId( :path => {:attribute => 'id'} )
        t.process {
          t.name_(    :path => {:attribute => 'name'     }, :index_as => [:displayable, :not_searchable] )
          t.status(   :path => {:attribute => 'status'   }, :index_as => [:displayable, :not_searchable] )
          t.timestamp(:path => {:attribute => 'datetime' }, :index_as => [:displayable, :not_searchable] )#, :data_type => :date)
          t.elapsed(  :path => {:attribute => 'elapsed'  }, :index_as => [:displayable, :not_searchable] )
          t.lifecycle(:path => {:attribute => 'lifecycle'}, :index_as => [:displayable, :not_searchable] )
          t.attempts( :path => {:attribute => 'attempts' }, :index_as => [:displayable, :not_searchable] )
        }
      }
    end

    def initialize(*args)
      self.field_mapper = UtcDateFieldMapper.new
      super
    end

    def get_workflow(wf, repo = 'dor')
      xml = Dor::WorkflowService.get_workflow_xml(repo, pid, wf)
      xml = Nokogiri::XML(xml)
      return nil if xml.xpath('workflow').length == 0
      Workflow::Document.new(xml.to_s)
    end

    def [](wf)
      xml = Dor::WorkflowService.get_workflow_xml('dor', pid, wf)
      xml = Nokogiri::XML(xml)
      return nil if xml.xpath('workflow').length == 0
      Workflow::Document.new(xml.to_s)
    end

    def ensure_xml_loaded
      ng_xml
      self.xml_loaded = true
    end

    def ng_xml
      @ng_xml ||= Nokogiri::XML::Document.parse(content)
    end

    def content
      @content ||= Dor::WorkflowService.get_workflow_xml 'dor', pid, nil
    rescue RestClient::ResourceNotFound
      xml = Nokogiri::XML(%(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workflows objectId="#{pid}"/>))
      digital_object.datastreams.keys.each do |dsid|
        next unless dsid =~ /WF$/
        ds_content = Nokogiri::XML(Dor::WorkflowService.get_workflow_xml 'dor', pid, dsid)
        xml.root.add_child(ds_content.root)
      end
      @content ||= xml.to_xml
    end

    def workflows
      @workflows ||= workflow.nodeset.collect { |wf_node| Workflow::Document.new wf_node.to_xml }
    end

    def graph(dir = nil)
      result = GraphViz.digraph(pid)
      sg = result.add_graph('rank') { |g| g[:rank => 'same'] }
      workflows.each do |wf|
        unless wf.nil?
          g = wf.graph(result)
          sg.add_node(g.root.id) unless g.nil?
        end
      end
      result['rankdir'] = dir || 'TB'
      result
    end

    # Finds the first workflow that is expedited, then returns the value of its priority
    #
    # @return [Integer] value of the priority.  Defaults to 0 if none of the workflows are expedited
    def current_priority
      cp = workflows.detect &:expedited?
      return 0 if cp.nil?
      cp.priority.to_i
    end

    def to_solr(solr_doc = {}, *args)
      # super solr_doc, *args
      workflows.each { |wf| wf.to_solr(solr_doc, *args) }
      solr_doc
    end
  end
end
