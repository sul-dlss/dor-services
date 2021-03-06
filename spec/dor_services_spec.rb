# frozen_string_literal: true

require 'spec_helper'

describe Dor do
  describe '.registered_classes' do
    it 'registers the default models' do
      expect(described_class.registered_classes).to include \
        'adminPolicy' => Dor::AdminPolicyObject,
        'agreement' => Dor::Agreement,
        'collection' => Dor::Collection,
        'item' => Dor::Item,
        'set' => Dor::Set
    end
  end
end
