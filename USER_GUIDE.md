# MUXI Ruby SDK User Guide

## Installation

```bash
gem install muxi
```

Or add to your Gemfile:

```ruby
gem 'muxi'
```

## Quickstart

```ruby
require 'muxi'

# Server client (management, HMAC auth)
server = Muxi::ServerClient.new(
  url: 'https://server.example.com',
  key_id: '<key_id>',
  secret_key: '<secret_key>'
)
puts server.status

# Formation client (runtime, key auth)
formation = Muxi::FormationClient.new(
  server_url: 'https://server.example.com',
  formation_id: '<formation_id>',
  client_key: '<client_key>',
  admin_key: '<admin_key>'
)
puts formation.health
```

## Clients

- **ServerClient** (management, HMAC): deploy/list/update formations, server health/status, server logs.
- **FormationClient** (runtime, client/admin keys): chat/audio (streaming), agents, secrets, MCP, memory, scheduler, sessions/requests, identifiers, credentials, triggers/SOPs/audit, async/A2A/logging config, overlord/LLM settings, events/logs streaming.

## Streaming

```ruby
# Chat streaming (block)
formation.chat_stream({ message: 'Tell me a story' }, user_id: 'user-123') do |event|
  puts event['data'] if event['event'] == 'message'
end

# Chat streaming (enumerator)
formation.chat_stream({ message: 'Tell me a story' }, user_id: 'user-123').each do |event|
  puts event['data']
end

# Event streaming
formation.stream_events('user-123') do |event|
  puts event
end

# Log streaming (admin)
formation.stream_logs(level: 'info') do |log|
  puts log
end
```

## Auth & Headers

- **ServerClient**: HMAC with `key_id`/`secret_key` on `/rpc` endpoints.
- **FormationClient**: `X-MUXI-CLIENT-KEY` or `X-MUXI-ADMIN-KEY` on `/api/{formation}/v1`. Override `base_url` for direct access (e.g., `http://localhost:9012/v1`).
- **Idempotency**: `X-Muxi-Idempotency-Key` auto-generated on every request.
- **SDK headers**: `X-Muxi-SDK`, `X-Muxi-Client` set automatically.

## Timeouts & Retries

- Default timeout: 30s (no timeout for streaming).
- Retries: `max_retries` with exponential backoff on 429/5xx/connection errors; respects `Retry-After`.
- Debug logging: enabled when `debug: true` or `MUXI_DEBUG=1`.

## Error Handling

```ruby
begin
  formation.chat(message: 'hello')
rescue Muxi::AuthenticationError => e
  puts "Auth failed: #{e.message}"
rescue Muxi::RateLimitError => e
  puts "Rate limited. Retry after: #{e.retry_after}s"
rescue Muxi::NotFoundError => e
  puts "Not found: #{e.message}"
rescue Muxi::MuxiError => e
  puts "#{e.code}: #{e.message} (#{e.status_code})"
end
```

Error types: `AuthenticationError`, `AuthorizationError`, `NotFoundError`, `ValidationError`, `RateLimitError`, `ServerError`, `ConnectionError`.

## Notable Endpoints (FormationClient)

| Category | Methods |
|----------|---------|
| Chat/Audio | `chat`, `chat_stream`, `audio_chat`, `audio_chat_stream` |
| Memory | `get_memory_config`, `get_memories`, `add_memory`, `delete_memory`, `get_user_buffer`, `clear_user_buffer`, `clear_session_buffer`, `clear_all_buffers`, `get_buffer_stats` |
| Scheduler | `get_scheduler_config`, `get_scheduler_jobs`, `get_scheduler_job`, `create_scheduler_job`, `delete_scheduler_job` |
| Sessions | `get_sessions`, `get_session`, `get_session_messages`, `restore_session` |
| Requests | `get_requests`, `get_request_status`, `cancel_request` |
| Agents/MCP | `get_agents`, `get_agent`, `get_mcp_servers`, `get_mcp_server`, `get_mcp_tools` |
| Secrets | `get_secrets`, `get_secret`, `set_secret`, `delete_secret` |
| Credentials | `list_credential_services`, `list_credentials`, `get_credential`, `create_credential`, `delete_credential` |
| Identifiers | `get_user_identifiers_for_user`, `link_user_identifier`, `unlink_user_identifier` |
| Triggers/SOP | `get_triggers`, `get_trigger`, `fire_trigger`, `get_sops`, `get_sop` |
| Audit | `get_audit_log`, `clear_audit_log` |
| Config | `get_status`, `get_config`, `get_formation_info`, `get_async_config`, `get_a2a_config`, `get_logging_config`, `get_logging_destinations`, `get_overlord_config`, `get_overlord_soul`, `get_llm_settings` |
| Streaming | `stream_events`, `stream_logs`, `stream_request` |
| User | `resolve_user` |

## Webhook Verification

```ruby
require 'muxi'

post '/webhooks/muxi' do
  payload = request.body.read
  signature = request.env['HTTP_X_MUXI_SIGNATURE']

  unless Muxi::Webhook.verify_signature(payload, signature, ENV['WEBHOOK_SECRET'])
    halt 401, 'Invalid signature'
  end

  event = Muxi::Webhook.parse(payload)

  case event.status
  when 'completed'
    event.content.each { |item| puts item.text if item.type == 'text' }
  when 'failed'
    puts "Error: #{event.error&.message}"
  when 'awaiting_clarification'
    puts "Question: #{event.clarification&.question}"
  end

  { status: 'received' }.to_json
end
```

## Testing Locally

```bash
cd ruby
bundle install
rspec
```
