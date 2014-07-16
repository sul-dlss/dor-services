module Dor

  # Rename the druid trees  at the end of the accessionWF in order to be cleaned/deleted later.
  class ResetWorkspaceService

    def self.reset_workspace_druid_tree(druid, version, workspace_root)
      
      druid_tree_path = DruidTools::Druid.new(druid, workspace_root).pathname.to_s
      
      raise "The archived directory #{druid_tree_path}_v#{version} already existed." if  File.exists?("#{druid_tree_path}_v#{version}") 
      
      if File.exists?(druid_tree_path) 
        FileUtils.mv(druid_tree_path, "#{druid_tree_path}_v#{version}")
      end #Else is a truncated tree where we shouldn't do anything

    end

    def self.reset_export_bag(druid, version, export_root)
      
      id = druid.split(':').last
      bag_dir = File.join(export_root, id)

      raise "The archived bag #{bag_dir}_v#{version} already existed." if  File.exists?("#{bag_dir}_v#{version}") 
      
      if File.exists?(bag_dir) 
        FileUtils.mv(bag_dir, "#{bag_dir}_v#{version}")
      end 
      
      if File.exists?("#{bag_dir}.tar") 
        FileUtils.mv("#{bag_dir}.tar", "#{bag_dir}_v#{version}.tar")
      end 
    end
        
  end
end