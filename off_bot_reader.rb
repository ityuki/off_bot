#!/usr/local/env ruby
# coding: utf-8

# DB
@db = "off_bot.sqlite3"
@db_1st_execute = "PRAGMA journal_mode = MEMORY;"

# use HTTPS
@mastodon_server = "mstdn-workers.com"

@username = '@off_bot'

require 'net/https'
require 'uri'
require 'json'
require 'sqlite3'
require 'date'

@token = nil

File.open("off_bot.token","r"){|f|
  @token = f.gets.chomp
}


@init_sql = [
<<-SQL_EOF1,<<-SQL_EOF2,<<-SQL_EOF3,<<-SQL_EOF4,<<-SQL_EOF5,<<-SQL_EOF6,<<-SQL_EOF7
  -- 最終読み込みIDと時間を保持
  create table if not exists reader(
    last_id integer not null, -- 最終読み込みID
    read_date integer not null -- 最終読み込み時間
  );
SQL_EOF1
  -- 処理用の中間結果を保持
  create table if not exists read_data(
    arg text not null, -- 引数
    json text not null -- データ
  );
SQL_EOF2
  -- LTL最終読み込みIDと時間を保持
  create table if not exists reader_ltl(
    last_id integer not null, -- 最終読み込みID
    read_date integer not null -- 最終読み込み時間
  );
SQL_EOF3
  -- LTL処理用の中間結果を保持
  create table if not exists read_data_ltl(
    json text not null -- データ
  );
SQL_EOF4
  -- オフ会情報を保持
  create table if not exists off(
    id integer primary key autoincrement, -- オフID
    create_at integer not null, -- 作成日時
    last_update integer not null, -- 最終更新日時
    
    off_datetime integer not null, -- オフ会日時
    off_title text, -- オフ会のタイトル（分かれば）
    off_location text, -- オフ会の場所（分かれば）
    off_url text, -- オフ会関連URL
    
    account_id integer not null, -- 更新者アカウントID
    account_name text not null, -- 更新者アカウント名
    account_display_name text not null, -- 更新者表示名
    
    message_url text not null, -- 発言URL
    
    message_id integer not null -- オフ会情報最新更新情報
  );
SQL_EOF5
  create index if not exists off_idx_off_url on off(off_url);
SQL_EOF6
  -- オフ会情報の更新情報を保持
  create table if not exists off_update(
    id integer not null, -- オフID
    message_id integer not null, -- 更新発言番号
    create_at integer not null, -- 追加日
    
    account_id integer not null, -- 更新者アカウントID
    account_name text not null, -- 更新者アカウント名
    account_display_name text not null, -- 更新者表示名
    
    message_content text not null, -- 発言内容
    message_url text not null, -- 発言URL
    
    primary key(id,message_id) -- 主キー
  );
SQL_EOF7
]

def db_init
  # init
  SQLite3::Database.new(@db) do |db|
    db.execute(@db_1st_execute)
    db.transaction do
      @init_sql.each{|sql|
        db.execute(sql)
      }
    end
  end
end

def load_mstdn(form_data)
  uri = URI.parse("https://" + @mastodon_server + "/api/v1/notifications");
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE # :P
  req = Net::HTTP::Get.new(uri.path)
  req['Authorization'] = "Bearer " + @token
  req.set_form_data(form_data)
  res = http.request(req)

  return JSON.parse(res.body)
end

def load_mstdn_ltl(form_data)
  uri = URI.parse("https://" + @mastodon_server + "/api/v1/timelines/public");
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE # :P
  req = Net::HTTP::Get.new(uri.path)
  req['Authorization'] = "Bearer " + @token
  req.set_form_data(form_data)
  res = http.request(req)

  return JSON.parse(res.body)
end

def first_load
  SQLite3::Database.new(@db) do |db|
    db.execute(@db_1st_execute)
    db.transaction do
      if (db.execute("select count(*) from reader;"))[0][0] == 0 then
        # 最初は読み飛ばす
        json = load_mstdn({'local' => '1','limit' => 1})
        # 最新値を設定
        db.execute("insert into reader values(?,?);",json[0]['id'].to_i,Time.now.to_i)
      end
    end
  end
end

def first_load_ltl
  SQLite3::Database.new(@db) do |db|
    db.execute(@db_1st_execute)
    db.transaction do
      if (db.execute("select count(*) from reader_ltl;"))[0][0] == 0 then
        # 最初は読み飛ばす
        json = load_mstdn_ltl({'local' => '1','limit' => 1})
        # 最新値を設定
        db.execute("insert into reader_ltl values(?,?);",json[0]['id'].to_i,Time.now.to_i)
      end
    end
  end
end

def load_all
  SQLite3::Database.new(@db) do |db|
    db.execute(@db_1st_execute)
    db.transaction do
      # 最終IDを取得
      last_id = (db.execute("select last_id from reader;"))[0][0]
#      # 全部読み込む
      json_all = []
#      json = load_mstdn({'local' => '1','limit' => 1})
#      max = json[0]['id'].to_i
#      i = max
#      while(i >= last_id) do
#        sleep(0.1)
#        puts i.to_s + " load (limit 20)"
#        json = load_mstdn({'local' => '1','since_id' => (i-20+1).to_s,'max_id' => (i+1).to_s,'limit' => '20'})
#        i -= 20
#        next if json.size < 1
        json = load_mstdn({'local' => '1','since_id' => (last_id).to_s,'limit' => '30'})
        if json.instance_of?(Hash) and !json.has_key?('error')
          puts "error:" + json['error']
          return
        end
        max = last_id
        json.each{|j|
          next if j['id'].to_i <= last_id
          max = j['id'].to_i if max < j['id'].to_i
          next if j['type'] != 'mention'
          next if '@' + j['account']['username'] == @username
          json_all.push(j)
        }
#      end
      db.execute("update reader set last_id = ?, read_date = ?",max,Time.now.to_i)
      target = []
      json_all.each{|json|
        if json['status']['content'] =~ /\<a +href\=\"https\:\/\/mstdn\-workers\.com\/#{@username}\"/ then
          message = json['status']['content'].gsub(/<br\s*\/\s*>/,"\n").gsub(/\<.*?\>/,"")
          control,arg = message.split(/#{@username}[ \n　]*/,2)
          #if control == @username then
          arg = "" if arg.nil?
puts "reader:" + arg
          db.execute("insert into read_data values(?,?);",arg,JSON.dump(json))
        end
      }
    end
  end
end

def load_ltl
  json_all = []
  SQLite3::Database.new(@db) do |db|
    db.execute(@db_1st_execute)
    db.transaction do
      # 最終IDを取得
      last_id = (db.execute("select last_id from reader_ltl;"))[0][0]
#      # 全部読み込む
#      json = load_mstdn({'local' => '1','limit' => 1})
#      max = json[0]['id'].to_i
#      i = max
#      while(i >= last_id) do
#        sleep(0.1)
#        puts i.to_s + " load (limit 20)"
#        json = load_mstdn({'local' => '1','since_id' => (i-20+1).to_s,'max_id' => (i+1).to_s,'limit' => '20'})
#        i -= 20
#        next if json.size < 1
        json = load_mstdn_ltl({'local' => '1','since_id' => (last_id).to_s,'limit' => '30'})
        if json.instance_of?(Hash) and !json.has_key?('error')
          puts "LTL error:" + json['error']
          return json_all
        end
        max = last_id
        json.each{|j|
          max = j['id'].to_i if max < j['id'].to_i
          next if j['id'].to_i <= last_id
          # next if j['type'] != 'mention'
          next if '@' + j['account']['username'] == @username
          # twipla専用
          next if !(j['content'] =~ /http\:\/\/twipla\.jp\/events\/([0-9]+)/)
          json_all.push(j)
        }
#      end
      db.execute("update reader_ltl set last_id = ?, read_date = ?",max,Time.now.to_i)
      target = []
      json_all.each{|json|
        #if json['status']['content'] =~ /\<a +href\=\"https\:\/\/mstdn\-workers\.com\/#{@username}\"/ then
          #message = json['status']['content'].gsub(/<br\s*\/\s*>/,"\n").gsub(/\<.*?\>/,"")
          #control,arg = message.split(/#{@username}[ \n　]*/,2)
          ##if control == @username then
          #arg = "" if arg.nil?
          json['content'] =~ /http\:\/\/twipla\.jp\/events\/([0-9]+)/
puts "reader_ltl: http://twipla.jp/events/" + $1
          db.execute("insert into read_data_ltl values(?);",JSON.dump(json))
        #end
      }
    end
  end
  return json_all
end


db_init
first_load
load_all
first_load_ltl
while(load_ltl().size > 0) do
end


