"""
PonyTest suite for the shipped Carolina handler.

Community pattern (tutorial.ponylang.io/testing/ponytest):
- `actor Main is TestList`
- `class iso _Test… is UnitTest`
- hierarchical `name()` strings
- `exclusion_group` when tests would share a resource (live Postgres)
- `long_test` only if actors are required (these tests call Handler.apply
  synchronously, so they complete when `apply` returns)
"""

use "pony_test"
use json = "json"
use carolina = "carolina"

actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    test(_TestStructureIdentity)
    test(_TestStructureStallionNotHttpServer)
    test(_TestHealthJsonNoSql)
    test(_TestHealthParsesAsJson)
    test(_TestIdentityPonyStallion)
    test(_TestUnknownSpeakerSlug)
    test(_TestYearScopedSpeakersLanguagesTopics)
    test(_TestYearScopedSpeakersUseV1Talks)
    test(_TestYearScopedSponsorsTier)
    test(_TestYearsWrappedAsData)
    test(_TestTrailingSlashHealth)
    test(_TestFakeCatalogDoesNotConnect)

class iso _TestStructureIdentity is UnitTest
  fun name(): String => "carolina/structure/identity-primitive"

  fun apply(h: TestHelper) =>
    h.assert_eq[String]("Pony", carolina.Identity.language())
    h.assert_eq[String]("Stallion", carolina.Identity.framework())
    h.assert_eq[I64](1, carolina.Identity.schema_version())
    h.assert_eq[I64](2026, carolina.Identity.created_year())
    h.assert_true(carolina.Identity.framework() != "built-in SAPI")
    h.assert_true(carolina.Identity.language() != "Clef")

class iso _TestStructureStallionNotHttpServer is UnitTest
  fun name(): String => "carolina/structure/framework-is-stallion"

  fun apply(h: TestHelper) =>
    let body = carolina.Identity.json_string()
    h.assert_true(_Has(body, "Stallion"))
    h.assert_true(_Has(body, "Pony"))
    h.assert_false(_Has(body, "http_server"))
    h.assert_false(_Has(body, "Jennet"))
    h.assert_false(_Has(body, "Laravel"))

class iso _TestHealthJsonNoSql is UnitTest
  fun name(): String => "carolina/handler/health"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) = carolina.Handler("/health", None, cat)
    h.assert_eq[U16](200, status)
    h.assert_true(_Has(body, "\"status\""))
    h.assert_true(_Has(body, "\"ok\""))
    h.assert_eq[USize](0, cat.sql_count())
    h.assert_eq[USize](0, cat.connect_count())

class iso _TestHealthParsesAsJson is UnitTest
  fun name(): String => "carolina/handler/health-json-parse"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) = carolina.Handler("/health", None, cat)
    h.assert_eq[U16](200, status)
    match json.JSONParser.parse(body)
    | let doc: json.JSONValue =>
      try
        h.assert_eq[String]("ok", json.JSONNav(doc)("status").as_string()?)
      else
        h.fail("health JSON missing status")
      end
    | let err: json.JSONParseError =>
      h.fail("health body is not JSON: " + err.message)
    end

class iso _TestIdentityPonyStallion is UnitTest
  fun name(): String => "carolina/handler/identity"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) = carolina.Handler("/", None, cat)
    h.assert_eq[U16](200, status)
    h.assert_eq[USize](0, cat.sql_count())
    match json.JSONParser.parse(body)
    | let doc: json.JSONValue =>
      let nav = json.JSONNav(doc)
      try
        h.assert_eq[String]("Pony", nav("language").as_string()?)
        h.assert_eq[String]("Stallion", nav("framework").as_string()?)
      else
        h.fail("language or framework missing")
      end
    | let err: json.JSONParseError =>
      h.fail("identity is not JSON: " + err.message)
    end

class iso _TestUnknownSpeakerSlug is UnitTest
  fun name(): String => "carolina/handler/speakers/unknown-slug"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) = carolina.Handler("/v1/speakers/no-such-slug", None, cat)
    h.assert_eq[U16](404, status)
    h.assert_true(_Has(body, "not_found"))

class iso _TestYearScopedSpeakersLanguagesTopics is UnitTest
  fun name(): String => "carolina/handler/speakers/year-scoped-languages-topics"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) =
      carolina.Handler("/v1/speakers", "2026", cat)
    h.assert_eq[U16](200, status)
    h.assert_true(cat.sql_count() > 0)
    match json.JSONParser.parse(body)
    | let doc: json.JSONValue =>
      try
        let arr = json.JSONNav(doc)("data").as_array()?
        h.assert_true(arr.size() > 0)
        let row = json.JSONNav(arr(0)?)
        h.assert_true(row("languages").as_array()?.size() > 0)
        h.assert_true(row("topics").as_array()?.size() > 0)
      else
        h.fail("year-scoped speaker row missing languages/topics")
      end
    | let err: json.JSONParseError =>
      h.fail("speakers JSON parse failed: " + err.message)
    end

class iso _TestYearScopedSpeakersUseV1Talks is UnitTest
  fun name(): String => "carolina/handler/speakers/year-scoped-uses-v1-talks"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) =
      carolina.Handler("/v1/speakers", "2026", cat)
    h.assert_eq[U16](200, status)
    h.assert_true(cat.saw("v1_talks"))
    h.assert_false(cat.saw("v1_year_speakers"))
    h.assert_true(_Has(body, "languages"))

class iso _TestYearScopedSponsorsTier is UnitTest
  fun name(): String => "carolina/handler/sponsors/year-scoped-tier"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) =
      carolina.Handler("/v1/sponsors", "2026", cat)
    h.assert_eq[U16](200, status)
    match json.JSONParser.parse(body)
    | let doc: json.JSONValue =>
      try
        let arr = json.JSONNav(doc)("data").as_array()?
        h.assert_true(arr.size() > 0)
        h.assert_true(json.JSONNav(arr(0)?)("tier").as_string()?.size() > 0)
      else
        h.fail("year-scoped sponsor row missing tier")
      end
    | let err: json.JSONParseError =>
      h.fail("sponsors JSON parse failed: " + err.message)
    end

class iso _TestYearsWrappedAsData is UnitTest
  fun name(): String => "carolina/handler/years/wrapped-data"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) = carolina.Handler("/v1/years", None, cat)
    h.assert_eq[U16](200, status)
    h.assert_true(_Has(body, "\"data\""))

class iso _TestTrailingSlashHealth is UnitTest
  fun name(): String => "carolina/handler/health-trailing-slash"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) = carolina.Handler("/health/", None, cat)
    h.assert_eq[U16](200, status)
    h.assert_true(_Has(body, "ok"))
    h.assert_eq[USize](0, cat.sql_count())

class iso _TestFakeCatalogDoesNotConnect is UnitTest
  fun name(): String => "carolina/catalog/fake-does-not-open-postgres"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) = carolina.Handler("/health", None, cat)
    h.assert_eq[U16](200, status)
    h.assert_eq[USize](0, cat.connect_count())

primitive _Has
  fun apply(hay: String val, needle: String val): Bool =>
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


