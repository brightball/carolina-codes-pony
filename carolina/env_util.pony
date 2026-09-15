// Read process environment from `Env.vars` (`KEY=value` strings).
//
// `Env.vars` is `Array[String val] val` — globally immutable, safe to share
// with any actor as `val`.

primitive AsVal
  """
  Consume an ephemeral `String iso^` (substring, `+`, `.string()`) into `val`.
  """
  fun apply(s: String iso): String val =>
    consume s

primitive EnvUtil
  fun apply(vars: Array[String val] val, key: String val, default': String val)
    : String val
  =>
    let prefix: String val = key + "="
    for v in vars.values() do
      if v.at(prefix, 0) then
        return v.substring(prefix.size().isize())
      end
    end
    default'

  fun port(vars: Array[String val] val): String val =>
    apply(vars, "PORT", "4023")

  fun database_url(vars: Array[String val] val): String val =>
    apply(
      vars,
      "DATABASE_URL",
      "postgres://postgres:postgres@127.0.0.1:5432/carolina_dev")

  fun carolina_url(vars: Array[String val] val): String val =>
    apply(vars, "CAROLINA_URL", "")

  fun register_token(vars: Array[String val] val): String val =>
    apply(vars, "POLYGLOT_REGISTER_TOKEN", "")

  fun public_base_url(vars: Array[String val] val): String val =>
    let port' = port(vars)
    apply(vars, "PUBLIC_BASE_URL", "http://127.0.0.1:" + port')
