module Dor
  class Set < Dor::Abstract
    include Publishable

    has_many :members, :property => :is_member_of_collection, :class_name => 'ActiveFedora::Base'
    has_object_type 'set'
  end
end
