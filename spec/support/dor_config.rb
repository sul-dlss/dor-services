# frozen_string_literal: true

cert_dir = File.join(File.dirname(__FILE__), '..', 'certs')

Dor.configure do
  ssl do
    cert_file File.join(cert_dir, 'spec.crt')
    key_file File.join(cert_dir, 'spec.key')
    key_pass 'thisisatleast4bytes'
  end

  fedora.url 'http://fedoraAdmin:fedoraAdmin@localhost:8983/fedora'

  suri do
    mint_ids true
    id_namespace 'druid'
    url 'http://example.edu/suri'
    user 'hydra-etd'
    pass 'lyberteam'
  end

  solr.url 'https://solr.example.edu/solr/collection1'
end
