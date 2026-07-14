#!/usr/bin/env ruby
# AI 聊天伴侣 - 后端服务器
require 'webrick'
require 'json'
require 'fileutils'

PORT = 8080
DOC_ROOT = File.dirname(__FILE__)
DATA_DIR = File.join(DOC_ROOT, 'data')
ACCOUNTS_FILE = File.join(DATA_DIR, 'accounts.json')

FileUtils.mkdir_p(DATA_DIR)

# ===== 文件数据库操作 =====
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

# ===== API 响应 =====
def json_response(res, data, status = 200)
  res['Content-Type'] = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  res['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
  res['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
  res.status = status
  res.body = data.to_json
end

# ===== 服务器 =====
server = WEBrick::HTTPServer.new(
  Port: PORT,
  DocumentRoot: DOC_ROOT,
  BindAddress: '0.0.0.0',
  Logger: WEBrick::Log.new($stdout, WEBrick::Log::INFO),
  AccessLog: [[File.open('/dev/null', 'w'), WEBrick::AccessLog::COMMON_LOG_FORMAT]]
)

# ===== CORS 预检 =====
server.mount_proc '/api' do |req, res|
  if req.request_method == 'OPTIONS'
    json_response(res, { ok: true })
  end
end

# ===== 注册 =====
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

    unless password_hash && password_hash.length > 0
      json_response(res, { success: false, error: '请输入密码' }, 400)
      next
    end

    accounts = read_json(ACCOUNTS_FILE, {})

    if accounts[username]
      json_response(res, { success: false, error: '用户名已存在' }, 409)
      next
    end

    accounts[username] = {
      username: username,
      passwordHash: password_hash,
      createdAt: Time.now.to_i,
      lastLogin: Time.now.to_i,
      failedAttempts: 0,
      lockedUntil: nil
    }
    write_json(ACCOUNTS_FILE, accounts)

    # 创建用户数据文件
    write_json(user_file(username), {
      sessions: [],
      settings: {},
      messages: {},
      memory: {},
      custom_pers: []
    })

    puts "[REGISTER] #{username} created"
    json_response(res, { success: true, username: username })
  rescue => e
    json_response(res, { success: false, error: e.message }, 500)
  end
end

# ===== 登录 =====
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

    # 检查封禁
    if acct['lockedUntil'] && Time.now.to_i < acct['lockedUntil']
      days = ((acct['lockedUntil'] - Time.now.to_i) / 86400.0).ceil
      json_response(res, { success: false, error: "账号已封禁，#{days}天后解封" }, 403)
      next
    end

    # 验证密码
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

    # 登录成功
    acct['failedAttempts'] = 0
    acct['lockedUntil'] = nil
    acct['lastLogin'] = Time.now.to_i
    write_json(ACCOUNTS_FILE, accounts)

    # 返回用户数据
    user_data = read_json(user_file(username), {})
    puts "[LOGIN] #{username} OK"
    json_response(res, {
      success: true,
      username: username,
      data: user_data
    })
  rescue => e
    json_response(res, { success: false, error: e.message }, 500)
  end
end

# ===== 同步：上传 =====
server.mount_proc '/api/sync' do |req, res|
  if req.request_method == 'OPTIONS'
    json_response(res, { ok: true })
    next
  end

  begin
    auth = req['Authorization']&.gsub('Bearer ', '')
    username = req.query['username'] || auth

    unless username
      json_response(res, { success: false, error: '未登录' }, 401)
      next
    end

    accounts = read_json(ACCOUNTS_FILE, {})
    unless accounts[username]
      json_response(res, { success: false, error: '账号不存在' }, 404)
      next
    end

    if req.request_method == 'POST'
      # 上传数据
      body = JSON.parse(req.body)
      write_json(user_file(username), body['data'] || body)
      puts "[SYNC] #{username} data saved (#{(body['data'] || body).to_json.length} bytes)"
      json_response(res, { success: true })
    else
      # 下载数据
      user_data = read_json(user_file(username), {})
      puts "[SYNC] #{username} data loaded"
      json_response(res, { success: true, data: user_data })
    end
  rescue => e
    json_response(res, { success: false, error: e.message }, 500)
  end
end

# ===== 修改密码 =====
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

    # 修改密码
    if new_hash && new_hash.length > 0
      acct['passwordHash'] = new_hash
    end

    # 修改用户名
    if new_username && new_username.length > 0 && new_username != username
      if accounts[new_username]
        json_response(res, { success: false, error: '新用户名已存在' }, 409)
        next
      end
      # 迁移数据文件
      old_file = user_file(username)
      new_file = user_file(new_username)
      if File.exist?(old_file)
        FileUtils.mv(old_file, new_file)
      end
      accounts[new_username] = acct
      accounts[new_username]['username'] = new_username
      accounts.delete(username)
      username = new_username
    end

    write_json(ACCOUNTS_FILE, accounts)
    puts "[CHANGE] #{username} updated"
    json_response(res, { success: true, username: username })
  rescue => e
    json_response(res, { success: false, error: e.message }, 500)
  end
end

# ===== 注销账号 =====
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

    # 删除数据
    accounts.delete(username)
    write_json(ACCOUNTS_FILE, accounts)

    data_file = user_file(username)
    File.delete(data_file) if File.exist?(data_file)

    puts "[DELETE] #{username} removed"
    json_response(res, { success: true })
  rescue => e
    json_response(res, { success: false, error: e.message }, 500)
  end
end

# ===== 启动 =====
puts "=" * 50
puts "🌟 AI 聊天伴侣 - 服务器启动"
puts "=" * 50
puts "  📂 目录: #{DOC_ROOT}"
puts "  🌐 网页: http://localhost:#{PORT}/ai-chat-companion.html"
puts "  📡 API:  http://localhost:#{PORT}/api/"
puts "  💾 数据: #{DATA_DIR}/"
puts "=" * 50

trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }
server.start
