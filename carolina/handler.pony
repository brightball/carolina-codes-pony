// Shipped request handler.
//
// `Handler.apply` is a primitive function: no actor, no I/O of its own, takes a
// `Catalog ref` that belongs to the calling actor. PonyTest drives this exact
// function. The Stallion connection actor is a thin shell over it.

use json = "json"

primitive Handler
  fun apply(path': String val, year_q: (String val | None), catalog: Catalog)
    : (U16, String val)
  =>
    let path = _normalize(path')
    if path == "/health" then
      return (200, JsonOut.health())
    end
    if path == "/" then
      return (200, Identity.json_string())
    end
    if path == "/v1/years" then
      let rows =
        catalog.query(
          "SELECT year, slug, name, status FROM v1_years ORDER BY year DESC",
          Sql.none_args())
      return (200, JsonOut.wrap_array(_to_values(rows)))
    end
    if path == "/v1/speakers" then
      let year = _year_opt(year_q)
      return (200, JsonOut.wrap_array(CatalogFns.list_speakers(catalog, year)))
    end
    if path == "/v1/sponsors" then
      match _year_opt(year_q)
      | let y: I64 =>
        let rows =
          catalog.query(
            "SELECT " + Sql.year_sponsor_cols() +
            " FROM v1_year_sponsors WHERE year = $1 ORDER BY name",
            Sql.one(y.string()))
        return (200, JsonOut.wrap_array(_to_values(rows)))
      | None =>
        let rows =
          catalog.query(
            "SELECT " + Sql.sponsor_cols() + " FROM v1_sponsors ORDER BY name",
            Sql.none_args())
        return (200, JsonOut.wrap_array(_to_values(rows)))
      end
    end

    let parts = _split(path)
    if (parts.size() == 4) then
      try
        if (parts(0)? == "v1") and (parts(1)? == "speakers") then
          let year = parts(2)?.i64()?
          let slug = parts(3)?
          return _speaker_year(catalog, year, slug)
        end
        if (parts(0)? == "v1") and (parts(1)? == "sponsors") then
          let year = parts(2)?.i64()?
          let slug = parts(3)?
          return _sponsor_year(catalog, year, slug)
        end
      end
    end
    if parts.size() == 3 then
      try
        if (parts(0)? == "v1") and (parts(1)? == "speakers") then
          return _speaker(catalog, parts(2)?)
        end
        if (parts(0)? == "v1") and (parts(1)? == "sponsors") then
          return _sponsor(catalog, parts(2)?)
        end
      end
    end
    (404, JsonOut.not_found())

  fun _speaker(catalog: Catalog, slug: String val): (U16, String val) =>
    match \exhaustive\ CatalogFns.query_one(
      catalog,
      "SELECT " + Sql.speaker_cols() + " FROM v1_speakers WHERE slug = $1",
      Sql.one(slug))
    | None => (404, JsonOut.not_found())
    | let speaker: Row val =>
      var obj = JsonOut.row_object(speaker)
      let talks = CatalogFns.talks_for(catalog, slug, None)
      var talks_json = json.JSONArray
      for t in talks.values() do
        talks_json = talks_json.push(JsonOut.row_object(t))
      end
      obj = obj.update("talks", talks_json)
      obj = obj.update("years", JsonOut.i64_array(CatalogFns.talk_years(catalog, slug)))
      (200, JsonOut.wrap_data(obj))
    end

  fun _speaker_year(catalog: Catalog, year: I64, slug: String val)
    : (U16, String val)
  =>
    match \exhaustive\ CatalogFns.query_one(
      catalog,
      "SELECT " + Sql.speaker_cols() + " FROM v1_speakers WHERE slug = $1",
      Sql.one(slug))
    | None => (404, JsonOut.not_found())
    | let speaker: Row val =>
      let talks = CatalogFns.talks_for(catalog, slug, year)
      if talks.size() == 0 then
        return (404, JsonOut.not_found())
      end
      let years = CatalogFns.talk_years(catalog, slug)
      let other = recover iso Array[I64] end
      for y in years.values() do
        if y != year then other.push(y) end
      end
      var obj = JsonOut.row_object(speaker)
      obj = obj.update("year", year)
      obj = obj.update("years", JsonOut.i64_array(years))
      obj = obj.update("other_years", JsonOut.i64_array(consume other))
      var talks_json = json.JSONArray
      for t in talks.values() do
        talks_json = talks_json.push(JsonOut.row_object(t))
      end
      obj = obj.update("talks", talks_json)
      obj =
        obj.update(
          "languages",
          JsonOut.string_array(CatalogFns.uniq_tags(talks, "languages")))
      obj =
        obj.update(
          "topics",
          JsonOut.string_array(CatalogFns.uniq_tags(talks, "topics")))
      (200, JsonOut.wrap_data(obj))
    end

  fun _sponsor(catalog: Catalog, slug: String val): (U16, String val) =>
    match \exhaustive\ CatalogFns.query_one(
      catalog,
      "SELECT " + Sql.sponsor_cols() + " FROM v1_sponsors WHERE slug = $1",
      Sql.one(slug))
    | None => (404, JsonOut.not_found())
    | let row: Row val =>
      var obj = JsonOut.row_object(row)
      let sps =
        catalog.query(
          "SELECT * FROM v1_sponsorships WHERE sponsor_slug = $1",
          Sql.one(slug))
      var arr = json.JSONArray
      for s in sps.values() do
        arr = arr.push(JsonOut.row_object(s))
      end
      obj = obj.update("sponsorships", arr)
      (200, JsonOut.wrap_data(obj))
    end

  fun _sponsor_year(catalog: Catalog, year: I64, slug: String val)
    : (U16, String val)
  =>
    match \exhaustive\ CatalogFns.query_one(
      catalog,
      "SELECT " + Sql.year_sponsor_cols() +
      " FROM v1_year_sponsors WHERE year = $1 AND slug = $2",
      Sql.two(year.string(), slug))
    | None => (404, JsonOut.not_found())
    | let row: Row val =>
      let years = CatalogFns.sponsor_years(catalog, slug)
      let other = recover iso Array[I64] end
      for y in years.values() do
        if y != year then other.push(y) end
      end
      var obj = JsonOut.row_object(row)
      obj = obj.update("years", JsonOut.i64_array(years))
      obj = obj.update("other_years", JsonOut.i64_array(consume other))
      (200, JsonOut.wrap_data(obj))
    end

  fun _to_values(rows: Array[Row val] val): Array[json.JSONValue] val =>
    let out = recover iso Array[json.JSONValue] end
    for row in rows.values() do
      out.push(JsonOut.row_object(row))
    end
    consume out

  fun _year_opt(year_q: (String val | None)): (I64 | None) =>
    match \exhaustive\ year_q
    | None => None
    | let s: String val =>
      if s.size() == 0 then
        None
      else
        try
          s.i64()?
        else
          None
        end
      end
    end

  fun _normalize(path: String val): String val =>
    if path.size() <= 1 then
      if path.size() == 0 then "/" else path end
    else
      try
        if path(path.size() - 1)? == '/' then
          path.substring(0, (path.size() - 1).isize())
        else
          path
        end
      else
        path
      end
    end

  fun _split(path: String val): Array[String val] val =>
    recover val
      let out = Array[String val]
      var start: USize = 0
      var i: USize = 0
      while i < path.size() do
        try
          if path(i)? == '/' then
            if i > start then
              out.push(path.substring(start.isize(), i.isize()))
            end
            start = i + 1
          end
        end
        i = i + 1
      end
      if path.size() > start then
        out.push(path.substring(start.isize()))
      end
      out
    end
