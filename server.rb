require 'webrick'
require 'json'
require 'fileutils'

PORT = ENV['PORT'] ? ENV['PORT'].to_i : 8080
ROOT = File.dirname(__FILE__)
DATA_DIR = File.join(ROOT, 'data')
ACCOUNTS_FILE = File.join(DATA_DIR, 'accounts.json')
FileUtils.mkdir_p(DATA_DIR)

def rjson(path, d = {})
  File.exist?(path) ? JSON.parse(File.read(path)) : d
rescue
  d
end

def wjson(path, data)
  File.write(path, JSON.generate(data))
end

server = WEBrick::HTTPServer.new(
  Port: PORT, DocumentRoot: ROOT, BindAddress: '0.0.0.0',
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN), AccessLog: []
)

server.mount_proc '/api/auth/register' do |req, res|
  res['Content-Type'] = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  next if req.request_method == 'OPTIONS'
  b = JSON.parse(req.body)
  u, h = b['username'].to_s.strip, b['passwordHash'].to_s.strip
  return res.body = '{"success":false}' if u.empty?
  a = rjson(ACCOUNTS_FILE, {})
  return res.body = '{"success":false,"error":"用户名已存在"}' if a[u]
  a[u] = { username: u, passwordHash: h, createdAt: Time.now.to_i, lastLogin: Time.now.to_i, failedAttempts: 0, lockedUntil: nil }
  wjson(ACCOUNTS_FILE, a)
  wjson(File.join(DATA_DIR, "#{u}.json"), { sessions: [], settings: {}, messages: {}, memory: {}, custom_pers: [] })
  res.body = '{"success":true}'
rescue => e
  res.body = "{\"success\":false,\"error\":\"#{e.message}\"}"
end

server.mount_proc '/api/auth/login' do |req, res|
  res['Content-Type'] = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  next if req.request_method == 'OPTIONS'
  b = JSON.parse(req.body)
  u, h = b['username'].to_s.strip, b['passwordHash'].to_s.strip
  a = rjson(ACCOUNTS_FILE, {})
  return res.body = '{"success":false,"error":"账号不存在"}' unless a[u]
  ac = a[u]
  if ac['lockedUntil'] && Time.now.to_i < ac['lockedUntil']
    d = ((ac['lockedUntil'] - Time.now.to_i) / 86400.0).ceil
    return res.body = "{\"success\":false,\"error\":\"封禁中，#{d}天后解封\"}"
  end
  if h != ac['passwordHash']
    ac['failedAttempts'] = (ac['failedAttempts'] || 0) + 1
    if ac['failedAttempts'] >= 10
      ac['lockedUntil'] = Time.now.to_i + 604800; ac['failedAttempts'] = 0
      wjson(ACCOUNTS_FILE, a)
      return res.body = '{"success":false,"error":"密码错误10次，封禁7天"}'
    end
    wjson(ACCOUNTS_FILE, a)
    return res.body = "{\"success\":false,\"error\":\"密码错误（#{10 - ac['failedAttempts']}次剩余）\"}"
  end
  ac['failedAttempts'] = 0; ac['lockedUntil'] = nil; ac['lastLogin'] = Time.now.to_i
  wjson(ACCOUNTS_FILE, a)
  data = rjson(File.join(DATA_DIR, "#{u}.json"), {})
  res.body = JSON.generate({ success: true, username: u, data: data })
rescue => e
  res.body = "{\"success\":false,\"error\":\"#{e.message}\"}"
end

server.mount_proc '/api/sync' do |req, res|
  res['Content-Type'] = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  next if req.request_method == 'OPTIONS'
  u = req.query['username'].to_s.strip
  return res.body = '{"success":false}' if u.empty?
  if req.request_method == 'POST'
    b = JSON.parse(req.body)
    wjson(File.join(DATA_DIR, "#{u}.json"), b['data'] || b)
    res.body = '{"success":true}'
  else
    data = rjson(File.join(DATA_DIR, "#{u}.json"), {})
    res.body = JSON.generate({ success: true, data: data })
  end
rescue => e
  res.body = "{\"success\":false,\"error\":\"#{e.message}\"}"
end

server.mount_proc '/api/auth/change' do |req, res|
  res['Content-Type'] = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  next if req.request_method == 'OPTIONS'
  b = JSON.parse(req.body)
  u = b['username'].to_s.strip
  a = rjson(ACCOUNTS_FILE, {})
  return res.body = '{"success":false,"error":"账号不存在"}' unless a[u]
  return res.body = '{"success":false,"error":"密码错误"}' if b['oldPasswordHash'].to_s != a[u]['passwordHash']
  a[u]['passwordHash'] = b['newPasswordHash'] if b['newPasswordHash'] && b['newPasswordHash'].length > 0
  nu = b['newUsername'].to_s.strip
  if nu.length > 0 && nu != u
    return res.body = '{"success":false,"error":"用户名已存在"}' if a[nu]
    of, nf = File.join(DATA_DIR, "#{u}.json"), File.join(DATA_DIR, "#{nu}.json")
    FileUtils.mv(of, nf) if File.exist?(of)
    a[nu] = a[u]; a[nu]['username'] = nu; a.delete(u)
  end
  wjson(ACCOUNTS_FILE, a)
  res.body = '{"success":true}'
rescue => e
  res.body = "{\"success\":false,\"error\":\"#{e.message}\"}"
end

server.mount_proc '/api/auth/delete' do |req, res|
  res['Content-Type'] = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  next if req.request_method == 'OPTIONS'
  b = JSON.parse(req.body)
  u = b['username'].to_s.strip
  a = rjson(ACCOUNTS_FILE, {})
  return res.body = '{"success":false,"error":"账号不存在"}' unless a[u]
  return res.body = '{"success":false,"error":"密码错误"}' if b['passwordHash'].to_s != a[u]['passwordHash']
  a.delete(u); wjson(ACCOUNTS_FILE, a)
  f = File.join(DATA_DIR, "#{u}.json")
  File.delete(f) if File.exist?(f)
  res.body = '{"success":true}'
rescue => e
  res.body = "{\"success\":false,\"error\":\"#{e.message}\"}"
end

trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }
server.start
