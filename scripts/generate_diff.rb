# may or may not be slop
#!/usr/bin/env ruby
# Generates files from raw/ that don't exist in reference/ into diff/
# For mdb files, generates a diff JSON containing only new keys

require 'fileutils'
require 'json'
BASE_DIR = File.expand_path(__dir__)
RAW_DIR = File.join(BASE_DIR, 'raw')
REF_DIR = File.join(BASE_DIR, 'reference')
DIFF_DIR = File.join(BASE_DIR, 'diff')

# Folders that have a 'data' subdirectory in reference but not in raw
FOLDERS_WITH_DATA_SUBDIR = %w[home story]

# Mapping of raw mdb files to their reference counterparts
MDB_FILE_MAPPING = {
  'character_system_text.json' => 'character_system_text_dict.json',
  'text_data.json' => 'text_data_dict.json',
  'text_data_dict.json' => 'text_data_dict.json',
  'race_jikkyo_comment.json' => 'race_jikkyo_comment.json',
  'race_jikkyo_message.json' => 'race_jikkyo_message.json'
}

def get_reference_path(raw_relative_path)
  parts = raw_relative_path.split(File::SEPARATOR)
  folder = parts.first

  if FOLDERS_WITH_DATA_SUBDIR.include?(folder)
    # Insert 'data' after the folder name
    File.join(folder, 'data', *parts[1..])
  else
    raw_relative_path
  end
end

def get_mdb_reference_file(raw_filename)
  MDB_FILE_MAPPING[raw_filename]
end

# Recursively find keys in raw_hash that don't exist in ref_hash
# Returns a new hash with only the missing keys
def diff_nested_hash(raw_hash, ref_hash)
  diff = {}

  raw_hash.each do |key, value|
    if ref_hash.nil? || !ref_hash.key?(key)
      # Key doesn't exist in reference - include entire subtree
      diff[key] = value
    elsif value.is_a?(Hash) && ref_hash[key].is_a?(Hash)
      # Both are hashes - recurse
      nested_diff = diff_nested_hash(value, ref_hash[key])
      diff[key] = nested_diff unless nested_diff.empty?
    end
    # If key exists and values are not hashes, skip (already translated)
  end

  diff
end

def process_mdb_files
  mdb_raw_dir = File.join(RAW_DIR, 'mdb')
  mdb_ref_dir = File.join(REF_DIR, 'mdb')
  mdb_diff_dir = File.join(DIFF_DIR, 'mdb')

  return unless Dir.exist?(mdb_raw_dir)

  raw_files = Dir.glob(File.join(mdb_raw_dir, '*.json'))
                 .reject { |f| File.basename(f) == '.gitkeep' }

  puts "\n=== Processing MDB files (content diff) ==="

  raw_files.each do |raw_file|
    raw_filename = File.basename(raw_file)
    ref_filename = get_mdb_reference_file(raw_filename)

    unless ref_filename
      puts "  No mapping for #{raw_filename}, skipping"
      next
    end

    ref_file = File.join(mdb_ref_dir, ref_filename)

    unless File.exist?(ref_file)
      # No reference file - copy entire raw file
      FileUtils.mkdir_p(mdb_diff_dir)
      dest = File.join(mdb_diff_dir, raw_filename)
      FileUtils.cp(raw_file, dest)
      puts "  Copied entire file (no reference): #{raw_filename}"
      next
    end

    # Both files exist - compute diff
    raw_data = JSON.parse(File.read(raw_file))
    ref_data = JSON.parse(File.read(ref_file))

    diff_data = diff_nested_hash(raw_data, ref_data)

    if diff_data.empty?
      puts "  No new keys in: #{raw_filename}"
    else
      FileUtils.mkdir_p(mdb_diff_dir)
      dest = File.join(mdb_diff_dir, raw_filename)
      File.write(dest, JSON.pretty_generate(diff_data))

      # Count total new entries
      count = count_leaf_entries(diff_data)
      puts "  Generated diff for #{raw_filename}: #{count} new entries"
    end
  end
end

def count_leaf_entries(hash)
  count = 0
  hash.each do |_key, value|
    if value.is_a?(Hash)
      count += count_leaf_entries(value)
    else
      count += 1
    end
  end
  count
end

def process_non_mdb_files
  puts "=== Processing non-MDB files (file existence check) ==="

  # Find all files in raw (excluding .gitkeep and mdb folder)
  raw_files = Dir.glob(File.join(RAW_DIR, '**', '*'))
                 .select { |f| File.file?(f) }
                 .reject { |f| File.basename(f) == '.gitkeep' }
                 .reject { |f| f.start_with?(File.join(RAW_DIR, 'mdb')) }

  missing_files = []

  raw_files.each do |raw_file|
    raw_relative = raw_file.sub("#{RAW_DIR}/", '')
    ref_relative = get_reference_path(raw_relative)
    ref_file = File.join(REF_DIR, ref_relative)

    unless File.exist?(ref_file)
      missing_files << raw_relative
    end
  end

  puts "Found #{missing_files.size} files in raw/ that don't exist in reference/"

  missing_files.each do |relative_path|
    src = File.join(RAW_DIR, relative_path)
    dest = File.join(DIFF_DIR, relative_path)

    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(src, dest)
    puts "  Copied: #{relative_path}"
  end

  missing_files.size
end

def main
  non_mdb_count = process_non_mdb_files
  process_mdb_files

  puts "\nDone!"
end

main
