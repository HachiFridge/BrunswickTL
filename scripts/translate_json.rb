require 'net/http'
require 'json'
require 'uri'
require 'io/console'
require 'reline'

# ==========================================
# CONFIGURATION
# ==========================================
LM_STUDIO_URL = "http://localhost:1234/v1/chat/completions"

# Set this to TRUE to force everything into one single line
# Set to FALSE if you want to keep the model's paragraph breaks
FLATTEN_OUTPUT = true

# ==========================================

def translate_text(text)
  uri = URI(LM_STUDIO_URL)

  messages = [{ role: "user", content: text }]

  payload = {
    model: "local-model",
    messages: messages,
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
      clean_content = raw_content.strip

      if FLATTEN_OUTPUT
        clean_content = clean_content.gsub("\n", " ").squeeze(" ")
      end

      return clean_content
    else
      return nil
    end
  rescue StandardError => e
    puts "Connection Error: #{e.message}"
    return nil
  end
end

def needs_translation?(text)
  return false if text.nil? || text.empty?
  # Check if text contains Japanese characters (Hiragana, Katakana, or Kanji)
  text.match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
end

def find_translatable_strings(obj, path = [])
  results = []

  case obj
  when Hash
    obj.each do |key, value|
      results.concat(find_translatable_strings(value, path + [key]))
    end
  when Array
    obj.each_with_index do |value, index|
      results.concat(find_translatable_strings(value, path + [index]))
    end
  when String
    if needs_translation?(obj)
      results << { path: path, value: obj }
    end
  end

  results
end

def get_value_at_path(obj, path)
  path.reduce(obj) { |current, key| current[key] }
end

def set_value_at_path(obj, path, value)
  parent = path[0..-2].reduce(obj) { |current, key| current[key] }
  parent[path.last] = value
end

def display_context(json_data, path, context_lines = 2)
  # Show the path and surrounding context
  puts "\n--- Path: #{path.map(&:to_s).join(' -> ')} ---"
end

def prompt_action
  puts "\n[s]ave | [e]dit | [r]egenerate | [k]eep original | [q]uit"
  print "> "
  input = $stdin.gets
  return 'q' if input.nil?
  input.chomp.downcase
end

def manual_edit(current_translation)
  puts "\nEdit translation (arrow keys to move, Enter to confirm):"
  Reline.pre_input_hook = -> {
    Reline.insert_text(current_translation)
    Reline.redisplay
    Reline.pre_input_hook = nil
  }
  input = Reline.readline("> ", false)
  return current_translation if input.nil?
  input.empty? ? current_translation : input
end

# ==========================================
# MAIN
# ==========================================

if ARGV.empty?
  puts "Usage: ruby translate_json.rb <input.json>"
  exit 1
end

input_file = ARGV[0]

unless File.exist?(input_file)
  puts "Error: File '#{input_file}' not found."
  exit 1
end

puts "================================================="
puts " JSON Translator (Japanese -> English)"
puts "================================================="
puts "File: #{input_file}"
puts "================================================="

# Load JSON
begin
  json_content = File.read(input_file)
  json_data = JSON.parse(json_content)
rescue JSON::ParserError => e
  puts "Error parsing JSON: #{e.message}"
  exit 1
end

# Find all translatable strings
translatable = find_translatable_strings(json_data)

if translatable.empty?
  puts "\nNo Japanese text found in the file."
  exit 0
end

puts "\nFound #{translatable.length} string(s) to translate.\n"

translated_count = 0
skipped_count = 0

translatable.each_with_index do |item, index|
  path = item[:path]
  original = item[:value]

  puts "\n#{'=' * 50}"
  puts "[#{index + 1}/#{translatable.length}]"
  display_context(json_data, path)
  puts "\nOriginal:"
  puts original
  puts ""

  # Get initial translation
  print "Translating... "
  translation = translate_text(original)

  if translation.nil?
    puts "Failed!"
    puts "Could not get translation. [k]eep original or [q]uit?"
    input = $stdin.gets
    action = input.nil? ? 'q' : input.chomp.downcase
    if action == 'q'
      break
    else
      skipped_count += 1
      next
    end
  end

  puts "Done!\n\n"
  puts "Translation:"
  puts translation

  # Action loop
  loop do
    action = prompt_action

    case action
    when 's'
      set_value_at_path(json_data, path, translation)
      translated_count += 1
      File.write(input_file, JSON.pretty_generate(json_data))
      puts "Saved!"
      break

    when 'e'
      translation = manual_edit(translation)
      puts "\nUpdated translation:"
      puts translation

    when 'r'
      print "Regenerating... "
      new_translation = translate_text(original)
      if new_translation
        translation = new_translation
        puts "Done!\n\n"
        puts "New translation:"
        puts translation
      else
        puts "Failed! Keeping previous translation."
      end

    when 'k'
      skipped_count += 1
      puts "Keeping original."
      break

    when 'q'
      puts "\nSaving progress and exiting..."
      File.write(input_file, JSON.pretty_generate(json_data))
      puts "Saved to: #{input_file}"
      puts "Translated: #{translated_count}, Skipped: #{skipped_count}"
      exit 0

    else
      puts "Unknown option. Please choose [s]ave, [e]dit, [r]egenerate, [k]eep, or [q]uit."
    end
  end
end

# Save final output
puts "\n#{'=' * 50}"
puts "Translation complete!"
puts "Translated: #{translated_count}, Skipped: #{skipped_count}"
puts "#{'=' * 50}"

File.write(input_file, JSON.pretty_generate(json_data))
puts "Saved to: #{input_file}"
