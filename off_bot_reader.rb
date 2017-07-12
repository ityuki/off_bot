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
<<-SQL_EOF1,<<-SQL_EOF2,<<-SQL_EOF3,<<-SQL_EOF4
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
  -- オフ会情報を保持
  create table if not exists off(
    id integer primary key autoincrement, -- オフID
    create_at integer not null, -- 作成日時
    last_update integer not null, -- 最終更新日時
    
    off_datetime integer not null, -- オフ会日時
    off_title text, -- オフ会のタイトル（分かれば）
    off_location text, -- オフ会の場所（分かれば）
    
    account_id integer not null, -- 更新者アカウントID
    account_name text not null, -- 更新者アカウント名
    account_display_name text not null, -- 更新者表示名
    
    message_url text not null, -- 発言URL
    
    message_id integer not null -- オフ会情報最新更新情報
  );
SQL_EOF3
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
SQL_EOF4
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

def load_all
  SQLite3::Database.new(@db) do |db|
    db.execute(@db_1st_execute)
    db.transaction do
      # 最終IDを取得
      last_id = (db.execute("select last_id from reader;"))[0][0]
      # 全部読み込む
      json_all = []
      json = load_mstdn({'local' => '1','limit' => 1})
      max = json[0]['id'].to_i
      i = max
#      while(i >= last_id) do
#        sleep(0.1)
#        puts i.to_s + " load (limit 20)"
#        json = load_mstdn({'local' => '1','since_id' => (i-20+1).to_s,'max_id' => (i+1).to_s,'limit' => '20'})
#        i -= 20
#        next if json.size < 1
        json = load_mstdn({'local' => '1','since_id' => (last_id).to_s,'limit' => '30'})
        json.each{|j|
          next if j['id'].to_i <= last_id
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

db_init
first_load
load_all


