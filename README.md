# AI 聊天伴侣 / AI Chat Companion

多语言 AI 聊天伴侣应用，支持 13 种语言，带账号系统和跨设备同步。

## 功能

- 🤖 多 AI 供应商（OpenAI、Anthropic、DeepSeek、本地、自定义）
- 🎭 20 种人格 + 14 种性别 + 11 种关系 + 11 种风格 + 7 种观点
- 🌐 13 种语言界面（中文、English、日本語、한국어、Español、Français、Deutsch、Português、Русский、العربية、ไทย、Tiếng Việt、Italiano）
- 🔐 账号系统（注册/登录/修改密码/注销，10 次错误封禁 7 天）
- 💬 流式 AI 回复 + 语音输入 + 记忆系统
- 🌓 深色/浅色模式
- 📱 响应式设计

## 快速使用

### 本地运行
双击 `ai-chat-companion.command`，或终端运行：
```bash
ruby -rwebrick -e 'WEBrick::HTTPServer.new(:Port=>8080,:DocumentRoot=>".").start'
```
然后打开 http://localhost:8080/ai-chat-companion.html

### 带后端（跨设备同步）
```bash
ruby server.rb
```
后端 API 提供账号注册/登录/数据同步功能。

## 文件结构

- `ai-chat-companion.html` — 前端单文件应用
- `server.rb` — Ruby 后端 API 服务器
- `ai-chat-companion.command` — Mac 启动脚本
- `data/` — 用户数据存储目录
