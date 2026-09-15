// libpq FFI Catalog.
//
// Each HTTP connection actor constructs its own `PqCatalog` so the `PGconn`
// pointer never leaves that actor (`ref` is not sendable). Tests do not need
// this type; they use `FakeCatalog`.

use "lib:pq"

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

primitive _Pq
  fun connection_ok(): I32 => 0
  fun tuples_ok(): I32 => 2

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

class PqCatalog is Catalog
  let _dsn: String val
  var _conn: Pointer[_PGconn] = Pointer[_PGconn]
  var _sql_count: USize = 0
  var _connect_count: USize = 0
  var _ok: Bool = false

  new create(database_url: String val) =>
    _dsn = PqDsn(database_url)

  fun sql_count(): USize =>
    _sql_count

  fun connect_count(): USize =>
    _connect_count

  fun ref query(sql: String val, args: Array[String val] val): Array[Row val] val =>
    _sql_count = _sql_count + 1
    if not _ensure() then
      return recover val Array[Row val] end
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
    if res.is_null() then
      return recover val Array[Row val] end
    end
    if @PQresultStatus(res) != _Pq.tuples_ok() then
      @PQclear(res)
      return recover val Array[Row val] end
    end
    let rows = PqRead.rows(res)
    @PQclear(res)
    rows

  fun ref _ensure(): Bool =>
    if _ok then
      return true
    end
    _connect_count = _connect_count + 1
    _conn = @PQconnectdb(_dsn.cstring())
    if _conn.is_null() then
      return false
    end
    if @PQstatus(_conn) != _Pq.connection_ok() then
      @PQfinish(_conn)
      _conn = Pointer[_PGconn]
      return false
    end
    _ok = true
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
      return url + (if _contains(url, "sslmode=") then "" else " sslmode=disable" end)
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
      " password=" + pass + " sslmode=disable"

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
