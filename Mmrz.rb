#!/env/bin/ruby
# encoding: utf-8

VERSION = "v0.1.3"
MMRZ_BUILD_WINDOWS_EXE = false

if MMRZ_BUILD_WINDOWS_EXE
  Encoding.default_external = Encoding::CP932
  Encoding.default_internal = Encoding::CP932
else
  Encoding.default_external = Encoding::UTF_8
  Encoding.default_internal = Encoding::UTF_8
end

require 'readline'
require 'sqlite3'
require 'io/console'
require File.dirname(__FILE__) + '/db.rb'

welcome_str = "\
Welcome to Mmrz !!! -- Memorize words easily.
Mmrz is tool help you to memorize words.
Powered by zhanglintc. [#{VERSION}]

Available commands:
 - add:     Add words to word book.
 - delete:  Delete data with given wordID => e.g. delete 3
 - load:    Load formatted file to word book => e.g. load voc.mmz
 - list:    List all your words in word book.
 - mmrz:    Memorize words.
 - exit:    Exit the application.
 \
"

def my_readline prompt
  # Get user's input with CR||LF and front||end spaces removed.

  if MMRZ_BUILD_WINDOWS_EXE
    print prompt
    gets.chomp.gsub(/^\s*|\s*$/, "")
  else
    Readline.readline(prompt, true).chomp.gsub(/^\s*|\s*$/, "")
  end
end

def clear_screen
  # Windows
  if RbConfig::CONFIG['target_os'] == "mingw32"
    system "cls"
  # Linux/Mac
  else
    system "clear"
  end
end

def pause
  while not " " == STDIN.getch do end
end

def get_memorize_words
=begin
  Return a hash contains words reach remind time.
  Hash fomrat:
    selected_rows -- { list: row_as_key => [boolean: remembered, boolean: firstTimeFail] }
=end

  dbMgr = MmrzDBManager.new
  read_rows  = dbMgr.readDB

  # select words that need to be memorized
  selected_rows = {}
  read_rows.each do |r|
    selected_rows[r] = [false, false] if r[3] < Time.now.to_i
  end

  dbMgr.closeDB
  return selected_rows
end

def show_unmemorized_count
  count = get_memorize_words.size
  puts "Note: #{count} words need to be memorized"
end

def cal_remind_time memTimes, type
  curTime = Time.now

  case memTimes
  when 0
    remindTime = curTime + (60 * 5) # 5 minuts
    # remindTime = curTime # 0 minuts, debug mode
  when 1
    remindTime = curTime + (60 * 30) # 30 minuts
  when 2
    remindTime = curTime + (60 * 60 * 12) # 12 hours
  when 3
    remindTime = curTime + (60 * 60 * 24) # 1 day
  when 4
    remindTime = curTime + (60 * 30 * 24 * 2) # 2 days
  when 5
    remindTime = curTime + (60 * 30 * 24 * 4) # 4 days
  when 6
    remindTime = curTime + (60 * 30 * 24 * 7) # 7 days
  when 7
    remindTime = curTime + (60 * 30 * 24 * 15) # 15 days
  else
    remindTime = curTime
  end

  case type
  when "int"
    return remindTime.to_i
  when "str"
    return remindTime.to_s[0..-7]
  end
end

def add_word
  dbMgr = MmrzDBManager.new
  clear_screen()
  puts "Adding mode:"

  while not "exit" == ( command = my_readline("Add => ") )
    words = command.split
    if not [2, 3].include? words.size
      puts "Add: format not correct\n\n"
      next
    end
    
    word          = words[0]
    pronounce     = (words.size == 2 ? words[1] : "#{words[1]} -- #{words[2]}")
    memTimes      = 0
    remindTime    = cal_remind_time(memTimes, "int")
    remindTimeStr = cal_remind_time(memTimes, "str")
    wordID        = dbMgr.getMaxWordID + 1
    
    row = [word, pronounce, memTimes, remindTime, remindTimeStr, wordID]
    dbMgr.insertDB row
  end

  dbMgr.closeDB
  clear_screen()
end

def load_file paras
  if paras.size != 1
    puts "load: command not correct\n\n"
    return
  end

  if not paras[0].include? ".mmz"
    puts "load: only support \".mmz\" file\n\n"
    return
  end

  if MMRZ_BUILD_WINDOWS_EXE
    file_path = paras[0]
  else
    file_path = "#{File.dirname(__FILE__)}/#{paras[0]}"
  end

  begin
    fr = open file_path
  rescue
    puts "load: open file \"#{paras[0]}\" failed\n\n"
    return
  end

  clear_screen()
  puts "load: file load start\n\n"
  dbMgr = MmrzDBManager.new

  not_loaded_line = ""
  line_idx = 0
  no_added = 0
  added = 0
  fr.each_line do |line|
    line_idx += 1
    wordInfo = line.split
    if not [2, 3].include? wordInfo.size
      not_loaded_line += "*not loaded: line #{line_idx}, format error\n"
      no_added += 1
      next
    else
      word          = wordInfo[0]
      pronounce     = (wordInfo.size == 2 ? wordInfo[1] : "#{wordInfo[1]} -- #{wordInfo[2]}")
      memTimes      = 0
      remindTime    = cal_remind_time(memTimes, "int")
      remindTimeStr = cal_remind_time(memTimes, "str")
      wordID        = dbMgr.getMaxWordID + 1

      row = [word, pronounce, memTimes, remindTime, remindTimeStr, wordID]
      printf("loaded: %s <==> %s\n", word, pronounce)
      dbMgr.insertDB row

      added += 1
    end
  end

  fr.close
  dbMgr.closeDB
  puts ""
  puts not_loaded_line
  puts "\nload: load file \"#{paras[0]}\" completed, #{added} words added, #{no_added} aborted\n\n"
end

def del_word paras
  if paras.size != 1
    puts "del: command not correct\n\n"
  else
    wordID = paras[0]
    dbMgr = MmrzDBManager.new
    if dbMgr.deleteDB(wordID)
      puts "del: data with wordID \"#{wordID}\" has successfully removed\n\n"
    else
      puts "del: wordID \"#{wordID}\" not found\n\n"
    end
    dbMgr.closeDB
  end
end

def list_word
  dbMgr = MmrzDBManager.new
  rows = dbMgr.readAllDB
  rows.sort! { |r1, r2| r1[3] <=> r2[3] } # remindTime from short to long
  str_to_less = "Wordbook is shown below:\n\n"
  rows.each do |row|
    word          = row[0]
    pronounce     = row[1]
    memTimes      = row[2]
    remindTime    = row[3]
    remindTimeStr = row[4]
    wordID        = row[5]

    remindTime -= Time.now.to_i
    if remindTime > 0
      day  = remindTime / (60 * 60 * 24)
      hour = remindTime % (60 * 60 * 24) / (60 * 60)
      min  = remindTime % (60 * 60 * 24) % (60 * 60) / 60
    else
      day = hour = min = 0
    end

    remindTimeStr = format("%sd-%sh-%sm", day, hour, min)
    str_to_less += format("%4d => next after %10s, %d times, %s, %s\n", wordID, remindTimeStr, memTimes, word, pronounce)
  end

  system "echo '#{str_to_less}' | less"
  dbMgr.closeDB
  puts ""
end

def mmrz_word
  dbMgr = MmrzDBManager.new

  selected_rows = get_memorize_words
  left_words = selected_rows.size
  if left_words == 0
    clear_screen()
    puts "No word need to be memorized...\n\n"
    return
  end

  # memorize!!!
  while left_words > 0
    selected_rows.each do |row_as_key, paras|
      remembered    = paras[0] # selected_rows[row_as_key][0]
      firstTimeFail = paras[1] # selected_rows[row_as_key][1]

      if not remembered
        clear_screen()
        puts  "Memorize mode:\n\n"
        puts  "[#{left_words}] #{ left_words == 1 ? 'word' : 'words'} left:\n\n"
        if MMRZ_BUILD_WINDOWS_EXE
          puts  "単語: ".encode("cp932") + row_as_key[0]
          puts  "-------------------"
          print "秘密: ".encode("cp932")
        else
          puts  "単語: #{row_as_key[0]}"
          puts  "-------------------"
          print "秘密: "
        end
        pause
        puts "#{row_as_key[1]}\n\n"

        # Do you remember
        while true
          puts "Do you remember? (yes/no/pass)"
          command = my_readline("=> ")
          case command
          when "yes"
            # mark remembered as true
            selected_rows[row_as_key][0] = true # remembered = true
            left_words -= 1
            row_as_key[2] += 1 if not firstTimeFail
            row_as_key[3] = cal_remind_time row_as_key[2], "int"
            row_as_key[4] = cal_remind_time row_as_key[2], "str"
            dbMgr.updateDB row_as_key
            break # break "Do you remember"
          when "pass"
            selected_rows[row_as_key][0] = true # remembered = true
            left_words -= 1
            row_as_key[2] = 8
            dbMgr.updateDB row_as_key
            break # break "Do you remember"
          when "no"
            selected_rows[row_as_key][1] = true # firstTimeFail = true
            break # break "Do you remember"
          when "exit"
            clear_screen()
            return # return mmrz_word()
          else
            redo # redo "Do you remember"
          end
        end
      end
    end
  end

  clear_screen()
  puts "Memorize completed...\n\n"
  dbMgr.closeDB
end

if __FILE__ == $0
  dbMgr = MmrzDBManager.new
  dbMgr.createDB
  dbMgr.closeDB

  clear_screen()
  puts welcome_str

  while true
    show_unmemorized_count()
    raw_str  = my_readline("Mmrz => ")
    raw_list = raw_str.split
    command  = raw_list.shift
    paras    = raw_list
    case command
    when "exit"
      clear_screen()
      exit()
    when "reset"
      clear_screen()
      puts welcome_str
    when "add"
      add_word()
    when "delete"
      del_word(paras)
    when "load"
      load_file(paras)
    when "list"
      list_word()
    when "mmrz"
      mmrz_word()
    else
      puts "Mmrz: command not found\n\n"
    end
  end
end


