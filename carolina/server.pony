// Stallion HTTP shell.
//
// The connection actor owns a `PqCatalog ref` (libpq handle stays in this
// actor) and delegates routing to `Handler.apply` — the same function PonyTest
// calls.

use stallion = "stallion"
use uri = "uri"
use lori = "lori"
use @pony_asio_event_create[AsioEventID](owner: AsioEventNotify, fd: U32,
  flags: U32, nsec: U64, noisy: Bool)
use @pony_os_accept[I32](event: AsioEventID)

actor Listener is AsioEventNotify
  let _out: OutStream
  let _err: OutStream
  let _config: stallion.ServerConfig
  let _server_auth: lori.TCPServerAuth
  let _dsn: String val
  let _port: String
  var _fd: U32 = 0
  var _bound: Bool = false
  var _event: AsioEventID = AsioEvent.none()

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
    _port = port
    _server_auth = lori.TCPServerAuth(auth)
    _config = stallion.ServerConfig(host, port)
    // Bind before returning so a later register lookup cannot sit in front
    // of the listening socket. Arming is synchronous for the same reason:
    // the constructor runs before RegisterOnce.
    try
      _fd = Listen6.bind(port)?
      _bound = true
      _event = @pony_asio_event_create(this, _fd, AsioEvent.read(), 0, true)
      if _event.is_null() then
        _bound = false
        _err.print("Failed to bind Stallion listener")
      else
        _out.print("carolina-codes-pony listening on [::]:" + port)
      end
    else
      _err.print("Failed to bind Stallion listener")
    end

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    if (not _bound) or (event isnt _event) then
      return
    end
    // `arg` is part of AsioEventNotify. The readiness backend does not use it.
    if AsioEvent.errored(flags) then
      _err.print("listener error " + arg.string())
      return
    end
    if AsioEvent.readable(flags) then
      _accept()
    end

  fun ref _accept() =>
    if not _bound then
      return
    end
    while true do
      let fd = @pony_os_accept(_event)
      if fd <= 0 then
        return
      end
      PolyglotServer(_server_auth, fd.u32(), _config, _dsn)
    end

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
