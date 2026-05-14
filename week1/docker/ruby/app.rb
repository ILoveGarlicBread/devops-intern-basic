require 'webrick'
server = WEBrick::HTTPServer.new(Port: 8080)
server.mount_proc '/' do |req, res|
  res.body = "<h1>Hello world from Ruby server</h1>\n"
end
trap 'INT' do server.shutdown end
server.start
