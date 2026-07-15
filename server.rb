#!/usr/bin/env ruby
require 'webrick'
require 'json'
require 'fileutils'

PORT = ENV['PORT'] || 8080
DOC_ROOT = File.dirname(__FILE__)
DATA_DIR = File.join(DOC_ROOT, 'data')
ACCOUNTS_FILE = File.join(DATA_DIR, 'accounts.json')
FileUtils.mkdir_p(DATA_DIR)

def read_json(path, default = {})
  File.exist?(path) ? JSON.parse(File.read(path)) : default
rescue
  default
end

def write_json(path, data)
  File.write(path, JSON.pretty_generate(data))
end

def user_file(username)
  File.join(DATA_DIR, "#{username}.json")
end

def json_response(res, data, status = 200)
  res['Content-Type'] = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  res['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
  res['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
  res.status = status
  res.body = data.to_json
end

server = WEBrick::HTTPServer.new(
  Port: PORT,
  DocumentRoot: DOC_ROOT,
  BindAddress: '0.0.0.0',
  Logger: WEBrick::Log.new($stdout, WEBrick::Log::INFO),
  AccessLog: [[File.open('/dev/null', 'w'), WEBrick::AccessLog::COMMON_LOG_FORMAT]]
)

# ===== Register =====
server.mount_proc '/api/auth/register' do |req, res|
  if req.request_method == 'OPTIONS'
    json_response(res, { ok: true })
    next
  end
  begin
    body = JSON.parse(req.body)
    username = body['username']&.strip
    password_hash = body['passwordHash']&.strip
    unless username && username.length > 0
      json_response(res, { success: false, error: '请输入用户名' }, 400)
      next
    end
    accounts = read_json(ACCOUNTS_FILE, {})
    if accounts[username]
      json_response(res, { success: false, error: '用户名已存在' }, 409)
      next
    end
    accounts[username] = { username: username, passwordHash: password_hash, createdAt: Time.now.to_i, lastLogin: Time.now.to_i, failedAttempts: 0, lockedUntil: nil }
    write_json(ACCOUNTS_FILE, accounts)
    write_json(user_file(username), { sessions: [], settings: {}, messages: {}, memory: {}, custom_pers: [] })
    json_response(res, { success: true, username: username })
  rescue => e
    json_response(res, { success: false, error: e.message }, 500)
  end
end

# ===== Login =====
server.mount_proc '/api/auth/login' do |req, res|
  if req.request_method == 'OPTIONS'
    json_response(res, { ok: true })
    next
  end
  begin
    body = JSON.parse(req.body)
    username = body['username']&.strip
    password_hash = body['passwordHash']&.strip
    accounts = read_json(ACCOUNTS_FILE, {})
    unless accounts[username]
      json_response(res, { success: false, error: '账号不存在' }, 404)
      next
    end
    acct = accounts[username]
    if acct['lockedUntil'] && Time.now.to_i < acct['lockedUntil']
      days = ((acct['lockedUntil'] - Time.now.to_i) / 86400.0).ceil
      json_response(res, { success: false, error: "账号已封禁，#{days}天后解封" }, 403)
      next
    end
    if password_hash != acct['passwordHash']
      acct['failedAttempts'] = (acct['failedAttempts'] || 0) + 1
      if acct['failedAttempts'] >= 10
        acct['lockedUntil'] = Time.now.to_i + 604800
        acct['failedAttempts'] = 0
        write_json(ACCOUNTS_FILE, accounts)
        json_response(res, { success: false, error: '密码错误10次，封禁7天' }, 403)
        next
      end
      write_json(ACCOUNTS_FILE, accounts)
      json_response(res, { success: false, error: "密码错误（还剩#{10 - acct['failedAttempts']}次）" }, 401)
      next
    end
    acct['failedAttempts'] = 0
    acct['lockedUntil'] = nil
    acct['lastLogin'] = Time.now.to_i
    write_json(ACCOUNTS_FILE, accounts)
    user_data = read_json(user_file(username), {})
    json_response(res, { success: true, username: username, data: user_data })
  rescue => e
    json_response(res, { success: false, error: e.message }, 500)
  end
end

# ===== Sync =====
server.mount_proc '/api/sync' do |req, res|
  if req.request_method == 'OPTIONS'
    json_response(res, { ok: true })
    next
  end
  begin
    username = req.query['username']
    unless username
      json_response(res, { success: false, error: '未登录' }, 401)
      next
    end
    if req.request_method == 'POST'
      body = JSON.parse(req.body)
      data = body['data'] || body
      write_json(user_file(username), data)
      json_response(res, { success: true })
    else
      user_data = read_json(user_file(username), {})
      json_response(res, { success: true, data: user_data })
    end
  rescue => e
    json_response(res, { success: false, error: e.message }, 500)
  end
end

# ===== Change Password/Username =====
server.mount_proc '/api/auth/change' do |req, res|
  if req.request_method == 'OPTIONS'
    json_response(res, { ok: true })
    next
  end
  begin
    body = JSON.parse(req.body)
    username = body['username']&.strip
    old_hash = body['oldPasswordHash']&.strip
    new_hash = body['newPasswordHash']&.strip
    new_username = body['newUsername']&.strip
    accounts = read_json(ACCOUNTS_FILE, {})
    acct = accounts[username]
    unless acct
      json_response(res, { success: false, error: '账号不存在' }, 404)
      next
    end
    unless old_hash == acct['passwordHash']
      json_response(res, { success: false, error: '当前密码错误' }, 401)
      next
    end
    if new_hash && new_hash.length > 0
      acct['passwordHash'] = new_hash
    end
    if new_username && new_username.length > 0 && new_username != username
      if accounts[new_username]
        json_response(res, { success: false, error: '新用户名已存在' }, 409)
        next
      end
      old_file = user_file(username)
      new_file = user_file(new_username)
      FileUtils.mv(old_file, new_file) if File.exist?(old_file)
      accounts[new_username] = acct
      accounts[new_username]['username'] = new_username
      accounts.delete(username)
    end
    write_json(ACCOUNTS_FILE, accounts)
    json_response(res, { success: true, username: new_username || username })
  rescue => e
    json_response(res, { success: false, error: e.message }, 500)
  end
end

# ===== Delete Account =====
server.mount_proc '/api/auth/delete' do |req, res|
  if req.request_method == 'OPTIONS'
    json_response(res, { ok: true })
    next
  end
  begin
    body = JSON.parse(req.body)
    username = body['username']&.strip
    password_hash = body['passwordHash']&.strip
    accounts = read_json(ACCOUNTS_FILE, {})
    acct = accounts[username]
    unless acct
      json_response(res, { success: false, error: '账号不存在' }, 404)
      next
    end
    unless password_hash == acct['passwordHash']
      json_response(res, { success: false, error: '密码错误' }, 401)
      next
    end
    accounts.delete(username)
    write_json(ACCOUNTS_FILE, accounts)
    data_file = user_file(username)
    File.delete(data_file) if File.exist?(data_file)
    json_response(res, { success: true })
  rescue => e
    json_response(res, { success: false, error: e.message }, 500)
  end
end

puts "Server started on port #{PORT}"
trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }
server.start
