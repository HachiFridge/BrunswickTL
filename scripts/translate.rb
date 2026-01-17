require 'net/http'
require 'json'
require 'uri'

# ==========================================
# CONFIGURATION
# ==========================================
LM_STUDIO_URL = "http://localhost:1234/v1/chat/completions"
HISTORY_LIMIT = 0 

# Set this to TRUE to force everything into one single line
# Set to FALSE if you want to keep the model's paragraph breaks
FLATTEN_OUTPUT = true 

# ==========================================

$chat_history = []

def translate_text(text)
  uri = URI(LM_STUDIO_URL)
  
  current_messages = []
  if HISTORY_LIMIT > 0
    current_messages = $chat_history.last(HISTORY_LIMIT * 2)
  end
  current_messages << { role: "user", content: text }

  payload = {
    model: "local-model", 
    messages: current_messages,
    temperature: 0.1,
    stream: false
  }

  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
  request.body = payload.to_json

  begin
    response = http.request(request)
    data = JSON.parse(response.body)
    
    if data['choices'] && data['choices'][0]
      raw_content = data['choices'][0]['message']['content']
      
      # === CLEANING LOGIC ===
      clean_content = raw_content.strip
      
      if FLATTEN_OUTPUT
        # Replaces all line breaks with a single space and removes double spaces
        clean_content = clean_content.gsub("\n", " ").squeeze(" ")
      end
      
      # Save history (we save the CLEAN version to keep context tidy)
      $chat_history << { role: "user", content: text }
      $chat_history << { role: "assistant", content: clean_content }
      
      return clean_content
    else
      return "Error: No response."
    end
  rescue StandardError => e
    return "Connection Error: #{e.message}"
  end
end

# MAIN LOOP
puts "================================================="
puts " Japanese -> English (Clean Copy Mode)"
puts "================================================="
puts "Type 'exit' to quit. Type 'clear' to reset memory."

loop do
  print "\n> " # Simple prompt to save space
  input = gets.chomp

  break if input.strip.downcase == 'exit'
  next if input.strip.empty?

  if input.strip.downcase == 'clear'
    $chat_history = []
    puts "[Memory Cleared]"
    next
  end

  translation = translate_text(input)
  
  # Print strictly the translation for easy double-click selection
  puts "\n" + translation + "\n"
end