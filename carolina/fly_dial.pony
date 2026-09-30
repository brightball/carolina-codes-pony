// Fly private DNS is AAAA-only. An IPv4 lookup of these names is NXDOMAIN,
// and musl's getaddrinfo treats that as "name does not exist" for AF_UNSPEC.
// The decision here is pure: no sockets, no libpq, no DNS.

class val DialTarget
  """
  Where a catalog or register connection should dial.
  `ipv6` means the name is a Fly private host and must be reached over IPv6.
  Otherwise the host and port are the ones already in the URL.
  """
  let host: String
  let port: String
  let ipv6: Bool

  new val create(host': String val, port': String val, ipv6': Bool) =>
    host = host'
    port = port'
    ipv6 = ipv6'

primitive FlyDial
  """
  Classify a host, and build the libpq conninfo that dials it.
  """
  fun private_host(host: String val): Bool =>
    _suffix(host, ".internal") or
    _suffix(host, ".flycast") or
    _suffix(host, ".fly.io")

  fun target(host: String val, port: String val): DialTarget =>
    DialTarget(host, port, private_host(host))

  fun pg(url: String val): DialTarget =>
    """
    Host and port libpq will see, from the same conninfo `PqDsn` builds.
    """
    let dsn = PqDsn(url)
    let host =
      match _keyword(dsn, "host")
      | let h: String => h
      else
        ""
      end
    let port =
      match _keyword(dsn, "port")
      | let p: String => p
      else
        "5432"
      end
    target(host, port)

  fun http(url: String val): DialTarget =>
    """
    Host and port of an `http://` or `https://` register URL.
    """
    var rest: String val = url
    if rest.at("http://", 0) then
      rest = AsVal(rest.substring(7))
    elseif rest.at("https://", 0) then
      rest = AsVal(rest.substring(8))
    end
    try
      let slash = _idx(rest, '/')?
      rest = AsVal(rest.substring(0, slash.isize()))
    end
    try
      let at = _idx(rest, '@')?
      rest = AsVal(rest.substring((at + 1).isize()))
    end
    (let host, let port) = _host_port(rest, "80")
    target(host, port)

  fun conninfo(
    base: String val,
    spec: DialTarget,
    hostaddr: (String val | None))
    : (String val | None)
  =>
    """
    Non-Fly conninfo is returned unchanged.
    A Fly host with a resolved IPv6 literal gets `hostaddr` so libpq does
    not look the name up itself. A Fly host with no address is `None`:
    the caller must fail the query, not report an empty row set.
    """
    if not spec.ipv6 then
      return base
    end
    if _keyword(base, "hostaddr") isnt None then
      return base
    end
    match hostaddr
    | let addr: String =>
      if addr.size() == 0 then
        None
      else
        AsVal(base + " hostaddr=" + addr)
      end
    | None =>
      None
    end

  fun _host_port(hp: String val, default_port: String val): (String val, String val) =>
    if hp.size() > 0 then
      try
        if hp(0)? == '[' then
          let endb = _idx(hp, ']')?
          let host: String val = AsVal(hp.substring(1, endb.isize()))
          let after: String val = AsVal(hp.substring((endb + 1).isize()))
          if (after.size() > 0) and (after.at(":", 0)) then
            return (host, AsVal(after.substring(1)))
          else
            return (host, default_port)
          end
        end
      end
    end
    try
      let colon = _idx(hp, ':')?
      (AsVal(hp.substring(0, colon.isize())), AsVal(hp.substring((colon + 1).isize())))
    else
      (hp, default_port)
    end

  fun _keyword(s: String val, key: String val): (String val | None) =>
    let token: String val = key + "="
    var i: USize = 0
    while i < s.size() do
      let boundary = (i == 0) or _ws_at(s, i - 1)
      if boundary and s.at(token, i.isize()) then
        let start = i + token.size()
        var j = start
        while j < s.size() do
          try
            let c = s(j)?
            if (c == ' ') or (c == '\t') or (c == '\n') then
              break
            end
          else
            break
          end
          j = j + 1
        end
        return AsVal(s.substring(start.isize(), j.isize()))
      end
      i = i + 1
    end
    None

  fun _ws_at(s: String val, i: USize): Bool =>
    try
      let c = s(i)?
      (c == ' ') or (c == '\t') or (c == '\n')
    else
      false
    end

  fun _suffix(host: String val, suffix: String val): Bool =>
    if (host.size() == 0) or (host.size() < suffix.size()) then
      return false
    end
    host.at(suffix, (host.size() - suffix.size()).isize())

  fun _idx(s: String val, ch: U8): USize ? =>
    var i: USize = 0
    while i < s.size() do
      if s(i)? == ch then
        return i
      end
      i = i + 1
    end
    error
