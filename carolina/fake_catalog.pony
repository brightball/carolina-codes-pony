// In-memory Catalog for PonyTest.
//
// Lives as `ref` in the test actor (or any single actor). Records SQL so tests
// can prove the shipped handler queried `v1_talks` rather than `v1_year_speakers`.

class FakeCatalog is Catalog
  var _sql_count: USize = 0
  var _connect_count: USize = 0
  var _last_sql: String val = ""
  var _sqls: Array[String val] = Array[String val]

  fun ref query(sql: String val, args: Array[String val] val): Array[Row val] val =>
    _sql_count = _sql_count + 1
    _last_sql = sql
    _sqls.push(sql)
    _respond(sql, args)

  fun sql_count(): USize =>
    _sql_count

  fun connect_count(): USize =>
    _connect_count

  fun last_sql(): String val =>
    _last_sql

  fun saw(fragment: String val): Bool =>
    for s in _sqls.values() do
      if s.at(fragment, 0) or _contains(s, fragment) then
        return true
      end
    end
    false

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

  fun _respond(sql: String val, args: Array[String val] val): Array[Row val] val =>
    if _contains(sql, "FROM v1_speakers WHERE slug =") then
      // unknown slug → empty (404). Known test slug → one row.
      try
        if args(0)? == "diana-pham" then
          return _one(_speaker_row())
        end
      end
      return recover val Array[Row val] end
    end
    if _contains(sql, "FROM v1_speakers") then
      return _one(_speaker_row())
    end
    if _contains(sql, "FROM v1_talks") then
      return _one(_talk_row())
    end
    if _contains(sql, "FROM v1_year_sponsors") then
      try
        if (args.size() >= 2) and (args(1)? == "missing-sponsor") then
          return recover val Array[Row val] end
        end
      end
      return _one(_year_sponsor_row())
    end
    if _contains(sql, "FROM v1_sponsors WHERE slug") then
      try
        if args(0)? == "flywheel" then
          return _one(_sponsor_row())
        end
      end
      return recover val Array[Row val] end
    end
    if _contains(sql, "FROM v1_sponsors") then
      return _one(_year_sponsor_row())
    end
    if _contains(sql, "FROM v1_years") then
      return _one(_year_row())
    end
    if _contains(sql, "FROM v1_sponsorships") then
      return recover val Array[Row val] end
    end
    recover val Array[Row val] end

  fun _one(row: Row val): Array[Row val] val =>
    recover val Array[Row val](1) .> push(row) end

  fun _speaker_row(): Row val =>
    Row(recover val
      Array[(String val, String val)]
        .> push(("slug", "diana-pham"))
        .> push(("first_name", "Diana"))
        .> push(("last_name", "Pham"))
        .> push(("name", "Diana Pham"))
    end)

  fun _talk_row(): Row val =>
    Row(recover val
      Array[(String val, String val)]
        .> push(("slug", "talk"))
        .> push(("title", "Talk"))
        .> push(("speaker_slug", "diana-pham"))
        .> push(("year", "2026"))
        .> push(("languages", "{php}"))
        .> push(("topics", "{development}"))
    end)

  fun _sponsor_row(): Row val =>
    Row(recover val
      Array[(String val, String val)]
        .> push(("slug", "flywheel"))
        .> push(("name", "Flywheel"))
        .> push(("website", "https://getflywheel.com"))
    end)

  fun _year_sponsor_row(): Row val =>
    Row(recover val
      Array[(String val, String val)]
        .> push(("slug", "flywheel"))
        .> push(("name", "Flywheel"))
        .> push(("tier", "platinum"))
        .> push(("year", "2026"))
    end)

  fun _year_row(): Row val =>
    Row(recover val
      Array[(String val, String val)]
        .> push(("year", "2026"))
        .> push(("slug", "2026"))
        .> push(("name", "Carolina Code Conference 2026"))
        .> push(("status", "past"))
    end
    )
