#!/usr/local/env ruby
# coding: utf-8


# DB
@db = "off_bot.sqlite3"
@db_1st_execute = "PRAGMA journal_mode = MEMORY;"

# use HTTPS
@mastodon_server = "mstdn-workers.com"

require 'net/https'
require 'uri'
require 'json'
require 'sqlite3'
require 'date'

@token = nil

File.open("off_bot.token","r"){|f|
  @token = f.gets.chomp
}

def write_mstdn(form_data)
  uri = URI.parse("https://" + @mastodon_server + "/api/v1/statuses");
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE # :P
  req = Net::HTTP::Post.new(uri.path)
  req['Authorization'] = "Bearer " + @token
  req.set_form_data(form_data)
  res = http.request(req)
  # とりあえず結果は無視する
end

def getTwipla(eventid)
  uri = URI.parse("http://twipla.jp/events/" + eventid);
  http = Net::HTTP.new(uri.host, uri.port)
  req = Net::HTTP::Get.new(uri.path)
  res = http.request(req)
  # 頑張ってパースするよ！
  body = res.body.force_encoding("UTF-8")
  datetime = nil
  title = nil
  location = nil
  body =~ /\<meta +property\=\'og\:title\' +content\=\'([^']+)/
  title = $1
  if body.gsub(/\<.*?\>/,"") =~ /([0-9]+)年([0-9]+)月([0-9]+)日\[.*?\]\s*([0-9]+)\:([0-9]+)/
    datetime = Time.mktime($1,$2,$3,$4,$5)
  elsif body.gsub(/\<.*?\>/,"") =~ /([0-9]+)年([0-9]+)月([0-9]+)日\[.*?\]\s*終日/
    datetime = Time.mktime($1,$2,$3)
  end
  return [nil,nil,nil] if not body.gsub(/\<.*?\>/,"") =~ /mstdn\-workers|社畜丼/
  return [title,location,datetime]
end

def write_ok(db,id)
  d = (db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url from off where id = ?;",id))[0]
  msg = "オフ会情報\n\n"
  msg += "ユーザ:" + d[3] + "(" + d[4] + ") によってオフ会情報 #" + id.to_s + " が登録されました\n\n"
  msg += "「" + d[1] + "」\n\n" if !d[1].nil?
  msg += "場所:" + d[2] + "\n\n" if !d[2].nil?
  t = Time.at(d[0])
  msg += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n\n"
  msg += "\n"
  msg += "詳細:" + d[5]
  write_mstdn({'status' => msg, 'visibility' => 'public'})
end

def generate_data(d)
  msg = "#" + d[6].to_s + " "
  msg += "「" + d[1] + "」\n" if !d[1].nil?
  msg += "場所:" + d[2] + "\n" if !d[2].nil?
  t = Time.at(d[0])
  #msg += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n"
  msg += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n"
  msg += "\n"
  #msg += "詳細:" + d[5] + "\n\n"
  return msg
end

def show_execute(db,opt,row)
  msg = "オフ会情報\n\n"
  msg_hidden = "(" + Time.now.strftime("%Y年%m月%d日 %H時%M分") + "現在の情報です)\n\n"
  opt = "" if opt.nil?
  opt,other = opt.split(/[ \n]+/,2)
  opt = "" if opt.nil?
  if opt == "all"
    msg_hidden += "登録されている情報の最新２０件までのIDリストです\n\n"
    db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,id from off order by off_datetime desc limit 20;") do |row|
      t = Time.at(row[0])
      msg_hidden += "#" + row[6].to_s + ":"
      msg_hidden += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n"
    end
  elsif opt =~ /^\#([0-9]+)$/
    id = $1
    d = db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,id from off where id = ?;",id)
    if d.size < 1
      msg_hidden += "#"+id+" は登録がありません"
    else
      d.each{ |row|
        msg_hidden += generate_data(row)
      }
    end
  else
    msg_hidden += "現時点以降のリストです\n\n"
    d = db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,id from off where off_datetime > ? order by off_datetime;",Time.now.to_i)
    if d.size < 1
      msg_hidden += "登録がありません"
    else
      d.each{ |row|
        msg_hidden += generate_data(row)
      }
    end
  end
  if msg_hidden.length > 400
    msg_hidden = msg_hidden[0,400] + "...多すぎます"
  end
  write_mstdn({'status' => msg_hidden,'spoiler_text' => msg, 'visibility' => 'public'})
end

def val_to_int(intstr)
  return intstr.to_s.gsub(/０/,'0').gsub(/１/,'1').gsub(/２/,'2').gsub(/３/,'3').gsub(/４/,'4').gsub(/５/,'5').gsub(/６/,'6').gsub(/７/,'7').gsub(/８/,'8').gsub(/９/,'9').to_i
end

def add_execute(db,opt,json,row)
    off_datetime = nil
    off_title = nil
    off_location = nil
    account_id = json['status']['account']['id']
    account_name = json['status']['account']['username']
    account_display_name = json['status']['account']['display_name']
    message_content = row[1]
    message_url = json['status']['url']
    message_id = json['status']['id']
    # off_datetimeっぽいものを探す
    year = Time.now.year
    month = nil
    day = nil
    hour = 18
    min = 0
    if opt =~ /\s([0-9０１２３４５６７８９]+)[\:：]([0-9０１２３４５６７８９]+)/
      # 時間？
      hour = $1
      min = $2
    elsif opt =~ /\s([0-9０１２３４５６７８９]+)時([0-9０１２３４５６７８９]+)/
      # 時間？
      hour = $1
      min = $2
    elsif opt =~ /\s([0-9０１２３４５６７８９]+)時/
      # 時間？
      hour = $1
    end
    hour = val_to_int(hour)
    min = val_to_int(min)
    if opt =~ /\s([0-9０１２３４５６７８９]+)[\/／]([0-9０１２３４５６７８９]+)[\/／]([0-9０１２３４５６７８９]+)/
      # 年月日?
      year = $1
      month = $2
      day = $3
    elsif opt =~ /\s([0-9０１２３４５６７８９]+)[\/／]([0-9０１２３４５６７８９]+)/
      # 月日？
      month = $1
      day = $2
      month = val_to_int(month)
      day = val_to_int(day)
      if Date.new(year,month,day) < Date.now
        year += 1
      end
    end
    year = val_to_int(year)
    month = val_to_int(month)
    day = val_to_int(day)
    return if month.nil? or day.nil?
    begin
      off_datetime = Time.local(year,month,day,hour,min)
    rescue
      return
    end
    opt =~ /場所[\:：\s](.*)/
    off_location = $1
    opt =~ /[（［｛「『\(\[\{](.*?)[）］｝」』\)\]\}]/
    off_title = $1
    return if off_datetime.nil? or off_location.nil? or off_title.nil?
      db.execute("insert into off values(NULL,?,?, ?,?,?, ?,?,?, ?, ?);",
                 Time.now.to_i,Time.now.to_i,
                 off_datetime.to_i,off_title,off_location,
                 account_id,account_name,account_display_name,
                 message_url,message_id)
      id = db.last_insert_row_id
      db.execute("insert into off_update values(?,?,?, ?,?,?, ?,?);",
                 id,message_id,Time.now.to_i,
                 account_id,account_name,account_display_name,
                 message_content,message_url)
      write_ok(db,id)
end

def del_execute(db,opt,json,row)
  opt =~ /^\#([0-9]+)$/
  id = $1
  return if id.nil?
  account_id = json['status']['account']['id']
  # check
  check = db.execute("select account_id,message_url from off where id = ?;",id.to_i)
  if check.size < 1
    write_mstdn({'status' => "指定されたオフ会情報が見つかりません id= # " + id, 'visibility' => 'public'})
    return
  end
  addid = check[0][0]
  msgurl = check[0][1]
  if account_id.to_i != addid
    write_mstdn({'status' => "登録ユーザが違うため消せません id= # " + id, 'visibility' => 'public'})
  else
    db.execute("delete from off where id = ?;",id.to_i)
    write_mstdn({'status' => "オフ会情報 # " + id + " を削除しました\n" + "削除されたオフ情報:" + msgurl, 'visibility' => 'public'})
  end
end


def help_execute
  msg = "@off_botの使い方\n\n"
  msg_hidden = "@off_bot show [ all | # 番号]  登録されてる情報を表示 allと # 番号以外を指定すると何も指定しないのと同じ\n"
  msg_hidden += "@off_bot twiplaっぽいアドレス  twiplaのイベントを追加\n"
  msg_hidden += "@off_bot add 日付 「オフ会タイトル」 場所：～  それっぽいオフ会情報を追加\n"
  msg_hidden += "@off_bot del # 番号  それっぽいオフ会情報を削除\n"
  msg_hidden += "@off_bot help これ。\n"
  msg_hidden += "# 番号 内部で勝手に割り振ってるオフ会の番号\n"
  msg_hidden += "\n"
  msg_hidden += "これ以外は基本的に無視します\n"
  msg_hidden += "20秒に1回読み込むのでタイムラグがあります。\n"
  write_mstdn({'status' => msg_hidden,'spoiler_text' => msg, 'visibility' => 'public'})
end

def default_execute(db,arg,json,row)
    off_datetime = nil
    off_title = nil
    off_location = nil
    account_id = json['status']['account']['id']
    account_name = json['status']['account']['username']
    account_display_name = json['status']['account']['display_name']
    message_content = row[1]
    message_url = json['status']['url']
    message_id = json['status']['id']
    if json['status']['content'] =~ /http\:\/\/twipla\.jp\/events\/([0-9]+)/
      off_title,off_location,off_datetime = getTwipla($1)
    else
      # 途中 :P
      # off_datetimeっぽいものを探す
      year = Time.now.year
      month = nil
      day = nil
      hour = 18
      min = 0
      if arg =~ /\s([0-9０１２３４５６７８９]+[\/／])([0-9０１２３４５６７８９]+[\/／])([0-9０１２３４５６７８９]+)/
        # 年月日?
      elsif arg =~ /\s([0-9０１２３４５６７８９]+[\/／])([0-9０１２３４５６７８９]+)/
        # 月日？
      end
    end
    if off_datetime != nil
    puts off_title,off_location,off_datetime
      db.execute("insert into off values(NULL,?,?, ?,?,?, ?,?,?, ?, ?);",
                 Time.now.to_i,Time.now.to_i,
                 off_datetime.to_i,off_title,off_location,
                 account_id,account_name,account_display_name,
                 message_url,message_id)
      id = db.last_insert_row_id
      db.execute("insert into off_update values(?,?,?, ?,?,?, ?,?);",
                 id,message_id,Time.now.to_i,
                 account_id,account_name,account_display_name,
                 message_content,message_url)
      write_ok(db,id)
    end
end


def generate_write_off(db)
  db.execute("select arg,json from read_data;") do |row|
    arg = row[0]
    json = JSON.parse(row[1])
    cmd,opt = arg.split(/[ \n　]+/,2)
    begin
      if cmd == "show"
        show_execute(db,opt,row)
      elsif cmd == "add"
        add_execute(db,opt,json,row)
      elsif cmd == "del"
        del_execute(db,opt,json,row)
      elsif cmd == "help"
        help_execute()
      else
        default_execute(db,arg,json,row)
      end
    end
  end
  # 全部処理が終わったはずなので全部消す
  db.execute("delete from read_data;");
end

def doit
  SQLite3::Database.new(@db) do |db|
    db.execute(@db_1st_execute)
    db.transaction do
      generate_write_off(db)
      #raise Exception # debug
    end
  end
end


doit

