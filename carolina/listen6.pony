// Dual-stack listen for Fly's proxy.
//
// Lori's listen path calls getaddrinfo and never clears IPV6_V6ONLY, so on a
// host whose sysctl defaults to v6-only the socket rejects IPv4-mapped
// clients, and a musl getaddrinfo of "::" can fail to bind at all. Bind the
// IPv6 unspecified address directly and turn IPV6_V6ONLY off before bind.
// Constants are the Linux ABI (the Fly image and this workstation).

use @socket[I32](domain: I32, typ: I32, protocol: I32)
use @setsockopt[I32](fd: I32, level: I32, opt: I32, optval: Pointer[I32] tag, len: U32)
use @bind[I32](fd: I32, addr: Pointer[U8] tag, len: U32)
use @listen[I32](fd: I32, backlog: I32)
use @close[I32](fd: I32)
use @fcntl[I32](fd: I32, cmd: I32, arg: I32)
use @htons[U16](hostshort: U16)

primitive _Sock
  fun af_inet6(): I32 => 10
  fun sock_stream(): I32 => 1
  fun ipproto_tcp(): I32 => 6
  fun ipproto_ipv6(): I32 => 41
  fun ipv6_v6only(): I32 => 26
  fun sol_socket(): I32 => 1
  fun so_reuseaddr(): I32 => 2
  fun f_getfl(): I32 => 3
  fun f_setfl(): I32 => 4
  fun f_setfd(): I32 => 2
  fun fd_cloexec(): I32 => 1
  fun o_nonblock(): I32 => 2048

primitive Listen6
  """
  Listening socket bound to the IPv6 unspecified address, with
  IPV6_V6ONLY cleared so IPv4-mapped clients are accepted.
  """
  fun bind(port: String): U32 ? =>
    let port_num = port.u16()?
    let fd =
      @socket(_Sock.af_inet6(), _Sock.sock_stream(), _Sock.ipproto_tcp())
    if fd < 0 then
      error
    end
    var reuse: I32 = 1
    var v6only: I32 = 0
    let flags = @fcntl(fd, _Sock.f_getfl(), I32(0))
    if
      (@fcntl(fd, _Sock.f_setfd(), _Sock.fd_cloexec()) != 0) or
      (@fcntl(fd, _Sock.f_setfl(), flags or _Sock.o_nonblock()) != 0) or
      (@setsockopt(
        fd,
        _Sock.sol_socket(),
        _Sock.so_reuseaddr(),
        addressof reuse,
        U32(4)) != 0) or
      (@setsockopt(
        fd,
        _Sock.ipproto_ipv6(),
        _Sock.ipv6_v6only(),
        addressof v6only,
        U32(4)) != 0)
    then
      @close(fd)
      error
    end
    // sockaddr_in6, little-endian. A Pony struct's addressof is not the
    // field bytes, so the address is packed explicitly.
    let port_be = @htons(port_num)
    let addr = Array[U8]
    addr.push(10)
    addr.push(0)
    addr.push((port_be and 0xff).u8())
    addr.push((port_be >> 8).u8())
    var i: USize = 0
    while i < 24 do
      addr.push(0)
      i = i + 1
    end
    if
      (@bind(fd, addr.cpointer(), U32(28)) != 0) or
      (@listen(fd, I32(128)) != 0)
    then
      @close(fd)
      error
    end
    fd.u32()

