# frozen_string_literal: true

# Run: ruby tests/file-to-s3-mcp.test.rb
require "minitest/autorun"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "socket"
require "tmpdir"
require "uri"

SERVER = File.expand_path("../mcp/file-to-s3/server.rb", __dir__)

# A just-enough HTTP/1.1 server standing in for files.chiq.me. WEBrick is not
# in Ruby 3's stdlib, so this reads one request per connection by hand.
class FakeFileToS3
  attr_reader :requests, :url

  def initialize(&responder)
    @responder = responder
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @url = "http://127.0.0.1:#{@server.addr[1]}"
    @thread = Thread.new { loop { serve(@server.accept) } }
  end

  def stop
    @thread.kill
    @server.close
  end

  private

  def serve(socket)
    method, target, = socket.gets.to_s.split(" ")
    headers = {}
    while (line = socket.gets) && line != "\r\n"
      name, value = line.split(":", 2)
      headers[name.downcase] = value.strip
    end
    request = { method: method, path: target, headers: headers, body: socket.read(headers["content-length"].to_i) }
    @requests << request
    status, text = @responder.call(request)
    socket.write("HTTP/1.1 #{status} X\r\nContent-Type: text/plain\r\nContent-Length: #{text.bytesize}\r\nConnection: close\r\n\r\n#{text}")
  ensure
    socket.close
  end
end

class FileToS3McpTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("file-to-s3-mcp-")
    @token_file = File.join(@dir, "config", "file-to-s3", "token")
    @routes = {}
    @fake = FakeFileToS3.new do |request|
      handler = @routes[request[:path].split("?").first]
      handler ? handler.call(request) : [404, "Not found"]
    end
    @url = @fake.url
  end

  def teardown
    @fake.stop
    FileUtils.remove_entry(@dir)
  end

  # --- helpers ---------------------------------------------------------

  def raw(input)
    env = { "FILE_TO_S3_URL" => @url, "FILE_TO_S3_TOKEN_FILE" => @token_file, "HOME" => @dir }
    out, err, status = Open3.capture3(env, RbConfig.ruby, SERVER, stdin_data: input)
    assert status.success?, "server exited #{status.exitstatus}: #{err}"
    out.lines.map { |line| JSON.parse(line) }
  end

  def mcp(*messages)
    raw(messages.map { |message| JSON.generate(message) }.join("\n") + "\n")
  end

  def call_tool(name, arguments = {})
    mcp({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } })
      .last.fetch("result")
  end

  def text(result)
    result.fetch("content").first.fetch("text")
  end

  def logged_in(token = "fts_abc")
    FileUtils.mkdir_p(File.dirname(@token_file))
    File.write(@token_file, "#{token}\n")
  end

  def write_file(name, content)
    path = File.join(@dir, name)
    File.write(path, content)
    path
  end

  # --- protocol ----------------------------------------------------------

  def test_initialize_then_list_tools
    responses = mcp(
      { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "0" } } },
      { jsonrpc: "2.0", method: "notifications/initialized" },
      { jsonrpc: "2.0", id: 2, method: "tools/list" }
    )

    assert_equal [1, 2], responses.map { |response| response["id"] }
    assert_equal "2025-06-18", responses[0]["result"]["protocolVersion"]
    assert_equal "file-to-s3", responses[0]["result"]["serverInfo"]["name"]
    assert_equal({ "tools" => {} }, responses[0]["result"]["capabilities"])
    names = responses[1]["result"]["tools"].map { |tool| tool["name"] }
    assert_equal %w[file_to_s3_login file_to_s3_verify upload_file], names
    upload = responses[1]["result"]["tools"].find { |tool| tool["name"] == "upload_file" }
    assert_equal %w[path name], upload["inputSchema"]["properties"].keys
    assert_equal %w[path], upload["inputSchema"]["required"]
  end

  def test_ping
    assert_equal({}, mcp({ jsonrpc: "2.0", id: 7, method: "ping" }).first["result"])
  end

  def test_unknown_method_is_an_error
    response = mcp({ jsonrpc: "2.0", id: 3, method: "resources/list" }).first

    assert_equal(-32601, response["error"]["code"])
  end

  def test_bad_json_is_reported_and_the_server_keeps_going
    responses = raw("not json\n#{JSON.generate(jsonrpc: "2.0", id: 4, method: "ping")}\n")

    assert_equal(-32700, responses[0]["error"]["code"])
    assert_equal 4, responses[1]["id"]
  end

  # --- login -------------------------------------------------------------

  def test_login_requests_an_otp_labelled_with_the_hostname
    @routes["/auth/otp"] = ->(_) { [202, "OTP sent to Slack #otp"] }
    result = call_tool("file_to_s3_login")

    assert_equal false, result["isError"]
    assert_includes text(result), "Slack #otp"
    assert_includes text(result), "file_to_s3_verify"
    assert_includes @fake.requests.last[:body], URI.encode_www_form(label: Socket.gethostname)
  end

  def test_login_failure_is_a_tool_error
    @routes["/auth/otp"] = ->(_) { [503, "OTP delivery not configured"] }
    result = call_tool("file_to_s3_login")

    assert_equal true, result["isError"]
    assert_includes text(result), "OTP delivery not configured"
  end

  def test_verify_saves_the_token_privately
    @routes["/auth/verify"] = ->(_) { [200, JSON.generate(token: "fts_abc")] }
    result = call_tool("file_to_s3_verify", code: " 123456 ")

    assert_equal false, result["isError"]
    assert_includes @fake.requests.last[:body], "code=123456"
    assert_equal "fts_abc", File.read(@token_file)
    assert_equal 0o600, File.stat(@token_file).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(@token_file)).mode & 0o777
  end

  def test_rejected_code_writes_no_token
    @routes["/auth/verify"] = ->(_) { [401, "Invalid or expired code"] }
    result = call_tool("file_to_s3_verify", code: "000000")

    assert_equal true, result["isError"]
    assert_includes text(result), "Invalid or expired code"
    refute File.exist?(@token_file)
  end

  # --- upload ------------------------------------------------------------

  def test_upload_returns_the_url
    logged_in
    @routes["/upload"] = ->(_) { [200, "https://files.example/files/uuid-a.txt"] }
    result = call_tool("upload_file", path: write_file("a.txt", "hello"))

    assert_equal false, result["isError"]
    assert_equal "https://files.example/files/uuid-a.txt", text(result)
    request = @fake.requests.last
    assert_equal "Bearer fts_abc", request[:headers]["authorization"]
    assert_includes request[:body], %(filename="a.txt")
    assert_includes request[:body], "hello"
  end

  def test_upload_with_a_pinned_name
    logged_in
    @routes["/upload"] = ->(_) { [200, "https://files.example/files/stable.txt"] }
    call_tool("upload_file", path: write_file("a.txt", "hello"), name: "stable.txt")

    assert_equal "/upload?name=stable.txt", @fake.requests.last[:path]
  end

  def test_upload_expands_tilde
    logged_in
    write_file("home.txt", "hi")
    @routes["/upload"] = ->(_) { [200, "https://files.example/files/uuid-home.txt"] }
    result = call_tool("upload_file", path: "~/home.txt")

    assert_equal false, result["isError"], text(result)
  end

  def test_upload_without_a_token_asks_to_log_in
    result = call_tool("upload_file", path: write_file("a.txt", "hello"))

    assert_equal true, result["isError"]
    assert_includes text(result), "file_to_s3_login"
    assert_empty @fake.requests
  end

  def test_upload_with_a_rejected_token_asks_to_log_in
    logged_in
    @routes["/upload"] = ->(_) { [401, "Unauthorized"] }
    result = call_tool("upload_file", path: write_file("a.txt", "hello"))

    assert_equal true, result["isError"]
    assert_includes text(result), "file_to_s3_login"
  end

  def test_upload_missing_file
    logged_in
    result = call_tool("upload_file", path: "nope.txt")

    assert_equal true, result["isError"]
    assert_includes text(result), "Not a readable file"
    assert_includes text(result), "/nope.txt"
  end

  def test_upload_server_error_is_passed_through
    logged_in
    @routes["/upload"] = ->(_) { [422, "mcp.html is reserved"] }
    result = call_tool("upload_file", path: write_file("a.txt", "x"), name: "mcp.html")

    assert_equal true, result["isError"]
    assert_includes text(result), "mcp.html is reserved"
  end

  def test_unreachable_server_is_a_tool_error
    logged_in
    @url = "http://127.0.0.1:1"
    result = call_tool("upload_file", path: write_file("a.txt", "x"))

    assert_equal true, result["isError"]
    assert_includes text(result), "Could not reach"
  end

  def test_unknown_tool_is_a_tool_error
    result = call_tool("delete_everything")

    assert_equal true, result["isError"]
    assert_includes text(result), "Unknown tool"
  end
end
