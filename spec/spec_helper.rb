require 'simplecov'
SimpleCov.start
$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'bundler/setup'
require 'rspec'
require 'awesome_print'
#require 'rspec/autorun'
#require 'rspec/mocks'

require 'solrizer'
require 'om'

require 'dor-services'
#require 'ruby-debug'
require 'foxml_helper'
require 'equivalent-xml/rspec_matchers'
require 'fakeweb'
require 'pry'
require 'tmpdir'
require 'nokogiri'

require 'dor_config'
require 'vcr'

# ::ENABLE_SOLR_UPDATES = true

module Dor::SpecHelpers

  def stub_config
    @fixture_dir = fixture_dir = File.join(File.dirname(__FILE__), 'fixtures')
    Dor::Config.push! do
      suri.mint_ids false
      gsearch do
        url      'http://solr.edu/gsearch'
        rest_url 'http://fedora.edu/gsearch/rest'
      end
      solrizer.url 'http://solr.edu/solrizer'
      fedora.url   'http://fedora.edu/fedora'
      stacks.document_cache_host       'purl-test.stanford.edu'
      stacks.local_workspace_root      File.join(fixture_dir, 'workspace')
      stacks.local_stacks_root         File.join(fixture_dir, 'stacks')
      stacks.local_document_cache_root File.join(fixture_dir, 'purl')
      sdr.local_workspace_root         File.join(fixture_dir, 'workspace')
      sdr.local_export_home            File.join(fixture_dir, 'export')
    end
    allow(ActiveFedora).to receive(:fedora).and_return(double('frepo').as_null_object)  # must be used in per-request context: :each not :all
  end

  def unstub_config
    Dor::Config.pop!
  end

  def instantiate_fixture(druid, klass = ActiveFedora::Base)
    mask = File.join(@fixture_dir, "*_#{druid.sub(/:/, '_')}.xml")
    fname = Dir[mask].first
    return nil if fname.nil?
    item_from_foxml(File.read(fname), klass)
  end

  def read_fixture(fname)
    File.read(File.join(@fixture_dir, fname))
  end

end

RSpec.configure do |config|
  config.include Dor::SpecHelpers
  config.logger.level = Logger::WARN  # if you want INFO and lesser messages, tweak here
end

VCR.configure do |c|
  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  c.hook_into :webmock
  c.allow_http_connections_when_no_cassette = true
  c.default_cassette_options = { :record => :new_episodes }
  c.configure_rspec_metadata!
end

Retries.sleep_enabled = false  # fail fast in tests

def catch_stdio
  old_handles = [$stdout.dup, $stderr.dup]
  begin
    $stdout.reopen(File.new('/dev/null', 'w'))
    $stderr.reopen(File.new('/dev/null', 'w'))
    yield
  ensure
    $stdout.reopen(IO.new(old_handles[0].fileno, 'w'))
    $stderr.reopen(IO.new(old_handles[1].fileno, 'w'))
  end
end

module Kernel
  # Suppresses warnings within a given block.
  def with_warnings_suppressed
    saved_verbosity = $-v
    $-v = nil
    yield
  ensure
    $-v = saved_verbosity
  end
end
