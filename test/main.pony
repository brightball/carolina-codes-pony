// PonyTest suite for the shipped Carolina handler.
//
// Community pattern (tutorial.ponylang.io/testing/ponytest):
// - `actor Main is TestList`
// - `class iso _Test… is UnitTest`
// - hierarchical `name()` strings
// - `exclusion_group` when tests would share a resource (live Postgres)
// - `long_test` only if actors are required (these tests call Handler.apply
// synchronously, so they complete when `apply` returns)

use "pony_test"
use "files"
use json = "json"
use carolina = "carolina"

actor \nodoc\ Main is TestList
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
    test(_TestDockerfileBinName)
    test(_TestQualityGatePrecommit)
    test(_TestQualityGateGiteaWorkflow)
    test(_TestQualityGateMakefile)

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
    match \exhaustive\ json.JSONParser.parse(body)
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
    match \exhaustive\ json.JSONParser.parse(body)
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
    match \exhaustive\ json.JSONParser.parse(body)
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
    match \exhaustive\ json.JSONParser.parse(body)
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

class iso _TestDockerfileBinName is UnitTest
  """
  ponyc names the binary after the package directory unless --bin-name is set.
  WORKDIR /src would otherwise emit /out/src, which COPY /out/pony would miss.
  """
  fun name(): String => "carolina/structure/dockerfile-bin-name"

  fun apply(h: TestHelper) =>
    let body = _read_dockerfile(h)
    h.assert_true(
      _Has(body, "--bin-name pony"),
      "Dockerfile must pass --bin-name pony so WORKDIR /src still emits /out/pony")
    h.assert_true(
      _Has(body, "COPY --from=build /out/pony "),
      "Dockerfile COPY must use /out/pony, the --bin-name output")
    h.assert_false(
      _Has(body, "/out/src"),
      "Dockerfile must not COPY /out/src")

  fun _read_dockerfile(h: TestHelper): String val =>
    _RepoFile.apply(h, "Dockerfile")

class iso _TestQualityGatePrecommit is UnitTest
  fun name(): String => "carolina/structure/precommit-five-hooks"

  fun apply(h: TestHelper) =>
    let body = _RepoFile(h, ".pre-commit-config.yaml")
    h.assert_true(_Has(body, "id: local-tests"), "missing local-tests hook")
    h.assert_true(_Has(body, "entry: make test"), "local-tests must call make test")
    h.assert_true(_Has(body, "id: sast"), "missing sast hook")
    h.assert_true(_Has(body, "entry: make sast"), "sast must call make sast")
    h.assert_true(_Has(body, "id: audit"), "missing audit hook")
    h.assert_true(_Has(body, "entry: make audit"), "audit must call make audit")
    h.assert_true(_Has(body, "id: gitleaks"), "missing gitleaks hook")
    h.assert_true(
      _Has(body, "entry: make gitleaks"), "gitleaks must call make gitleaks")
    h.assert_true(_Has(body, "id: pony-lint"), "missing pony-lint hook")
    h.assert_true(_Has(body, "entry: make lint"), "pony-lint must call make lint")
    h.assert_true(_Has(body, "pass_filenames: false"))
    h.assert_false(
      _Has(body, "entry: make check"),
      "pre-commit must not fold the five checks into make check")

class iso _TestQualityGateGiteaWorkflow is UnitTest
  fun name(): String => "carolina/structure/gitea-parallel-jobs"

  fun apply(h: TestHelper) =>
    let body = _RepoFile(h, ".gitea/workflows/precommit.yml")
    h.assert_true(_Has(body, "\n  test:\n"), "missing Gitea job test")
    h.assert_true(_Has(body, "\n  sast:\n"), "missing Gitea job sast")
    h.assert_true(_Has(body, "\n  audit:\n"), "missing Gitea job audit")
    h.assert_true(_Has(body, "\n  gitleaks:\n"), "missing Gitea job gitleaks")
    h.assert_true(_Has(body, "\n  pony-lint:\n"), "missing Gitea job pony-lint")
    h.assert_true(_Has(body, "- run: make test"), "test job must run make test")
    h.assert_true(_Has(body, "- run: make sast"), "sast job must run make sast")
    h.assert_true(
      _Has(body, "- run: make audit"), "audit job must run make audit")
    h.assert_true(
      _Has(body, "- run: make gitleaks"),
      "gitleaks job must run make gitleaks")
    h.assert_true(
      _Has(body, "- run: make lint"), "pony-lint job must run make lint")
    h.assert_false(
      _Has(body, "make check"),
      "Gitea workflow must not run a combined make check job")
    h.assert_false(
      _Has(body, "uses: actions/checkout"),
      "Gitea workflow must not use the GitHub checkout action")
    h.assert_false(
      _Has(body, "git init\n"),
      "Gitea workflow must not run git init")
    h.assert_false(
      _Has(body, "git config --global init.defaultBranch"),
      "Gitea workflow must not force a default branch")
    h.assert_true(
      _Has(body, "git clone --depth 1 --no-checkout"),
      "jobs must clone GITHUB_SHA with the job token")
    h.assert_true(_Has(body, "missing job token for git fetch"))
    h.assert_true(_Has(body, "github.token"))

class iso _TestQualityGateMakefile is UnitTest
  fun name(): String => "carolina/structure/makefile-gate-targets"

  fun apply(h: TestHelper) =>
    let mk = _RepoFile(h, "Makefile")
    h.assert_true(_Has(mk, "sast:"), "Makefile missing sast target")
    h.assert_true(_Has(mk, "audit:"), "Makefile missing audit target")
    h.assert_true(_Has(mk, "gitleaks:"), "Makefile missing gitleaks target")
    h.assert_true(_Has(mk, "pony-lint:"), "Makefile missing pony-lint target")
    h.assert_true(_Has(mk, "semgrep"), "sast must invoke semgrep")
    h.assert_true(_Has(mk, "osv-scanner"), "audit must invoke osv-scanner")
    h.assert_true(_Has(mk, "lock.json"), "audit must start from corral lock.json")
    h.assert_true(
      _Has(mk, "detect --source ."),
      "gitleaks target must scan this repo")
    h.assert_true(_Has(mk, "pony-lint"), "lint must invoke pony-lint")
    let script = _RepoFile(h, "scripts/corral_to_osv.py")
    h.assert_true(_Has(script, "github.com/ponylang/stallion"))
    h.assert_true(_Has(script, "github.com/ponylang/lori"))
    h.assert_true(_Has(script, "github.com/ponylang/ssl"))
    h.assert_true(_Has(script, "osv-scanner-custom.json"))

primitive _RepoFile
  fun apply(h: TestHelper, rel: String val): String val =>
    let candidates: Array[String val] val =
      recover val
        Array[String val]
          .> push(rel)
          .> push("../" + rel)
      end
    for path_rel in candidates.values() do
      let path = FilePath(FileAuth(h.env.root), path_rel)
      let file = recover ref File.open(path) end
      if file.errno() is FileOK then
        let s: String val = file.read_string(file.size())
        file.dispose()
        return s
      end
    end
    h.fail(rel + " not found from cwd")
    ""

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



