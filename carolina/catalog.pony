// Catalog contract and v1_* query helpers.
//
// `Catalog` is a `ref` interface: each HTTP connection actor (and each test)
// owns its own implementation. That keeps mutable libpq state off the wire —
// `ref` is not sendable, which is the point of Pony's deny-capabilities.

use json = "json"

interface Catalog
  """
  Read-only SQL against v1_* views. Never Ash tables.
  """
  fun ref query(sql: String val, args: Array[String val] val): Array[Row val] val
  fun sql_count(): USize
  fun connect_count(): USize

primitive Sql
  fun speaker_cols(): String val =>
    "slug, first_name, last_name, name, tagline, bio, company, location, photo_path, twitter_url, linkedin_url, website_url, github_url, featured"

  fun year_sponsor_cols(): String val =>
    "slug, name, website, logo_path, description, blurb, tier, featured, year, twitter_url, linkedin_url, youtube_url, instagram_url, facebook_url"

  fun sponsor_cols(): String val =>
    "slug, name, website, logo_path, description, twitter_url, linkedin_url, youtube_url, instagram_url, facebook_url"

  fun talk_cols(): String val =>
    "slug, title, description, format, youtube_id, year, speaker_slug, languages, topics"

  fun none_args(): Array[String val] val =>
    recover val Array[String val] end

  fun one(a: String val): Array[String val] val =>
    recover val Array[String val](1) .> push(a) end

  fun two(a: String val, b: String val): Array[String val] val =>
    recover val Array[String val](2) .> push(a) .> push(b) end

primitive CatalogFns
  """
  Shipped catalog operations used by Handler. Tests call these too.
  """

  fun query_one(catalog: Catalog, sql: String val, args: Array[String val] val)
    : (Row val | None)
  =>
    let rows = catalog.query(sql, args)
    try
      rows(0)?
    else
      None
    end

  fun talks_for(catalog: Catalog, slug: String val, year: (I64 | None))
    : Array[Row val] val
  =>
    match \exhaustive\ year
    | let y: I64 =>
      catalog.query(
        "SELECT " + Sql.talk_cols() +
        " FROM v1_talks WHERE speaker_slug = $1 AND year = $2 ORDER BY year DESC",
        Sql.two(slug, y.string()))
    | None =>
      catalog.query(
        "SELECT " + Sql.talk_cols() +
        " FROM v1_talks WHERE speaker_slug = $1 ORDER BY year DESC",
        Sql.one(slug))
    end

  fun talk_years(catalog: Catalog, slug: String val): Array[I64] val =>
    let rows =
      catalog.query(
        "SELECT DISTINCT year FROM v1_talks WHERE speaker_slug = $1 ORDER BY year DESC",
        Sql.one(slug))
    _years_from(rows)

  fun sponsor_years(catalog: Catalog, slug: String val): Array[I64] val =>
    let rows =
      catalog.query(
        "SELECT DISTINCT year FROM v1_sponsorships WHERE sponsor_slug = $1 ORDER BY year DESC",
        Sql.one(slug))
    _years_from(rows)

  fun _years_from(rows: Array[Row val] val): Array[I64] val =>
    let out = recover iso Array[I64] end
    for row in rows.values() do
      try
        out.push(row("year").i64()?)
      end
    end
    consume out

  fun uniq_tags(talks: Array[Row val] val, key: String val): Array[String val] val =>
    recover val
      let seen = Array[String val]
      for talk in talks.values() do
        var s: String val = talk(key)
        try
          if (s.size() > 0) and (s(0)? == '{') and (s(s.size() - 1)? == '}') then
            s = s.substring(1, (s.size() - 1).isize())
          end
        end
        if s.size() > 0 then
          for part in s.split(",").values() do
            var p: String val = part.clone() .> strip()
            try
              if (p.size() >= 2) and (p(0)? == '"') and
                (p(p.size() - 1)? == '"')
              then
                p = p.substring(1, (p.size() - 1).isize())
              end
            end
            if p.size() > 0 then
              var found = false
              for item in seen.values() do
                if item == p then found = true end
              end
              if not found then
                seen.push(p)
              end
            end
          end
        end
      end
      seen
    end

  fun list_speakers(catalog: Catalog, year: (I64 | None)): Array[json.JSONValue] val =>
    match \exhaustive\ year
    | None =>
      let rows =
        catalog.query(
          "SELECT " + Sql.speaker_cols() +
          " FROM v1_speakers ORDER BY last_name, first_name",
          Sql.none_args())
      _rows_to_json(rows)
    | let y: I64 =>
      let rows =
        catalog.query(
          "SELECT " + Sql.speaker_cols() +
          " FROM v1_speakers WHERE slug IN (SELECT speaker_slug FROM v1_talks WHERE year = $1) ORDER BY last_name, first_name",
          Sql.one(y.string()))
      _attach_year_tags(catalog, rows, y)
    end

  fun _rows_to_json(rows: Array[Row val] val): Array[json.JSONValue] val =>
    let out = recover iso Array[json.JSONValue] end
    for row in rows.values() do
      out.push(JsonOut.row_object(row))
    end
    consume out

  fun _attach_year_tags(catalog: Catalog, speakers: Array[Row val] val, year: I64)
    : Array[json.JSONValue] val
  =>
    let talks_sql: String val =
      "SELECT " + Sql.talk_cols() +
      " FROM v1_talks WHERE year = $1 ORDER BY speaker_slug, year DESC"
    let talks = catalog.query(talks_sql, Sql.one(AsVal(year.string())))
    let out = recover iso Array[json.JSONValue] end
    for sp in speakers.values() do
      let slug = sp("slug")
      let mine = recover iso Array[Row val] end
      for t in talks.values() do
        if t("speaker_slug") == slug then
          mine.push(t)
        end
      end
      let mine_val: Array[Row val] val = consume mine
      let years = talk_years(catalog, slug)
      var obj = JsonOut.row_object(sp)
      obj = obj.update("year", year)
      obj = obj.update("languages", JsonOut.string_array(uniq_tags(mine_val, "languages")))
      obj = obj.update("topics", JsonOut.string_array(uniq_tags(mine_val, "topics")))
      obj = obj.update("years", JsonOut.i64_array(years))
      var talks_json = json.JSONArray
      for t in mine_val.values() do
        talks_json = talks_json.push(JsonOut.row_object(t))
      end
      obj = obj.update("talks", talks_json)
      out.push(obj)
    end
    consume out
