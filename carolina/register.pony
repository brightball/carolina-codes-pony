// One-shot register with Elixir over HTTP/1.1.
//
// Uses a lori client connection actor. Does not open libpq — the body is
// `Identity` JSON plus `base_url`, all `val`.

use json = "json"
use lori = "lori"

actor Registrar is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp: lori.TCPConnection = lori.TCPConnection.none()
  let _err: OutStream
  let _request: String val
  var _buf: String val = ""
  var _logged: Bool = false

  new create(
    auth: lori.TCPConnectAuth,
    host: String val,
    port: String val,
    request: String val,
    err: OutStream)
  =>
    _err = err
    _request = request
    _tcp = lori.TCPConnection.client(auth, host, port, "", this, this)

  fun ref _connection(): lori.TCPConnection =>
    _tcp

  fun ref _on_connection_failure(reason: lori.ConnectionFailureReason) =>
    _err.print("register: failed to connect")

  fun ref _on_connected() =>
    _tcp.send(_request)

  fun ref _on_received(data: Array[U8] iso): lori.ReadAction =>
    _buf = _buf + String.from_array(consume data)
    if (not _logged) and (_buf.size() > 12) then
      _logged = true
      let line = _first_line(_buf)
      _err.print("registered with elixir: " + line)
      _tcp.close()
    end
    lori.KeepReading

  fun _first_line(s: String val): String val =>
    var i: USize = 0
    while i < s.size() do
      try
        if (s(i)? == '\n') or (s(i)? == '\r') then
          return s.substring(0, i.isize())
        end
      end
      i = i + 1
    end
    s

primitive RegisterOnce
  fun apply(env: Env) =>
    let url = EnvUtil.carolina_url(env.vars)
    let token = EnvUtil.register_token(env.vars)
    if (url.size() == 0) or (token.size() == 0) then
      return
    end
    (let host, let port) = _host_port(url)
    let body: String val = json.JSONPrinter.print(
      Identity.json_object().update("base_url", EnvUtil.public_base_url(env.vars)))
    let req = _http_post(host, token, body)
    Registrar(lori.TCPConnectAuth(env.root), host, port, req, env.err)

  fun _http_post(host: String val, token: String val, body: String val)
    : String val
  =>
    recover val
      let s = String
      s.append("POST /internal/api-endpoints/register HTTP/1.1\r\n")
      s.append("Host: " + host + "\r\n")
      s.append("Authorization: Bearer " + token + "\r\n")
      s.append("Content-Type: application/json\r\n")
      s.append("Content-Length: " + body.size().string() + "\r\n")
      s.append("Connection: close\r\n\r\n")
      s.append(body)
      s
    end

  fun _host_port(url: String val): (String val, String val) =>
    var rest: String val = url
    if rest.at("http://", 0) then
      rest = rest.substring(7)
    elseif rest.at("https://", 0) then
      rest = rest.substring(8)
    end
    try
      let slash = _idx(rest, '/')?
      rest = rest.substring(0, slash.isize())
    end
    try
      let colon = _idx(rest, ':')?
      (rest.substring(0, colon.isize()), rest.substring((colon + 1).isize()))
    else
      (rest, "80")
    end

  fun _idx(s: String val, ch: U8): USize ? =>
    var i: USize = 0
    while i < s.size() do
      if s(i)? == ch then
        return i
      end
      i = i + 1
    end
    error
