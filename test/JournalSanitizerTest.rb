# frozen_string_literal: true

require 'test/unit'
require_relative '../betterez/JournalSanitizer'

class JournalSanitizerTest < Test::Unit::TestCase
  def test_redacts_userinfo_in_connection_uris
    text = <<~LOG
      mongodb://appuser:s3cret@mongo.internal:27017/gps
      mongodb+srv://appuser:s3cret@cluster.mongodb.net/gps
      postgres://appuser:s3cret@db.internal/gps
      postgresql://appuser:s3cret@db.internal/gps
      mysql://appuser:s3cret@db.internal/gps
      redis://:s3cret@cache.internal:6379/0
      rediss://appuser:s3cret@cache.internal:6379/0
      amqp://appuser:s3cret@mq.internal:5672
      amqps://appuser:s3cret@mq.internal:5671
      https://appuser:s3cret@hooks.internal/callback
      http://appuser:s3cret@hooks.internal/callback
    LOG

    sanitized = JournalSanitizer.sanitize(text)

    assert_no_match(/s3cret/, sanitized)
    assert_no_match(/appuser/, sanitized)
    assert_match(%r{mongodb://\[REDACTED\]@mongo\.internal:27017/gps}, sanitized)
    assert_match(%r{mongodb\+srv://\[REDACTED\]@cluster\.mongodb\.net/gps}, sanitized)
    assert_match(%r{postgres://\[REDACTED\]@db\.internal/gps}, sanitized)
    assert_match(%r{postgresql://\[REDACTED\]@db\.internal/gps}, sanitized)
    assert_match(%r{mysql://\[REDACTED\]@db\.internal/gps}, sanitized)
    assert_match(%r{redis://\[REDACTED\]@cache\.internal:6379/0}, sanitized)
    assert_match(%r{rediss://\[REDACTED\]@cache\.internal:6379/0}, sanitized)
    assert_match(%r{amqp://\[REDACTED\]@mq\.internal:5672}, sanitized)
    assert_match(%r{amqps://\[REDACTED\]@mq\.internal:5671}, sanitized)
    assert_match(%r{https://\[REDACTED\]@hooks\.internal/callback}, sanitized)
    assert_match(%r{http://\[REDACTED\]@hooks\.internal/callback}, sanitized)
  end

  def test_redacts_secret_query_params
    text = 'GET https://api.internal/path?password=s3cret&pwd=s3cret&token=s3cret&secret=s3cret&access_key=s3cret&ok=1'

    sanitized = JournalSanitizer.sanitize(text)

    assert_no_match(/s3cret/, sanitized)
    assert_match(/password=\[REDACTED\]/, sanitized)
    assert_match(/pwd=\[REDACTED\]/, sanitized)
    assert_match(/token=\[REDACTED\]/, sanitized)
    assert_match(/secret=\[REDACTED\]/, sanitized)
    assert_match(/access_key=\[REDACTED\]/, sanitized)
    assert_match(/ok=1/, sanitized)
  end

  def test_redacts_secret_assignments
    text = <<~LOG
      MONGO_PASSWORD=s3cret
      export DATABASE_URL=mongodb://appuser:s3cret@mongo.internal/gps
      api_key: s3cret
      "access_key": "s3cret"
      'private_key'='s3cret'
      connection_string: "user:s3cret@host"
      redis_url=redis://:s3cret@cache:6379
      mongodb_uri=mongodb://appuser:s3cret@host/db
      credential=s3cret
    LOG

    sanitized = JournalSanitizer.sanitize(text)

    assert_no_match(/s3cret/, sanitized)
    assert_no_match(/appuser/, sanitized)
    assert_match(/MONGO_PASSWORD=\[REDACTED\]/, sanitized)
    assert_match(/DATABASE_URL=\[REDACTED\]/, sanitized)
    assert_match(/api_key: \[REDACTED\]/, sanitized)
    assert_match(/"access_key": "\[REDACTED\]"/, sanitized)
    assert_match(/'private_key'='\[REDACTED\]'/, sanitized)
    assert_match(/connection_string: "\[REDACTED\]"/, sanitized)
    assert_match(/redis_url=\[REDACTED\]/, sanitized)
    assert_match(/mongodb_uri=\[REDACTED\]/, sanitized)
    assert_match(/credential=\[REDACTED\]/, sanitized)
  end

  def test_redacts_aws_access_key_ids_bearer_tokens_and_private_keys
    text = <<~LOG
      using AKIAIOSFODNN7EXAMPLE and ASIAIOSFODNN7EXAMPLE
      Authorization: Bearer s3cret-token
      -----BEGIN RSA PRIVATE KEY-----
      MIIEowIBAAKCAQEA7s3cret
      -----END RSA PRIVATE KEY-----
    LOG

    sanitized = JournalSanitizer.sanitize(text)

    assert_no_match(/AKIAIOSFODNN7EXAMPLE/, sanitized)
    assert_no_match(/ASIAIOSFODNN7EXAMPLE/, sanitized)
    assert_no_match(/s3cret-token/, sanitized)
    assert_no_match(/MIIEowIBAAKCAQEA7s3cret/, sanitized)
    assert_match(/\[REDACTED\]/, sanitized)
    assert_match(/Authorization: Bearer \[REDACTED\]/, sanitized)
  end

  def test_leaves_ordinary_log_lines_unchanged
    text = <<~LOG
      service started
      HTTP/1.1 200 OK
      checking service health, 1 of 90
      connected to server 10.1.6.240
    LOG

    assert_equal(text, JournalSanitizer.sanitize(text))
  end

  def test_sanitize_nil_returns_empty_string
    assert_equal('', JournalSanitizer.sanitize(nil))
  end
end
