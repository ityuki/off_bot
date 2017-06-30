#!/usr/local/env ruby
# coding: utf-8


while(true) do
  begin
    system("ruby off_bot_reader.rb")
    system("ruby off_bot_check_write.rb")
  rescue => e
    puts "error"
    puts e
  end
  sleep(60)
end




