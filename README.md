# MUXI Ruby SDK

Official Ruby SDK for [MUXI](https://muxi.ai) — infrastructure for AI agents.

**Highlights**
- Pure Ruby with stdlib only (no external dependencies)
- Built-in retries, idempotency, and typed errors
- Streaming helpers for chat/audio and deploy/log tails

> Need deeper usage notes? See the [User Guide](https://github.com/muxi-ai/muxi-ruby/blob/main/USER_GUIDE.md) for streaming, retries, and auth details.

## Installation

Add to your Gemfile:

```ruby
gem 'muxi'
```

Or install directly:

```bash
gem install muxi
```

## Quick Start

### Server Management (Control Plane)

```ruby
require 'muxi'

# Create a server client for managing formations
server = Muxi::ServerClient.new(
  url: ENV['MUXI_SERVER_URL'],
  key_id: ENV['MUXI_KEY_ID'],
  secret_key: ENV['MUXI_SECRET_KEY']
)

# List formations
formations = server.list_formations
formations['formations'].each do |f|
  puts "#{f['id']}: #{f['status']}"
end

# Get server status
status = server.status
puts "Uptime: #{status['uptime']}s"
```

### Formation Usage (Runtime API)

```ruby
require 'muxi'

# Create a formation client
client = Muxi::FormationClient.new(
  formation_id: 'my-bot',
  server_url: ENV['MUXI_SERVER_URL'],
  admin_key: ENV['MUXI_ADMIN_KEY'],
  client_key: ENV['MUXI_CLIENT_KEY']
)

# Or connect directly to a formation
client = Muxi::FormationClient.new(
  url: 'http://localhost:8001',
  admin_key: ENV['MUXI_ADMIN_KEY'],
  client_key: ENV['MUXI_CLIENT_KEY']
)

# Chat (non-streaming)
response = client.chat({ message: 'Hello!' }, user_id: 'user123')
puts response['message']

# Chat (streaming)
client.chat_stream({ message: 'Tell me a story' }, user_id: 'user123') do |event|
  data = JSON.parse(event['data']) rescue event['data']
  print data['text'] if data.is_a?(Hash) && data['text']
end

# Health check
health = client.health
puts "Status: #{health['status']}"
```

## Webhook Verification

```ruby
require 'muxi'

# In your webhook handler (e.g., Rails controller)
def webhook
  payload = request.raw_post
  signature = request.headers['X-Muxi-Signature']
  
  unless Muxi::Webhook.verify_signature(payload, signature, ENV['WEBHOOK_SECRET'])
    render json: { error: 'Invalid signature' }, status: 401
    return
  end
  
  event = Muxi::Webhook.parse(payload)
  
  case event.status
  when 'completed'
    event.content.each do |item|
      puts item.text if item.type == 'text'
    end
  when 'failed'
    puts "Error: #{event.error.message}"
  when 'awaiting_clarification'
    puts "Question: #{event.clarification.question}"
  end
  
  render json: { received: true }
end
```

## Configuration

### Environment Variables

- `MUXI_DEBUG=1` - Enable debug logging

### Client Options

```ruby
Muxi::ServerClient.new(
  url: 'https://muxi.example.com:7890',
  key_id: 'your-key-id',
  secret_key: 'your-secret-key',
  timeout: 30,        # Request timeout in seconds
  max_retries: 3,     # Retry on 429/5xx errors
  debug: true         # Enable debug logging
)
```

## Error Handling

```ruby
begin
  server.get_formation('nonexistent')
rescue Muxi::NotFoundError => e
  puts "Not found: #{e.message}"
rescue Muxi::AuthenticationError => e
  puts "Auth failed: #{e.message}"
rescue Muxi::RateLimitError => e
  puts "Rate limited. Retry after: #{e.retry_after}s"
rescue Muxi::MuxiError => e
  puts "Error: #{e.message} (#{e.status_code})"
end
```

## Requirements

- Ruby 3.0+
- No external dependencies (uses stdlib only)

## License

MIT
