// libpq FFI Catalog.
//
// Each HTTP connection actor constructs its own `PqCatalog` so the `PGconn`
// pointer never leaves that actor (`ref` is not sendable). Tests do not need
// this type; they use `FakeCatalog`.

use "lib:pq"
use net = "net"
use @pony_os_addrinfo[Pointer[U8]](family: U32, host: Pointer[U8] tag,
  service: Pointer[U8] tag)
use @pony_os_getaddr[None](addr: Pointer[None] tag, ipaddr: net.NetAddress tag)
use @freeaddrinfo[None](addr: Pointer[None] tag)

use @PQconnectdb[Pointer[_PGconn]](conninfo: Pointer[U8] tag)
use @PQstatus[I32](conn: Pointer[_PGconn] tag)
use @PQfinish[None](conn: Pointer[_PGconn] tag)
use @PQerrorMessage[Pointer[U8]](conn: Pointer[_PGconn] tag)
// pony-lint: off style/member-naming
use @PQexecParams[Pointer[_PGresult]](
  conn: Pointer[_PGconn] tag,
  command: Pointer[U8] tag,
  nParams: I32,
  paramTypes: Pointer[U32] tag,
  paramValues: Pointer[Pointer[U8] tag] tag,
  paramLengths: Pointer[I32] tag,
  paramFormats: Pointer[I32] tag,
  resultFormat: I32)
// pony-lint: on style/member-naming
use @PQresultStatus[I32](res: Pointer[_PGresult] tag)
use @PQclear[None](res: Pointer[_PGresult] tag)
use @PQntuples[I32](res: Pointer[_PGresult] tag)
use @PQnfields[I32](res: Pointer[_PGresult] tag)
use @PQfname[Pointer[U8] box](res: Pointer[_PGresult] tag, field_num: I32)
use @PQgetvalue[Pointer[U8] box](res: Pointer[_PGresult] tag, tup: I32, field: I32)
use @PQgetisnull[I32](res: Pointer[_PGresult] tag, tup: I32, field: I32)

struct _PGconn
struct _PGresult

primitive PqCodes
  """
  libpq ConnStatusType and ExecStatusType values this process branches on.
  """
  fun connection_ok(): I32 => 0
  fun connection_bad(): I32 => 1
  fun tuples_ok(): I32 => 2
  fun bad_response(): I32 => 5
  fun fatal_error(): I32 => 7

primitive PqRows
  """Successful PGRES_TUPLES_OK row set. Zero tuples is still success."""

primitive PqFailed
  """
  The statement failed and the result is not an empty row set.
  The connection itself can still be reused.
  """

primitive PqDrop
  """
  The connection is not usable. Finish it. Do not report an empty row set.
  The next query opens a new connection.
  """

type PqExecOutcome is (PqRows | PqFailed | PqDrop)

primitive PqDecision
  """
  Reuse-or-finish decision `PqCatalog.query` calls. No libpq handle.
  """
  fun keep_connection(conn_status: I32): Bool =>
    conn_status == PqCodes.connection_ok()

  fun after_exec(
    result_null: Bool,
    result_status: I32,
    conn_status: I32,
    ntuples: I32)
    : PqExecOutcome
  =>
    """
    `ntuples` is only meaningful for PGRES_TUPLES_OK. Zero is an empty
    success. A null result, or any status while the connection is not
    CONNECTION_OK, drops the connection instead of looking like zero rows.
    """
    if result_null or not keep_connection(conn_status) then
      PqDrop
    elseif (result_status == PqCodes.tuples_ok()) and (ntuples >= 0) then
      PqRows
    else
      PqFailed
    end

primitive PqStr
  fun apply(ptr: Pointer[U8] box): String val =>
    if ptr.is_null() then
      ""
    else
      String.copy_cstring(ptr).clone()
    end

primitive PqRead
  """
  Extract rows from a PGresult. Primitive so we do not capture a Catalog `ref`.
  """
  fun rows(res: Pointer[_PGresult] tag): Array[Row val] val =>
    let out = recover iso Array[Row val] end
    let nt = @PQntuples(res)
    let nf = @PQnfields(res)
    var r: I32 = 0
    while r < nt do
      let pairs = recover iso Array[(String val, String val)] end
      var f: I32 = 0
      while f < nf do
        let name = PqStr(@PQfname(res, f))
        var value: String val = ""
        if @PQgetisnull(res, r, f) == 0 then
          value = PqStr(@PQgetvalue(res, r, f))
        end
        pairs.push((name, value))
        f = f + 1
      end
      out.push(Row(consume pairs))
      r = r + 1
    end
    consume out

primitive Ipv6Literal
  """
  Numeric IPv6 address for `host`, looked up with AF_INET6 only.
  An empty result is an error. This is not used on the `/health` path.
  """
  fun apply(host: String, service: String): String val ? =>
    let result = @pony_os_addrinfo(U32(2), host.cstring(), service.cstring())
    if result.is_null() then
      error
    end
    let ip = recover net.NetAddress end
    @pony_os_getaddr(result, ip)
    @freeaddrinfo(result)
    if not ip.ip6() then
      error
    end
    (let name, let _) = ip.name()?
    if name.size() == 0 then
      error
    end
    name

class PqCatalog is Catalog
  let _url: String val
  var _conn: Pointer[_PGconn] = Pointer[_PGconn]
  var _sql_count: USize = 0
  var _connect_count: USize = 0
  var _open: Bool = false

  new create(database_url: String val) =>
    _url = database_url

  fun sql_count(): USize =>
    _sql_count

  fun connect_count(): USize =>
    _connect_count

  fun ref query(sql: String val, args: Array[String val] val): Array[Row val] val ? =>
    _sql_count = _sql_count + 1
    if not _prepare() then
      error
    end
    let n = args.size().i32()
    let values = Array[Pointer[U8] tag](args.size())
    for a in args.values() do
      values.push(a.cstring())
    end
    let res =
      if n == 0 then
        @PQexecParams(
          _conn,
          sql.cstring(),
          0,
          Pointer[U32],
          Pointer[Pointer[U8] tag],
          Pointer[I32],
          Pointer[I32],
          0)
      else
        @PQexecParams(
          _conn,
          sql.cstring(),
          n,
          Pointer[U32],
          values.cpointer(),
          Pointer[I32],
          Pointer[I32],
          0)
      end
    let result_null = res.is_null()
    let result_status: I32 =
      if result_null then I32(-1) else @PQresultStatus(res) end
    let ntuples: I32 =
      if result_null then I32(-1) else @PQntuples(res) end
    let outcome =
      PqDecision.after_exec(
        result_null,
        result_status,
        @PQstatus(_conn),
        ntuples)
    if outcome is PqRows then
      let rows = PqRead.rows(res)
      @PQclear(res)
      rows
    elseif outcome is PqDrop then
      if not result_null then @PQclear(res) end
      _finish()
      error
    else
      if not result_null then @PQclear(res) end
      error
    end

  fun ref _prepare(): Bool =>
    if _open and not PqDecision.keep_connection(@PQstatus(_conn)) then
      _finish()
    end
    if _open then
      true
    else
      _connect()
    end

  fun ref _finish() =>
    if not _open then
      return
    end
    @PQfinish(_conn)
    _conn = Pointer[_PGconn]
    _open = false

  fun ref _connect(): Bool =>
    _connect_count = _connect_count + 1
    let spec = FlyDial.pg(_url)
    let base = PqDsn(_url)
    let hostaddr: (String val | None) =
      if spec.ipv6 then
        try
          Ipv6Literal(spec.host, spec.port)?
        else
          None
        end
      else
        None
      end
    let info =
      match FlyDial.conninfo(base, spec, hostaddr)
      | let s: String => s
      | None => return false
      end
    _conn = @PQconnectdb(info.cstring())
    if _conn.is_null() then
      _open = false
      return false
    end
    if not PqDecision.keep_connection(@PQstatus(_conn)) then
      @PQfinish(_conn)
      _conn = Pointer[_PGconn]
      _open = false
      return false
    end
    _open = true
    true

primitive PqDsn
  fun apply(url: String val): String val =>
    """
    Translate postgres://user:pass@host:port/db into libpq conninfo.
    """
    var rest: String val = url
    if rest.at("postgres://", 0) then
      rest = rest.substring(11)
    elseif rest.at("postgresql://", 0) then
      rest = rest.substring(13)
    else
      return url + _libpq_tail(url)
    end
    var user: String val = "postgres"
    var pass: String val = "postgres"
    var host: String val = "127.0.0.1"
    var port: String val = "5432"
    var db: String val = "carolina_dev"
    try
      let at = _index_of(rest, '@')?
      let creds: String val = rest.substring(0, at.isize())
      rest = rest.substring((at + 1).isize())
      try
        let colon = _index_of(creds, ':')?
        user = creds.substring(0, colon.isize())
        pass = creds.substring((colon + 1).isize())
      else
        user = creds
      end
    end
    try
      let slash = _index_of(rest, '/')?
      let hp: String val = rest.substring(0, slash.isize())
      db = rest.substring((slash + 1).isize())
      try
        let q = _index_of(db, '?')?
        db = db.substring(0, q.isize())
      end
      try
        let colon = _index_of(hp, ':')?
        host = hp.substring(0, colon.isize())
        port = hp.substring((colon + 1).isize())
      else
        host = hp
      end
    end
    "host=" + host + " port=" + port + " dbname=" + db + " user=" + user +
      " password=" + pass + " sslmode=disable connect_timeout=2"

  fun _libpq_tail(url: String val): String val =>
    let ssl = _contains(url, "sslmode=")
    let timeout = _contains(url, "connect_timeout=")
    if (not ssl) and (not timeout) then
      " sslmode=disable connect_timeout=2"
    elseif (not ssl) and timeout then
      " sslmode=disable"
    elseif ssl and (not timeout) then
      " connect_timeout=2"
    else
      ""
    end

  fun _index_of(s: String val, ch: U8): USize ? =>
    var i: USize = 0
    while i < s.size() do
      if s(i)? == ch then
        return i
      end
      i = i + 1
    end
    error

  fun _contains(hay: String val, needle: String val): Bool =>
    if needle.size() > hay.size() then
      return false
    end
    var i: USize = 0
    let max = (hay.size() - needle.size()) + 1
    while i < max do
      if hay.at(needle, i.isize()) then
        return true
      end
      i = i + 1
    end
    false
