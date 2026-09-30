// Register once, then listen. Catalog SQL stays inside each connection actor.

use lori = "lori"
use carolina = "carolina"

actor Main
  new create(env: Env) =>
    // Arm the listener before registration. Register's DNS must not run
    // before the process can accept Fly's health checks.
    let host: String val = "::"
    let port = carolina.EnvUtil.port(env.vars)
    let dsn = carolina.EnvUtil.database_url(env.vars)
    let auth = lori.TCPListenAuth(env.root)
    carolina.Listener(auth, host, port, dsn, env.out, env.err)
    carolina.RegisterOnce(env)

  fun @runtime_override_defaults(rto: RuntimeOptions) =>
    rto.ponymaxthreads = carolina.SchedCap.threads()
