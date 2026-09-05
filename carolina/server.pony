// Stallion HTTP shell.
//
// The connection actor owns a `PqCatalog ref` (libpq handle stays in this
// actor) and delegates routing to `Handler.apply` — the same function PonyTest
// calls.

use stallion = "stallion"
use uri = "uri"
use lori = "lori"

actor Listener is lori.TCPListenerActor
  var _tcp_listener: lori.TCPListener = lori.TCPListener.none()
  let _out: OutStream
  let _err: OutStream
  let _config: stallion.ServerConfig
  let _server_auth: lori.TCPServerAuth
  let _dsn: String val

  new create(
    auth: lori.TCPListenAuth,
    host: String,
    port: String,
    dsn: String val,
    out: OutStream,
    err: OutStream)
  =>
    _out = out
    _err = err
    _dsn = dsn
    _server_auth = lori.TCPServerAuth(auth)
    _config = stallion.ServerConfig(host, port)
    _tcp_listener = lori.TCPListener(auth, host, port, this)

  fun ref _listener(): lori.TCPListener =>
    _tcp_listener

  fun ref _on_accept(fd: U32): lori.TCPConnectionActor =>
    PolyglotServer(_server_auth, fd, _config, _dsn)

  fun ref _on_listening() =>
    try
      (let host, let port) = _tcp_listener.local_address().name()?
      _out.print("carolina-codes-pony listening on " + host + ":" + port)
    else
      _out.print("carolina-codes-pony listening")
    end

  fun ref _on_listen_failure() =>
    _err.print("Failed to bind Stallion listener")

actor PolyglotServer is stallion.HTTPServerActor
  var _http: stallion.HTTPServer = stallion.HTTPServer.none()
  let _catalog: PqCatalog

  new create(
    auth: lori.TCPServerAuth,
    fd: U32,
    config: stallion.ServerConfig,
    dsn: String val)
  =>
    _catalog = PqCatalog(dsn)
    _http = stallion.HTTPServer(auth, fd, this, config)

  fun ref _http_connection(): stallion.HTTPServer =>
    _http

  fun ref on_request_complete(
    request': stallion.Request val,
    responder: stallion.Responder)
  =>
    var year_q: (String val | None) = None
    match request'.uri.query_params()
    | let params: uri.FormURLEncoded val =>
      match params.get("year")
      | let y: String => year_q = y
      end
    end
    (let status, let body) = Handler(request'.uri.path, year_q, _catalog)
    let stallion_status: stallion.Status =
      if status == 200 then
        stallion.StatusOK
      elseif status == 404 then
        stallion.StatusNotFound
      else
        stallion.StatusInternalServerError
      end
    let response = stallion.ResponseBuilder(stallion_status)
      .add_header("Content-Type", "application/json; charset=utf-8")
      .add_header("Content-Length", body.size().string())
      .add_header("X-Polyglot-Language", Identity.language())
      .add_header("X-Polyglot-Framework", Identity.framework())
      .finish_headers()
      .add_chunk(body)
      .build()
    responder.respond(response)
