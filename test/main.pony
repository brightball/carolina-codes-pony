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
    test(_TestQualityGateCiEnvHelper)
    test(_TestAllNineRoutes)
    test(_TestUnknownSponsorSlug)
    test(_TestCatalogFailureIsNotEmptySuccess)
    test(_TestDeadConnectionDecision)
    test(_TestPqConnectTimeout)
    test(_TestFlySuspend)
    test(_TestSchedulerCap)

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
    h.assert_true(
      _Has(body, "-Dopenssl_3.0.x"),
      "container compile must define OpenSSL 3")
    h.assert_false(
      _Has(body, "--debug"),
      "container binary must be a non-debug build")

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
    h.assert_true(_Has(body, "\n  prepare:\n"), "missing first-stage job prepare")
    h.assert_true(_Has(body, "\n  test:\n"), "missing Gitea job test")
    h.assert_true(_Has(body, "\n  sast:\n"), "missing Gitea job sast")
    h.assert_true(_Has(body, "\n  audit:\n"), "missing Gitea job audit")
    h.assert_true(_Has(body, "\n  gitleaks:\n"), "missing Gitea job gitleaks")
    h.assert_true(_Has(body, "\n  pony-lint:\n"), "missing Gitea job pony-lint")
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
    h.assert_true(_Has(body, "github.token"))
    h.assert_true(_Has(body, "ci-env.sh restore"))
    h.assert_true(_Has(body, "*restore-prepared-env"))

    let prepare = _GiteaJob(body, "prepare")
    h.assert_true(prepare.size() > 0, "could not parse prepare job")
    h.assert_true(
      _Has(prepare, "git clone --depth 1 --no-checkout"),
      "first-stage job must token-clone GITHUB_SHA")
    h.assert_true(
      _Has(prepare, "GITHUB_SHA"),
      "first-stage job must clone GITHUB_SHA")
    h.assert_true(
      _Has(prepare, "x-access-token"),
      "first-stage job must clone over HTTPS with the job token")
    h.assert_true(
      _Has(prepare, "missing job token for git fetch"))
    h.assert_true(
      _Has(prepare, "ci-env.sh prepare"),
      "first-stage job must install tools via ci-env.sh prepare")
    h.assert_false(
      _Has(prepare, "needs:"),
      "prepare must not depend on a check job")

    _assert_check_job(h, body, "test", "- run: make test")
    _assert_check_job(h, body, "sast", "- run: make sast")
    _assert_check_job(h, body, "audit", "- run: make audit")
    _assert_check_job(h, body, "gitleaks", "- run: make gitleaks")
    _assert_check_job(h, body, "pony-lint", "- run: make lint")
    _assert_check_job(h, body, "smoke", "- run: make smoke")

  fun _assert_check_job(
    h: TestHelper,
    wf: String val,
    job_name: String val,
    make_cmd: String val)
  =>
    let job = _GiteaJob(wf, job_name)
    h.assert_true(job.size() > 0, "could not parse Gitea job " + job_name)
    h.assert_true(
      _Has(job, make_cmd), job_name + " must run " + make_cmd)
    h.assert_true(
      _Has(job, "needs: prepare"),
      job_name + " must need only the first-stage prepare job")
    h.assert_false(
      _Has(job, "git clone"),
      job_name + " re-clones the repo instead of using the prepared environment")
    h.assert_false(
      _Has(job, "apk add"),
      job_name + " must not apk add")
    h.assert_false(
      _Has(job, "apt-get"),
      job_name + " must not apt-get install")
    h.assert_false(
      _Has(job, "pip install"),
      job_name + " must not re-install Python tools")
    if (not _Has(job, "*restore-prepared-env")) and
      (not _Has(job, "ci-env.sh restore"))
    then
      h.fail(job_name + " does not restore the prepared environment")
    end
    let others: Array[String val] val =
      ["test"; "sast"; "audit"; "gitleaks"; "pony-lint"; "smoke"]
    for other in others.values() do
      if other != job_name then
        h.assert_false(
          _Has(job, "needs: " + other),
          job_name + " must not need check job " + other)
      end
    end

class iso _TestQualityGateCiEnvHelper is UnitTest
  fun name(): String => "carolina/structure/ci-env-helper"

  fun apply(h: TestHelper) =>
    let sh = _RepoFile(h, "scripts/ci-env.sh")
    h.assert_true(_Has(sh, "cmd_pack"), "helper must pack the workspace")
    h.assert_true(_Has(sh, "cmd_unpack"), "helper must unpack the workspace")
    h.assert_true(_Has(sh, "cmd_upload"), "helper must upload via artifact API")
    h.assert_true(
      _Has(sh, "cmd_download"), "helper must download via artifact API")
    h.assert_true(_Has(sh, "cmd_prepare"))
    h.assert_true(_Has(sh, "cmd_restore"))
    h.assert_true(
      _Has(sh, "apk add"),
      "helper must install OS packages with apk add")
    h.assert_true(
      _Has(sh, "usr/include/postgresql/libpq-fe.h"),
      "overlay must require libpq-fe.h (apk fetch is empty on apk-tools 3)")
    h.assert_true(
      _Has(sh, "usr/include/openssl/ssl.h"),
      "overlay must require openssl/ssl.h")
    h.assert_true(
      _Has(sh, "usr/bin/python3"),
      "overlay must require python3 for check-job venv/semgrep/audit")
    h.assert_true(_Has(sh, "semgrep"), "helper must install semgrep")
    h.assert_true(_Has(sh, "gitleaks"), "helper must install gitleaks")
    h.assert_true(_Has(sh, "osv-scanner"), "helper must install osv-scanner")
    h.assert_true(_Has(sh, "fileContainerResourceUrl"))
    h.assert_true(_Has(sh, "ponyc"))

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
    h.assert_true(_Has(mk, "smoke:"), "Makefile missing smoke target")
    h.assert_true(
      _Has(mk, "python3 scripts/smoke.py"),
      "smoke must hit the running non-debug binary")
    h.assert_true(
      _Has(mk, "--bin-name pony -o $(BIN_DIR) ."),
      "release binary must use --bin-name pony")
    h.assert_false(
      _Has(mk, "--debug --path=. -D$(SSL_DEFINE) --bin-name pony"),
      "release binary must not be compiled --debug")
    h.assert_true(
      _Has(mk, "check: test sast audit gitleaks lint smoke"),
      "local make check includes the non-debug smoke")
    h.assert_true(
      _Has(mk, "SSL_DEFINE ?= openssl_3.0.x"),
      "local release compile must use the container OpenSSL define")
    let script = _RepoFile(h, "scripts/corral_to_osv.py")
    h.assert_true(_Has(script, "github.com/ponylang/stallion"))
    h.assert_true(_Has(script, "github.com/ponylang/lori"))
    h.assert_true(_Has(script, "github.com/ponylang/ssl"))
    h.assert_true(_Has(script, "osv-scanner-custom.json"))

class iso _TestAllNineRoutes is UnitTest
  fun name(): String => "carolina/handler/routes/all-nine"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    _expect(h, cat, "/", None, 200, "Pony")
    _expect(h, cat, "/health", None, 200, "\"ok\"")
    h.assert_eq[USize](0, cat.sql_count())
    _expect(h, cat, "/v1/years", None, 200, "\"data\"")
    _expect(h, cat, "/v1/speakers", None, 200, "diana-pham")
    _expect(h, cat, "/v1/speakers", "2026", 200, "languages")
    _expect(h, cat, "/v1/speakers/diana-pham", None, 200, "diana-pham")
    _expect(h, cat, "/v1/speakers/no-such-slug", None, 404, "not_found")
    _expect(h, cat, "/v1/speakers/2026/diana-pham", None, 200, "topics")
    _expect(h, cat, "/v1/speakers/2026/no-such-slug", None, 404, "not_found")
    _expect(h, cat, "/v1/sponsors", None, 200, "\"data\"")
    _expect(h, cat, "/v1/sponsors", "2026", 200, "platinum")
    _expect(h, cat, "/v1/sponsors/flywheel", None, 200, "flywheel")
    _expect(h, cat, "/v1/sponsors/no-such-sponsor", None, 404, "not_found")
    _expect(h, cat, "/v1/sponsors/2026/flywheel", None, 200, "flywheel")
    _expect(h, cat, "/v1/sponsors/2026/missing-sponsor", None, 404, "not_found")
    h.assert_true(cat.sql_count() > 0)
    h.assert_eq[USize](0, cat.connect_count())

  fun _expect(
    h: TestHelper,
    cat: carolina.FakeCatalog,
    path: String val,
    year: (String val | None),
    status: U16,
    body_has: String val)
  =>
    (let got, let body) = carolina.Handler(path, year, cat)
    h.assert_eq[U16](status, got)
    h.assert_true(_Has(body, body_has), path + " body missing " + body_has)

class iso _TestUnknownSponsorSlug is UnitTest
  fun name(): String => "carolina/handler/sponsors/unknown-slug"

  fun apply(h: TestHelper) =>
    let cat = recover ref carolina.FakeCatalog end
    (let status, let body) =
      carolina.Handler("/v1/sponsors/no-such-sponsor", None, cat)
    h.assert_eq[U16](404, status)
    h.assert_true(_Has(body, "not_found"))

class iso _TestCatalogFailureIsNotEmptySuccess is UnitTest
  fun name(): String => "carolina/handler/catalog-failure-not-empty"

  fun apply(h: TestHelper) =>
    let cat = recover ref _ErrorCatalog end
    (let health, let health_body) = carolina.Handler("/health", None, cat)
    h.assert_eq[U16](200, health)
    h.assert_true(_Has(health_body, "\"ok\""))
    (let status, let body) = carolina.Handler("/v1/years", None, cat)
    h.assert_eq[U16](500, status)
    h.assert_true(_Has(body, "unavailable"))
    h.assert_false(_Has(body, "\"data\""))

class _ErrorCatalog is carolina.Catalog
  fun ref query(sql: String val, args: Array[String val] val)
    : Array[carolina.Row val] val ?
  =>
    let seen = sql.size() + args.size()
    if seen >= 0 then error end
    error

  fun sql_count(): USize => 0

  fun connect_count(): USize => 0

class iso _TestDeadConnectionDecision is UnitTest
  """
  Drives PqDecision, the function PqCatalog.query calls for keep-or-finish
  and for tuples-ok versus a connection failure. No Postgres.
  """
  fun name(): String => "carolina/postgres/dead-connection-decision"

  fun apply(h: TestHelper) =>
    let ok = carolina.PqCodes.connection_ok()
    let bad = carolina.PqCodes.connection_bad()
    let tuples = carolina.PqCodes.tuples_ok()
    let fatal = carolina.PqCodes.fatal_error()
    let bad_response = carolina.PqCodes.bad_response()
    h.assert_true(carolina.PqDecision.keep_connection(ok))
    h.assert_false(carolina.PqDecision.keep_connection(bad))
    h.assert_true(
      carolina.PqDecision.after_exec(false, tuples, ok, 0) is carolina.PqRows,
      "zero-row PGRES_TUPLES_OK is an empty success")
    h.assert_true(
      carolina.PqDecision.after_exec(false, tuples, ok, 2) is carolina.PqRows)
    h.assert_true(
      carolina.PqDecision.after_exec(true, tuples, ok, 0) is carolina.PqDrop,
      "null result is a dead connection, not zero rows")
    h.assert_true(
      carolina.PqDecision.after_exec(false, fatal, bad, 0) is carolina.PqDrop,
      "fatal result on a bad connection is finished, not reused")
    h.assert_true(
      carolina.PqDecision.after_exec(false, tuples, bad, 0) is carolina.PqDrop)
    h.assert_true(
      carolina.PqDecision.after_exec(false, fatal, ok, 0) is carolina.PqFailed,
      "connection-level query failure is not an empty row set")
    h.assert_true(
      carolina.PqDecision.after_exec(false, bad_response, ok, 0)
        is carolina.PqFailed)
    let src = _RepoFile(h, "carolina/postgres.pony")
    h.assert_true(
      _Has(src, "PqDecision.keep_connection"),
      "PqCatalog must call keep_connection")
    h.assert_true(
      _Has(src, "PqDecision.after_exec"),
      "PqCatalog.query must call after_exec")
    h.assert_false(_Has(src, "var _ok"), "dead connections must not stick _ok")

class iso _TestPqConnectTimeout is UnitTest
  fun name(): String => "carolina/postgres/connect-timeout"

  fun apply(h: TestHelper) =>
    let url =
      carolina.PqDsn("postgres://postgres:postgres@127.0.0.1:5432/carolina_dev")
    h.assert_true(_Has(url, "connect_timeout=2"))
    h.assert_true(_Has(url, "sslmode=disable"))
    let keyword =
      carolina.PqDsn("host=db port=5432 dbname=carolina_dev user=postgres password=x")
    h.assert_true(_Has(keyword, "connect_timeout=2"))
    h.assert_true(_Has(keyword, "sslmode=disable"))
    let kept =
      carolina.PqDsn("host=db connect_timeout=5 sslmode=require")
    h.assert_true(_Has(kept, "connect_timeout=5"))
    h.assert_false(_Has(kept, "connect_timeout=2"))
    h.assert_false(_Has(kept, "sslmode=disable"))

class iso _TestFlySuspend is UnitTest
  fun name(): String => "carolina/fly/suspend"

  fun apply(h: TestHelper) =>
    let body = _RepoFile(h, "fly.toml")
    h.assert_true(_Has(body, "auto_stop_machines = \"suspend\""))
    h.assert_false(_Has(body, "auto_stop_machines = \"stop\""))
    h.assert_true(_Has(body, "auto_start_machines = true"))
    h.assert_true(_Has(body, "min_machines_running = 0"))
    h.assert_true(_Has(body, "path = \"/health\""))
    h.assert_true(_Has(body, "memory = \"256mb\""))
    h.assert_true(_Has(body, "cpu_kind = \"shared\""))
    h.assert_true(_Has(body, "cpus = 1"))

class iso _TestSchedulerCap is UnitTest
  fun name(): String => "carolina/runtime/scheduler-cap"

  fun apply(h: TestHelper) =>
    h.assert_eq[U32](1, carolina.SchedCap.threads())
    let main_src = _RepoFile(h, "main.pony")
    h.assert_true(_Has(main_src, "@runtime_override_defaults"))
    h.assert_true(_Has(main_src, "ponymaxthreads"))
    h.assert_true(_Has(main_src, "SchedCap.threads()"))

primitive _GiteaJob
  """
  Body of one `jobs.<name>` block. Clone/install assertions must target this
  slice, not the whole workflow file.
  """
  fun apply(wf: String val, name: String val): String val =>
    let jobs_at = _Find(wf, "\njobs:\n")
    if jobs_at < 0 then
      return ""
    end
    let header: String val = "\n  " + name + ":\n"
    let start = _FindFrom(wf, header, jobs_at)
    if start < 0 then
      return ""
    end
    let body_start = start + header.size().isize()
    let nxt = _NextJobAt(wf, body_start)
    if nxt < 0 then
      recover val wf.substring(body_start) end
    else
      recover val wf.substring(body_start, nxt) end
    end

primitive _Find
  fun apply(hay: String val, needle: String val): ISize =>
    try
      hay.find(needle)?
    else
      ISize(-1)
    end

primitive _FindFrom
  fun apply(hay: String val, needle: String val, from: ISize): ISize =>
    try
      hay.find(needle, from)?
    else
      ISize(-1)
    end

primitive _NextJobAt
  fun apply(wf: String val, from: ISize): ISize =>
    var i: ISize = from
    let last = wf.size().isize()
    while i < last do
      if wf.at("\n  ", i) and (not wf.at("\n   ", i)) then
        if _JobHeaderAt(wf, i + 1) then
          return i
        end
      end
      i = i + 1
    end
    ISize(-1)

primitive _JobHeaderAt
  fun apply(wf: String val, line_start: ISize): Bool =>
    var j: ISize = line_start
    let last = wf.size().isize()
    while (j < last) and (not wf.at("\n", j)) do
      j = j + 1
    end
    let line: String val = recover val wf.substring(line_start, j) end
    _IsJobHeaderLine(line)

primitive _IsJobHeaderLine
  fun apply(line: String val): Bool =>
    if line.size() < 4 then
      return false
    end
    if not line.at("  ", 0) then
      return false
    end
    if line.at("   ", 0) then
      return false
    end
    if not line.at(":", (line.size() - 1).isize()) then
      return false
    end
    var i: USize = 2
    let last = line.size() - 1
    if last <= 2 then
      return false
    end
    while i < last do
      try
        let c = line(i)?
        let ok =
          ((c >= 'A') and (c <= 'Z')) or
          ((c >= 'a') and (c <= 'z')) or
          ((c >= '0') and (c <= '9')) or
          (c == '_') or
          (c == '-')
        if not ok then
          return false
        end
      else
        return false
      end
      i = i + 1
    end
    true

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



