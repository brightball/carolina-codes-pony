// Identity for the Pony + Stallion polyglot sibling.
//
// All values are `val` so they can be sent between actors (Main → Registrar,
// connection actors, tests) without aliasing mutable state.

use json = "json"

primitive Identity
  fun language(): String val => "Pony"

  fun framework(): String val => "Stallion"

  fun api_version(): String val => "0.2.0"

  fun schema_version(): I64 => 1

  fun created_year(): I64 => 2026

  fun language_version(): String val =>
    // ponyc --version is 0.70.1 on the machine that built this sibling.
    "0.70.1"

  fun endpoints(): json.JSONArray val =>
    json.JSONArray
      .push(_ep("/", recover val Array[String val] end))
      .push(_ep("/health", recover val Array[String val] end))
      .push(_ep("/v1/years", recover val Array[String val] end))
      .push(_ep("/v1/speakers", recover val Array[String val](1) .> push("year") end))
      .push(_ep("/v1/speakers/:slug", recover val Array[String val] end))
      .push(_ep("/v1/speakers/:year/:slug", recover val Array[String val] end))
      .push(_ep("/v1/sponsors", recover val Array[String val](1) .> push("year") end))
      .push(_ep("/v1/sponsors/:slug", recover val Array[String val] end))
      .push(_ep("/v1/sponsors/:year/:slug", recover val Array[String val] end))

  fun _ep(path: String val, query: Array[String val] val): json.JSONObject val =>
    var q = json.JSONArray
    for item in query.values() do
      q = q.push(item)
    end
    json.JSONObject
      .update("method", "GET")
      .update("path", path)
      .update("query", q)

  fun json_object(): json.JSONObject val =>
    json.JSONObject
      .update("language", language())
      .update("language_version", language_version())
      .update("api_version", api_version())
      .update("framework", framework())
      .update("created_year", created_year())
      .update("schema_version", schema_version())
      .update("endpoints", endpoints())

  fun json_string(): String val =>
    json.JSONPrinter.print(json_object())
