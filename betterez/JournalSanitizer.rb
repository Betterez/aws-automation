# frozen_string_literal: true

class JournalSanitizer
  REDACTED = '[REDACTED]'

  SECRET_KEY = '(?:password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|' \
               'credentials?|connection[_-]?string|database[_-]?url|' \
               'mongo(?:db)?[_-]?(?:uri|url)|redis[_-]?url)'

  URI_USERINFO = %r{
    (mongodb(?:\+srv)?|postgres(?:ql)?|mysql|redis|rediss|amqp|amqps|https?)://
    [^/\s:@]*:[^@\s/]+@
  }ix

  QUERY_SECRET = /([?&])(password|pwd|token|secret|access_key)=[^&\s]*/i

  QUOTED_ASSIGNMENT = /
    (["'])([A-Za-z0-9_.-]*#{SECRET_KEY}[A-Za-z0-9_.-]*)\1
    (\s*[=:]\s*)
    (["']).*?\4
  /ix

  QUOTED_VALUE_ASSIGNMENT = /
    \b([A-Za-z0-9_.-]*#{SECRET_KEY}[A-Za-z0-9_.-]*)
    (\s*[=:]\s*)
    (["']).*?\3
  /ix

  PLAIN_ASSIGNMENT = /
    \b([A-Za-z0-9_.-]*#{SECRET_KEY}[A-Za-z0-9_.-]*)
    (\s*[=:]\s*)
    [^&\s"']+
  /ix

  AWS_ACCESS_KEY_ID = /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/

  BEARER = /(Authorization:\s*Bearer\s+)\S+/i

  PRIVATE_KEY = /-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/m

  def self.sanitize(text)
    return '' if text.nil?

    sanitized = text.dup
    sanitized.gsub!(PRIVATE_KEY, REDACTED)
    sanitized.gsub!(BEARER, "\\1#{REDACTED}")
    sanitized.gsub!(QUERY_SECRET, "\\1\\2=#{REDACTED}")
    sanitized.gsub!(QUOTED_ASSIGNMENT, "\\1\\2\\1\\3\\4#{REDACTED}\\4")
    sanitized.gsub!(QUOTED_VALUE_ASSIGNMENT, "\\1\\2\\3#{REDACTED}\\3")
    sanitized.gsub!(PLAIN_ASSIGNMENT, "\\1\\2#{REDACTED}")
    sanitized.gsub!(URI_USERINFO, "\\1://#{REDACTED}@")
    sanitized.gsub!(AWS_ACCESS_KEY_ID, REDACTED)
    sanitized
  end
end
