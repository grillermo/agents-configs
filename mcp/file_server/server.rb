#!/usr/bin/env ruby
# frozen_string_literal: true

# Local stdio MCP server that uploads files to file_server (files.chiq.me).
# Ruby stdlib only, so it runs on any machine with Ruby 3 — including over SSH.
# Login: the server posts a one-time code to Slack #otp, the user reads it to
# Claude, and the code is exchanged for a token that never expires.

require "fileutils"
require "json"
require "net/http"
require "openssl"
require "socket"
require "uri"

module FileToS3Mcp
  PROTOCOL_VERSION = "2025-06-18"
  NOT_LOGGED_IN = "Not logged in to file_server. Call file_server_login, ask the user for the " \
                  "6-digit code posted to Slack #otp, then call file_server_verify with it."

  TOOLS = [
    {
      name: "file_server_login",
      description: "Start logging in to file_server: posts a 6-digit one-time code to the user's " \
                   "Slack #otp channel. Then ask the user for the code and call file_server_verify.",
      inputSchema: { type: "object", properties: {} }
    },
    {
      name: "file_server_verify",
      description: "Finish logging in to file_server with the 6-digit code the user read from " \
                   "Slack #otp. Saves a token on this machine that never expires.",
      inputSchema: {
        type: "object",
        properties: { code: { type: "string", description: "The 6-digit code from Slack #otp" } },
        required: ["code"]
      }
    },
    {
      name: "upload_file",
      description: "Upload a local file (max 25 MB) to file_server and return its public URL. " \
                   "Without name the URL is unique (UUID-prefixed). With name the file is stored " \
                   "as exactly that name, overwriting the previous upload, so the URL is stable: " \
                   "https://files.chiq.me/files/<name>.",
      inputSchema: {
        type: "object",
        properties: {
          path: { type: "string", description: "Absolute or ~/ path to the local file" },
          name: { type: "string", description: "Optional stable filename (e.g. app-manifest.plist). " \
                                                "Re-uploading with the same name replaces the file " \
                                                "and keeps the same URL." }
        },
        required: ["path"]
      }
    }
  ].freeze

  class ToolError < StandardError; end

  # Talks HTTP to the file_server app and owns the saved token.
  class Client
    def initialize(base_url:, token_file:)
      @base_url = base_url.chomp("/")
      @token_file = token_file
    end

    def request_otp
      response = post("/auth/otp", form: { "label" => Socket.gethostname })
      raise ToolError, "file_server refused the login (#{response.code}): #{response.body}" unless response.code == "202"

      "A 6-digit code was posted to Slack #otp. Ask the user for it, then call file_server_verify with the code."
    end

    def verify(code)
      response = post("/auth/verify", form: { "code" => code.to_s.strip, "label" => Socket.gethostname })
      unless response.code == "200"
        raise ToolError, "Code rejected (#{response.code}): #{response.body}. " \
                         "If it expired, call file_server_login for a new one."
      end

      token =
        begin
          JSON.parse(response.body).fetch("token")
        rescue JSON::ParserError, KeyError => e
          raise ToolError, "Unexpected response from #{@base_url}: #{e.class}: #{e.message}"
        end
      save_token(token)
      "Logged in to file_server as #{Socket.gethostname}. The token never expires."
    end

    def upload(path, name = nil)
      token = read_token or raise ToolError, NOT_LOGGED_IN
      full_path = File.expand_path(path.to_s)
      raise ToolError, "Not a readable file: #{full_path}" unless File.file?(full_path) && File.readable?(full_path)

      query = name.to_s.strip.empty? ? "" : "?#{URI.encode_www_form(name: name.strip)}"
      response = File.open(full_path, "rb") do |file|
        post("/upload#{query}", multipart: [["file", file, { filename: File.basename(full_path) }]], token: token)
      end

      case response.code
      when "200" then response.body.strip
      when "401" then raise ToolError, NOT_LOGGED_IN
      else raise ToolError, "Upload failed (#{response.code}): #{response.body}"
      end
    end

    private

    def post(path, form: nil, multipart: nil, token: nil)
      uri = URI("#{@base_url}#{path}")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token}" if token
      multipart ? request.set_form(multipart, "multipart/form-data") : request.set_form_data(form)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 300) do |http|
        http.request(request)
      end
    rescue SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise ToolError, "Could not reach #{@base_url}: #{e.message}"
    rescue Net::ProtocolError => e
      raise ToolError, "Unexpected response from #{@base_url}: #{e.class}: #{e.message}"
    end

    def read_token
      return nil unless File.exist?(@token_file)

      token = File.read(@token_file).strip
      token.empty? ? nil : token
    end

    def save_token(token)
      FileUtils.mkdir_p(File.dirname(@token_file), mode: 0o700)
      File.write(@token_file, token, perm: 0o600)
      File.chmod(0o600, @token_file) # perm: only applies when the file is created
    end
  end

  # Newline-delimited JSON-RPC 2.0 over stdio. Only stdout carries protocol
  # messages; anything diagnostic goes to stderr.
  class Server
    def initialize(client, input: $stdin, output: $stdout)
      @client = client
      @input = input
      @output = output
    end

    def run
      @output.sync = true
      @input.each_line do |line|
        next if line.strip.empty?

        response = handle_line(line)
        @output.puts(JSON.generate(response)) if response
      end
    end

    private

    def handle_line(line)
      begin
        message = JSON.parse(line)
      rescue JSON::ParserError
        return error(nil, -32700, "Parse error")
      end

      id = message["id"] if message.is_a?(Hash)
      handle(message)
    rescue StandardError => e
      warn "[file_server] #{e.class}: #{e.message}"
      error(id, -32603, e.message)
    end

    def handle(message)
      return nil unless message.key?("id") # notifications get no reply

      id = message["id"]
      result =
        case message["method"]
        when "initialize" then initialize_result(message["params"] || {})
        when "ping" then {}
        when "tools/list" then { tools: TOOLS }
        when "tools/call" then call_tool(message.dig("params", "name"), message.dig("params", "arguments") || {})
        else return error(id, -32601, "Method not found: #{message["method"]}")
        end
      { jsonrpc: "2.0", id: id, result: result }
    end

    def initialize_result(params)
      {
        protocolVersion: params["protocolVersion"] || PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: "file_server", version: "1.0.0" }
      }
    end

    def call_tool(name, arguments)
      text =
        case name
        when "file_server_login" then @client.request_otp
        when "file_server_verify" then @client.verify(arguments["code"])
        when "upload_file" then @client.upload(arguments["path"], arguments["name"])
        else raise ToolError, "Unknown tool: #{name}"
        end
      { content: [{ type: "text", text: text }], isError: false }
    rescue ToolError => e
      { content: [{ type: "text", text: e.message }], isError: true }
    end

    def error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  client = FileToS3Mcp::Client.new(
    base_url: ENV.fetch("FILE_SERVER_URL", "https://files.chiq.me"),
    token_file: ENV.fetch("FILE_SERVER_TOKEN_FILE") { File.expand_path("~/.config/file_server/token") }
  )
  FileToS3Mcp::Server.new(client).run
end
