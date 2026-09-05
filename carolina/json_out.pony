// JSON helpers. Uses the stdlib `json` package (all values are `val`).

use json = "json"

primitive JsonOut
  fun health(): String val =>
    json.JSONPrinter.print(json.JSONObject.update("status", "ok"))

  fun not_found(): String val =>
    json.JSONPrinter.print(json.JSONObject.update("error", "not_found"))

  fun wrap_data(value: json.JSONValue): String val =>
    json.JSONPrinter.print(json.JSONObject.update("data", value))

  fun wrap_array(items: Array[json.JSONValue] val): String val =>
    var arr = json.JSONArray
    for item in items.values() do
      arr = arr.push(item)
    end
    wrap_data(arr)

  fun pg_text_array(raw: String val): json.JSONArray val =>
    """Turn a Postgres text[] literal `{a,b}` into a JSON array."""
    var arr = json.JSONArray
    if (raw.size() == 0) or (raw == "{}") then
      return arr
    end
    var s: String val = raw
    try
      if (s(0)? == '{') and (s(s.size() - 1)? == '}') then
        s = s.substring(1, (s.size() - 1).isize())
      end
    end
    if s.size() == 0 then
      return arr
    end
    for part in s.split(",").values() do
      var p: String val = part.clone().>strip()
      try
        if (p.size() >= 2) and (p(0)? == '"') and (p(p.size() - 1)? == '"') then
          p = p.substring(1, (p.size() - 1).isize())
        end
      end
      if p.size() > 0 then
        arr = arr.push(p)
      end
    end
    arr

  fun row_object(row: Row val): json.JSONObject val =>
    var obj = json.JSONObject
    for (k, v) in row.pairs().values() do
      if (k == "languages") or (k == "topics") then
        obj = obj.update(k, pg_text_array(v))
      elseif k == "year" then
        try
          obj = obj.update(k, v.i64()?)
        else
          obj = obj.update(k, v)
        end
      else
        obj = obj.update(k, v)
      end
    end
    obj

  fun with_field(obj: json.JSONObject val, key: String val, value: json.JSONValue)
    : json.JSONObject val
  =>
    obj.update(key, value)

  fun string_array(items: Array[String val] val): json.JSONArray val =>
    var arr = json.JSONArray
    for item in items.values() do
      arr = arr.push(item)
    end
    arr

  fun i64_array(items: Array[I64] val): json.JSONArray val =>
    var arr = json.JSONArray
    for item in items.values() do
      arr = arr.push(item)
    end
    arr
