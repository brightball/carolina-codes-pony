// One catalog row as an immutable list of `(column, value)` pairs.
//
// `class val` so a row can be stored in `Array[Row val] val` and sent between
// actors. Lookups are linear; v1_* projections are small.

class val Row
  let _pairs: Array[(String val, String val)] val

  new val create(pairs': Array[(String val, String val)] val) =>
    _pairs = pairs'

  fun apply(key: String val): String val =>
    for (k, v) in _pairs.values() do
      if k == key then
        return v
      end
    end
    ""

  fun contains(key: String val): Bool =>
    for (k, _) in _pairs.values() do
      if k == key then
        return true
      end
    end
    false

  fun pairs(): Array[(String val, String val)] val =>
    _pairs

primitive RowBuild
  """Mutable builder that recovers a `Row val`."""
  fun pair(key: String val, value: String val): (String val, String val) =>
    (key, value)

  fun from_map(pairs': Array[(String val, String val)] val): Row val =>
    Row(pairs')
