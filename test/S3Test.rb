require 'nokogiri'
require_relative "../betterez/Helpers"


Helpers.log 'testing s3'
client=Helpers.create_aws_S3_client
resp=client.get_object({
  bucket: "btrz-aws-automation",
  key: "ossec/agent/ossec.conf"
  })
xml_content=resp.body.read
noko_xml=Nokogiri::XML(xml_content)
#puts  noko_xml.css("ossec_config client server-ip").first.content
noko_xml.css("ossec_config client server-ip").first.content="ossec-manager.staging.btrz"
puts noko_xml.to_s

Helpers.log "done"
