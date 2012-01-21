class WorkflowDs < ActiveFedora::NokogiriDatastream 
  include SolrDocHelper
  
  set_terminology do |t|
    t.root(:path=>"workflow", :xmlns => '', :namespace_prefix => nil)
    t.workflowId(:path=>{:attribute => "id"})
    t.process(:path=>'process', :namespace_prefix => nil) {
      t._name(:path=>{:attribute=>"name"})
      t.status(:path=>{:attribute=>"status"})
      t.timestamp(:path=>{:attribute=>"datetime"}, :data_type => :date)
      t.elapsed(:path=>{:attribute=>"elapsed"})
      t.lifecycle(:path=>{:attribute=>"lifecycle"})
      t.attempts(:path=>{:attribute=>"attempts"}, :index_as => nil)
    }
  end

  def initialize(*args)
    self.field_mapper = UtcDateFieldMapper.new
    super
  end
  
  def definition
    wfo = Dor::WorkflowObject.find_by_name(self.workflowId.first)
    wfo ? wfo.definition : nil
  end
  
  def graph(parent = nil)
    wf_definition = self.definition
    wf_definition ? Workflow::Graph.from_processes(wf_definition.repository, wf_definition.name, self.processes, parent) : nil
  end
  
  def processes
    if self.definition
      self.definition.processes.collect do |process|
        node = ng_xml.at("/workflow/process[@name = '#{process.name}']")
        process.update!(node) unless node.nil?
        process
      end
    else
      []
    end
  end
    
  def to_solr(solr_doc=Hash.new, *args)
    super
    wf_name = self.workflowId.first
    add_solr_value(solr_doc, 'wf', wf_name, :string, [:facetable])
    add_solr_value(solr_doc, 'wf_wps', wf_name, :string, [:facetable])
    add_solr_value(solr_doc, 'wf_wsp', wf_name, :string, [:facetable])
    self.find_by_terms(:workflow, :process).sort { |a,b| a['datetime'] <=> b['datetime'] }.each do |process|
      add_solr_value(solr_doc, 'wf_wps', "#{wf_name}:#{process['name']}", :string, [:facetable])
      add_solr_value(solr_doc, 'wf_wps', "#{wf_name}:#{process['name']}:#{process['status']}", :string, [:facetable])
      add_solr_value(solr_doc, 'wf_wsp', "#{wf_name}:#{process['status']}", :string, [:facetable])
      add_solr_value(solr_doc, 'wf_wsp', "#{wf_name}:#{process['status']}:#{process['name']}", :string, [:facetable])
    end
    solr_doc
  end
  
end