# frozen_string_literal: true

module Dor
  module Governable
    extend ActiveSupport::Concern

    included do
      belongs_to :admin_policy_object, property: :is_governed_by, class_name: 'Dor::AdminPolicyObject'
      has_and_belongs_to_many :collections, property: :is_member_of_collection, class_name: 'Dor::Collection'
      has_and_belongs_to_many :sets, property: :is_member_of, class_name: 'Dor::Collection'
    end

    def initiate_apo_workflow(name)
      CreateWorkflowService.create_workflow(self, name: name, create_ds: !new_record?)
    end
    deprecation_deprecate initiate_apo_workflow: 'Use Dor::Services::Client.object(object_identifier).workflow.create(wf_name:) instead'

    def reset_to_apo_default
      rightsMetadata.content = admin_policy_object.rightsMetadata.ng_xml
    end

    def set_read_rights(rights)
      rightsMetadata.set_read_rights(rights)
      unshelve_and_unpublish if rights == 'dark'
    end

    def unshelve_and_unpublish
      if respond_to? :contentMetadata
        content_ds = datastreams['contentMetadata']
        unless content_ds.nil?
          content_ds.ng_xml.xpath('/contentMetadata/resource//file').each_with_index do |file_node, index|
            content_ds.ng_xml_will_change! if index == 0
            file_node['publish'] = 'no'
            file_node['shelve'] = 'no'
          end
        end
      end
    end

    def add_collection(collection_or_druid)
      collection =
        case collection_or_druid
        when String
          Dor::Collection.find(collection_or_druid)
        when Dor::Collection
          collection_or_druid
        end
      collections << collection
      sets << collection
    end

    def remove_collection(collection_or_druid)
      collection =
        case collection_or_druid
        when String
          Dor::Collection.find(collection_or_druid)
        when Dor::Collection
          collection_or_druid
        end

      collections.delete(collection)
      sets.delete(collection)
    end

    # set the rights metadata datastream to the content of the APO's default object rights
    def reapplyAdminPolicyObjectDefaults
      rightsMetadata.content = admin_policy_object.datastreams['defaultObjectRights'].content
    end

    def rights
      return nil unless respond_to? :rightsMetadata
      return nil if rightsMetadata.nil?

      xml = rightsMetadata.ng_xml
      return nil if xml.search('//rightsMetadata').length != 1 # ORLY?

      if xml.search('//rightsMetadata/access[@type=\'read\']/machine/group').length == 1
        'Stanford'
      elsif xml.search('//rightsMetadata/access[@type=\'read\']/machine/world').length == 1
        'World'
      elsif xml.search('//rightsMetadata/access[@type=\'discover\']/machine/none').length == 1
        'Dark'
      else
        'None'
      end
    end

    delegate :can_manage_item?, :can_manage_desc_metadata?, :can_manage_system_metadata?,
             :can_manage_content?, :can_manage_rights?, :can_manage_embargo?,
             :can_view_content?, :can_view_metadata?, to: Dor::Ability

    deprecation_deprecate can_manage_item?: 'Use Dor::Ability.can_manage_item? instead'
    deprecation_deprecate can_manage_desc_metadata?: 'Use Dor::Ability.can_manage_desc_metadata? instead'
    deprecation_deprecate can_manage_system_metadata?: 'Use Dor::Ability.can_manage_system_metadata? instead'
    deprecation_deprecate can_manage_content?: 'Use Dor::Ability.can_manage_content? instead'
    deprecation_deprecate can_manage_rights?: 'Use Dor::Ability.can_manage_rights? instead'
    deprecation_deprecate can_manage_embargo?: 'Use Dor::Ability.can_manage_embargo? instead'
    deprecation_deprecate can_view_content?: 'Use Dor::Ability.can_view_content? instead'
    deprecation_deprecate can_view_metadata?: 'Use Dor::Ability.can_view_metadata? instead'
  end
end
