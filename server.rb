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
  Port: PORT,
  DocumentRoot: ROOT,
  BindAddress: '0.0.0.0',
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN),
  AccessLog: []
)

server.mount_proc '/api/auth/register' do |req, res|
  res['Content-Type'] = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  next if req.request_method == 'OPTIONS'
  body = JSON.parse(req.body)
  u = body['username'].to_s.strip
  h = body['passwordHash'].to_s.strip
  return res.body = '{"success":false,"error":"invalid"}' if u.empty?
  accts = rjson(ACCOUNTS_FILE, {})
  return res.body = '{"success":false,"error":"用户名已存在"}' if accts[u]
  accts[u] = { username: u, passwordHash: h, createdAt: Time.now.to_i, lastLogin: Time.now.to_i, failedAttempts: 0, lockedUntil: nil }
  wjson(ACCOUNTS_FILE, accts)
  wjson(File.join(DATA_DIR, "#{u}.json"), { sessions: [], settings: {}, messages: {}, memory: {}, custom_pers: [] })
  res.body = '{"success":true}'
rescue => e
  res.body = "{\"success\":false,\"error\":\"#{e.message}\"}"
end

server.mount_proc '/api/auth/login' do |req, res|
  res['Content-Type'] = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  next if req.request_method == 'OPTIONS'
  body = JSON.parse(req.body)
  u = body['username'].to_s.strip
  h = body['passwordHash'].to_s.strip
  accts = rjson(ACCOUNTS_FILE, {})
  return res.body = '{"success":false,"error":"账号不存在"}' unless accts[u]
  a = accts[u]
  if a['lockedUntil'] && Time.now.to_i < a['lockedUntil']
    d = ((a['lockedUntil'] - Time.now.to_i) / 86400.0).ceil
    return res.body = "{\"success\":false,\"error\":\"封禁中，#{d}天后解封\"}"
  end
  if h != a['passwordHash']
    a['failedAttempts'] = (a['failedAttempts'] || 0) + 1
    if a['failedAttempts'] >= 10
      a['lockedUntil'] = Time.now.to_i + 604800
      a['failedAttempts'] = 0
      wjson(ACCOUNTS_FILE, accts)
      return res.body = '{"success":false,"error":"密码错误10次，封禁7天"}'
    end
    wjson(ACCOUNTS_FILE, accts)
    return res.body = "{\"success\":false,\"error\":\"密码错误（剩余#{10 - a['failedAttempts']}次）\"}"
  end
  a['failedAttempts'] = 0
  a['lockedUntil'] = nil
  a['lastLogin'] = Time.now.to_i
  wjson(ACCOUNTS_FILE, accts)
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
    body = JSON.parse(req.body)
    wjson(File.join(DATA_DIR, "#{u}.json"), body['data'] || body)
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
  body = JSON.parse(req.body)
  u = body['username'].to_s.strip
  accts = rjson(ACCOUNTS_FILE, {})
  return res.body = '{"success":false,"error":"账号不存在"}' unless accts[u]
  return res.body = '{"success":false,"error":"密码错误"}' if body['oldPasswordHash'].to_s != accts[u]['passwordHash']
  if body['newPasswordHash'] && body['newPasswordHash'].length > 0
    accts[u]['passwordHash'] = body['newPasswordHash']
  end
  nu = body['newUsername'].to_s.strip
  if nu.length > 0 && nu != u
    return res.body = '{"success":false,"error":"用户名已存在"}' if accts[nu]
    of = File.join(DATA_DIR, "#{u}.json")
    nf = File.join(DATA_DIR, "#{nu}.json")
    FileUtils.mv(of, nf) if File.exist?(of)
    accts[nu] = accts[u]
    accts[nu]['username'] = nu
    accts.delete(u)
  end
  wjson(ACCOUNTS_FILE, accts)
  res.body = '{"success":true}'
rescue => e
  res.body = "{\"success\":false,\"error\":\"#{e.message}\"}"
end

server.mount_proc '/api/auth/delete' do |req, res|
  res['Content-Type'] = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  next if req.request_method == 'OPTIONS'
  body = JSON.parse(req.body)
  u = body['username'].to_s.strip
  accts = rjson(ACCOUNTS_FILE, {})
  return res.body = '{"success":false,"error":"账号不存在"}' unless accts[u]
  return res.body = '{"success":false,"error":"密码错误"}' if body['passwordHash'].to_s != accts[u]['passwordHash']
  accts.delete(u)
  wjson(ACCOUNTS_FILE, accts)
  f = File.join(DATA_DIR, "#{u}.json")
  File.delete(f) if File.exist?(f)
  res.body = '{"success":true}'
rescue => e
  res.body = "{\"success\":false,\"error\":\"#{e.message}\"}"
end

puts "Ready on port #{PORT}"
trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }
server.start
