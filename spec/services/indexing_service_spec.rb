# frozen_string_literal: true

require 'spec_helper'

describe Dor::IndexingService do
  before { stub_config }

  after  { unstub_config }

  describe '#generate_index_logger' do
    before do
      allow(Deprecation).to receive(:warn)
      @mock_log_msg = 'something noteworthy'
    end

    after do
      File.delete Dor::Config.indexing_svc.log if File.exist? Dor::Config.indexing_svc.log
    end

    it 'calls entry_id_block for each logging event, and include the result in the logging statement' do
      mock_req_id_ctr = 0
      test_index_logger = described_class.generate_index_logger do
        # this entry_id_block returns next value from a counter each time its called
        mock_req_id_ctr += 1 # ruby has no [post-]increment operator
      end

      expect(Deprecation).to have_received(:warn)

      # log some test messages
      mock_log_messages = ['msg 1', 'msg 2', 'msg 3']
      mock_log_messages.each do |msg|
        test_index_logger.info msg
      end

      # parse the log and make sure the log lines match the expected format,
      # with the expected messages, and the extra identifier (the counter
      # values).
      # the first log line is just a statement about when it was created, e.g.
      # "# Logfile created on ...".  we just care about the subsequent lines.
      log_lines = open(Dor::Config.indexing_svc.log).read.split("\n")[1..-1]
      log_lines.each_with_index do |log_line, idx|
        entry_id = idx + 1 # first entry_id is 1 since increment happened before return in entry_id_block
        expect(log_line).to match(/\[#{entry_id}\] \[.*\] #{mock_log_messages[idx]}$/)
      end
      expect(mock_req_id_ctr).to eq(mock_log_messages.length)
    end

    it 'logs the default entry_id if entry_id_block is nil' do
      test_index_logger = described_class.generate_index_logger

      expect(Deprecation).to have_received(:warn)

      test_index_logger.info @mock_log_msg
      last_log_line = open(Dor::Config.indexing_svc.log).read.split("\n")[-1]
      expect(last_log_line).to match(/\[---\] \[.*\] #{@mock_log_msg}$/)
    end

    it 'logs the default entry_id if entry_id_block throws a StandardError' do
      test_index_logger = described_class.generate_index_logger do
        raise ZeroDivisionError, 'whoops'
      end

      expect(Deprecation).to have_received(:warn)

      test_index_logger.info @mock_log_msg

      last_log_line = open(Dor::Config.indexing_svc.log).read.split("\n")[-1]
      expect(last_log_line).to match(/\[---\] \[.*\] #{@mock_log_msg}$/)
    end

    it "does not trap the exception if it's not StandardError" do
      stack_overflow_ex = SystemStackError.new 'really? here?'
      test_index_logger = described_class.generate_index_logger { raise stack_overflow_ex }

      expect(Deprecation).to have_received(:warn)

      expect { test_index_logger.info @mock_log_msg }.to raise_error(stack_overflow_ex)
    end
  end

  describe '#default_index_logger' do
    before do
      allow(Deprecation).to receive(:warn)
    end

    it 'calls generate_index_logger, and memoize the result' do
      mock_default_logger = double(Logger)
      expect(described_class).to receive(:generate_index_logger).once.and_return(mock_default_logger)
      expect(described_class.default_index_logger).to eq(mock_default_logger)
      expect(described_class.default_index_logger).to eq(mock_default_logger)
      expect(Deprecation).to have_received(:warn).twice
    end
  end

  describe '#reindex_pid_list' do
    before do
      expect(Deprecation).to receive(:warn)
      @mock_solr_conn = double(ActiveFedora.solr.conn)
    end

    it 'reindexes the pids and not commit by default' do
      pids = [1..10].map(&:to_s)
      pids.each { |pid| expect(described_class).to receive(:reindex_pid).with(pid, raise_errors: false) }
      expect(@mock_solr_conn).not_to receive(:commit)
      described_class.reindex_pid_list pids
    end

    it 'reindexes the pids and commit if should_commit is true' do
      pids = [1..10].map(&:to_s)
      pids.each { |pid| expect(described_class).to receive(:reindex_pid).with(pid, raise_errors: false) }
      expect(ActiveFedora.solr).to receive(:conn).and_return(@mock_solr_conn)
      expect(@mock_solr_conn).to receive(:commit)
      described_class.reindex_pid_list pids, true
    end

    it 'proceeds despite individual indexing failures' do
      pids = (1..10).map(&:to_s)
      pids.each { |pid| expect(described_class).to receive(:reindex_pid).with(pid, raise_errors: false) }
      expect(ActiveFedora.solr).to receive(:conn).and_return(@mock_solr_conn)
      expect(@mock_solr_conn).to receive(:commit)
      described_class.reindex_pid_list pids, true
    end
  end

  describe '#reindex_object' do
    before do
      expect(Deprecation).to receive(:warn)
      @mock_pid = 'unique_id'
      @mock_obj = double(Dor::Item)
      @mock_solr_doc = { id: @mock_pid, text_field_tesim: 'a field to be searched' }
    end

    it 'reindexes the object via Dor::SearchService' do
      expect(@mock_obj).to receive(:to_solr).and_return(@mock_solr_doc)
      expect(Dor::SearchService.solr).to receive(:add).with(hash_including(id: @mock_pid), {})
      ret_val = described_class.reindex_object @mock_obj
      expect(ret_val).to eq(@mock_solr_doc)
    end

    it 'passes add_attributes options to solr' do
      expect(@mock_obj).to receive(:to_solr).and_return(@mock_solr_doc)
      expect(Dor::SearchService.solr).to receive(:add).with(hash_including(id: @mock_pid), add_attributes: { commitWithin: 10 })
      ret_val = described_class.reindex_object @mock_obj, add_attributes: { commitWithin: 10 }
      expect(ret_val).to eq(@mock_solr_doc)
    end
  end

  describe '#reindex_pid' do
    before do
      expect(Deprecation).to receive(:warn)
      @mock_pid = 'unique_id'
      @mock_default_logger = double(Logger)
      @mock_obj = double(Dor::Item)
      @mock_solr_doc = { id: @mock_pid, text_field_tesim: 'a field to be searched' }
      expect(described_class).to receive(:default_index_logger).at_least(:once).and_return(@mock_default_logger)
    end

    it 'handles old, primitive arguments' do
      expect(Dor).to receive(:find).with(@mock_pid).and_raise(ActiveFedora::ObjectNotFoundError)
      expect(@mock_default_logger).to receive(:warn).with("failed to update index for #{@mock_pid}, object not found in Fedora")
      expect(described_class).to receive(:warn)
      expect { described_class.reindex_pid(@mock_pid, nil, false) }.not_to raise_error
    end

    it 'reindexes the object via Dor::IndexingService.reindex_pid and log success' do
      expect(Dor).to receive(:find).with(@mock_pid).and_return(@mock_obj)
      expect(described_class).to receive(:reindex_object).with(@mock_obj, {}).and_return(@mock_solr_doc)
      expect(@mock_default_logger).to receive(:info).with(/successfully updated index for #{@mock_pid}.*metrics.*find.*to_solr/)
      ret_val = described_class.reindex_pid @mock_pid
      expect(ret_val).to eq(@mock_solr_doc)
    end

    it 'logs the right thing if an object is not found, then re-raise the exception by default' do
      expect(Dor).to receive(:find).with(@mock_pid).and_raise(ActiveFedora::ObjectNotFoundError)
      expect(@mock_default_logger).to receive(:warn).with("failed to update index for #{@mock_pid}, object not found in Fedora")
      expect { described_class.reindex_pid(@mock_pid) }.to raise_error(ActiveFedora::ObjectNotFoundError)
    end

    it 'logs the right thing if an object is not found, but swallow the exception when should_raise_errors is false' do
      expect(Dor).to receive(:find).with(@mock_pid).and_raise(ActiveFedora::ObjectNotFoundError)
      expect(@mock_default_logger).to receive(:warn).with("failed to update index for #{@mock_pid}, object not found in Fedora")
      expect { described_class.reindex_pid(@mock_pid, raise_errors: false) }.not_to raise_error
    end

    it "logs the right thing if there's an unexpected error, then re-raise the exception by default" do
      unexpected_err = ZeroDivisionError.new "how'd that happen?"
      expect(Dor).to receive(:find).with(@mock_pid).and_raise(unexpected_err)
      expect(@mock_default_logger).to receive(:warn).with(start_with("failed to update index for #{@mock_pid}, unexpected StandardError, see main app log: ["))
      expect { described_class.reindex_pid(@mock_pid) }.to raise_error(unexpected_err)
    end

    it "logs the right thing if there's an unexpected Exception that's not StandardError, then re-raise the exception, even when should_raise_errors is false" do
      stack_overflow_ex = SystemStackError.new "didn't see that one coming... maybe you shouldn't have self-referential collections?"
      expect(Dor).to receive(:find).with(@mock_pid).and_raise(stack_overflow_ex)
      # TODO: fix this expectation and the code it's testing, as per https://github.com/sul-dlss/dor-services/issues/156
      # expect(@mock_default_logger).to receive(:error).with(start_with("failed to update index for #{@mock_pid}, unexpected Exception, see main app log: ["))
      expect { described_class.reindex_pid(@mock_pid, raise_errors: false) }.to raise_error(stack_overflow_ex)
    end
  end

  describe '#reindex_pid_remotely' do
    before do
      @mock_pid = 'druid:aa111bb2222'
      @mock_default_logger = double(Logger)
      expect(described_class).to receive(:default_index_logger).at_least(:once).and_return(@mock_default_logger)
      expect(Deprecation).to receive(:warn)
    end

    it 'calls a remote service to reindex' do
      expect(RestClient).to receive(:post).and_return(double)
      expect(@mock_default_logger).to receive(:info).with(/successfully updated index for druid:/)
      described_class.reindex_pid_remotely(@mock_pid)
    end

    it 'calls a remote service to reindex even without a druid: prefix' do
      expect(RestClient).to receive(:post).and_return(double)
      expect(@mock_default_logger).to receive(:info).with(/successfully updated index for druid:/)
      described_class.reindex_pid_remotely('aa111bb2222')
    end

    it 'raises a ReindexRemotelyError exception in cases of predictable failures' do
      expect(RestClient).to receive(:post).exactly(3).and_raise(RestClient::Exception.new(double))
      expect(@mock_default_logger).to receive(:error).with(/failed to reindex/)
      expect { described_class.reindex_pid_remotely(@mock_pid) }.to raise_error(Dor::IndexingService::ReindexError)
    end

    it 'raises a ReindexRemotelyError exception in cases of remote host is down' do
      expect(RestClient).to receive(:post).exactly(3).and_raise(Errno::ECONNREFUSED)
      expect(@mock_default_logger).to receive(:error).with(/failed to reindex/)
      expect { described_class.reindex_pid_remotely(@mock_pid) }.to raise_error(Dor::IndexingService::ReindexError)
    end

    it 'raises other exceptions in cases of unpredictable failures' do
      expect(RestClient).to receive(:post).and_raise(RuntimeError.new)
      expect(@mock_default_logger).to receive(:error).with(/failed to reindex/)
      expect { described_class.reindex_pid_remotely(@mock_pid) }.to raise_error(RuntimeError)
    end
  end
end
