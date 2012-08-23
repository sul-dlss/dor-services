module Dor
  class AdminPolicyObject < ::ActiveFedora::Base
    include Identifiable
    include Governable
    
    has_relationship 'thing', :property => :is_governed_by, :inbound => :true
    has_object_type 'adminPolicy'
    has_metadata :name => "administrativeMetadata", :type => Dor::AdministrativeMetadataDS, :label => 'Administrative Metadata'
    has_metadata :name => "roleMetadata", :type => Dor::RoleMetadataDS, :label => 'Role Metadata'
    has_metadata :name => "defaultObjectRights", :type => ActiveFedora::NokogiriDatastream, :label => 'Default Object Rights'
  end
end