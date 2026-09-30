// One-shot register with Elixir over HTTP/1.1.
//
// Uses a lori client connection actor. Does not open libpq — the body is
// `Identity` JSON plus `base_url`, all `val`.

use json = "json"
use lori = "lori"

actor Registrar is (lori.TCPConnectionActor & lori.ClientLifecycleEventReceiver)
  var _tcp: lori.TCPConnection = lori.TCPConnection.none()
  let _auth: lori.TCPConnectAuth
  let _spec: DialTarget
  let _err: OutStream
  let _request: String val
  var _buf: String val = ""
  var _logged: Bool = false
  var _started: Bool = false

  new create(
    auth: lori.TCPConnectAuth,
    spec: DialTarget,
    request: String val,
    err: OutStream)
  =>
    _auth = auth
    _spec = spec
    _err = err
    _request = request
    // Dial from a later turn so Main can finish arming the listener first.
    _dial()

  be _dial() =>
    if _started then
      return
    end
    _started = true
    _tcp =
      if _spec.ipv6 then
        lori.TCPConnection.client(
          _auth,
          _spec.host,
          _spec.port,
          "",
          this,
          this
          where ip_version = lori.IP6)
      else
        lori.TCPConnection.client(
          _auth,
          _spec.host,
          _spec.port,
          "",
          this,
          this)
      end

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

primitive RegisterPlan
  """
  No-op when the CMS URL or the bearer token is empty. Otherwise the
  dial target for that URL, IPv6 when the host is Fly 6PN.
  """
  fun apply(url: String val, token: String val): (DialTarget | None) =>
    if (url.size() == 0) or (token.size() == 0) then
      None
    else
      FlyDial.http(url)
    end

primitive RegisterOnce
  fun apply(env: Env) =>
    let url = EnvUtil.carolina_url(env.vars)
    let token = EnvUtil.register_token(env.vars)
    match RegisterPlan(url, token)
    | let spec: DialTarget =>
      let body: String val =
        json.JSONPrinter.print(
          Identity.json_object().update(
            "base_url", EnvUtil.public_base_url(env.vars)))
      let req = _http_post(spec.host, token, body)
      Registrar(lori.TCPConnectAuth(env.root), spec, req, env.err)
    | None =>
      None
    end

  fun _http_post(host: String val, token: String val, body: String val)
    : String val
  =>
    recover val
      String
        .> append("POST /internal/api-endpoints/register HTTP/1.1\r\n")
        .> append("Host: " + host + "\r\n")
        .> append("Authorization: Bearer " + token + "\r\n")
        .> append("Content-Type: application/json\r\n")
        .> append("Content-Length: " + body.size().string() + "\r\n")
        .> append("Connection: close\r\n\r\n")
        .> append(body)
    end

