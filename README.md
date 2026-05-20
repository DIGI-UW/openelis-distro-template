# OpenELIS Distro Template

A [Copier](https://copier.readthedocs.io/) template for generating deployable
OpenELIS Global distribution repos for a country, site, or project. The
template renders into a self-contained Docker Compose stack that boots on
defaults — accept the prompts, copy `.env.example` to `.env`, and the demo
stack comes up with a working OpenELIS frontend, FHIR store, analyzer bridge,
and a curated set of vendor analyzer profiles already mounted.

Customize incrementally from there: rotate generated secrets, pin upstream
image versions, add distro-specific analyzer profiles, and replace the demo
facility identity with your deployment's. The `oe_context.py doctor --prod`
gate flags anything that still looks demo-quality before you ship.

**For a guided walkthrough** of creating a country/site distro,
including a phase-by-phase checklist and a worked PNG example, see
[CREATING-A-DISTRO.md](CREATING-A-DISTRO.md).

## Create a new distro in 60 seconds

```bash
# 1. Install Copier (one-time setup).
pipx install copier      # or: pip install --user copier

# 2. Generate a distro. Press Enter at every prompt to accept defaults.
#    --trust is required: this template runs post-generate tasks that
#    materialize per-distro random secrets and merge the analyzer-profile
#    tree. Without --trust, copier prompts before running them.
copier copy --trust gh:DIGI-UW/openelis-distro-template my-distro

# 3. Boot it.
cd my-distro
cp .env.example .env
docker compose up -d

# 4. Open OpenELIS.
open http://localhost:8080/OpenELIS-Global/      # macOS
# xdg-open http://localhost:8080/OpenELIS-Global # Linux

# 5. Confirm the contextualization state.
python3 tools/contextualize/oe_context.py doctor
```

That's the whole loop. The first `copier copy` generates per-distro random
values for `POSTGRES_PASSWORD` and `FHIRSTORE_PASSWORD` (no shared
`demo-password` across distros), drops the curated analyzer profiles into
`configs/analyzer-profiles/core/`, and renders the Docker Compose stack with
demo facility metadata.

## What the defaults give you

A working demo: PostgreSQL + OpenELIS Global + frontend + FHIR store +
analyzer bridge + proxy, networked together. Per-distro random secrets in
`.env.example` (and `.env` after you copy it). 12 vendored analyzer profiles
across ASTM, file, and HL7 protocols. Demo facility identity (`Demo
Country`, `demo-facility`). The contextualization manifest at
`context/config-surfaces.yml` enumerates every place a deployment-specific
value needs to go.

## What to change before production

Walk through these in order. Each links to the surface that owns the value.

- **Rotate the generated secrets.** Edit `.env` and replace both
  `POSTGRES_PASSWORD` and `FHIRSTORE_PASSWORD`. Then:
  ```bash
  python3 tools/contextualize/oe_context.py doctor --prod
  ```
  The `--prod` gate fails if `.env` still uses the values that shipped in
  `.env.example`. See [`docs/contextualization.md`](docs/contextualization.md)
  for the rationale.
- **Pin upstream image versions.** Compose ships with `:develop` floats for
  the OpenELIS, frontend, FHIR, and bridge images. Replace these with
  versioned tags before tagging a release. Use `scripts/pin-versions.sh
  <oe-version> <bridge-version>` (added by the release machinery) to rewrite
  the image refs in one shot, then commit. The release workflow's pin-check
  gate refuses to publish if any `image:` line still resolves to a moving
  label.
- **Customize identity and locality.** `context_name`, `project_name`,
  `default_nationality`, `facility_id`, `timezone`, and `public_hostname`
  are Copier prompts at generation time, but they're easy to change later —
  edit `.copier-answers.yml` and run `copier update`. See
  [`docs/contextualization.md`](docs/contextualization.md) for what each
  surface controls.
- **Add distro-specific analyzer profiles.** The 12 profiles in
  `configs/analyzer-profiles/core/` are the upstream-managed defaults.
  Drop your distro's profiles (overrides or additions) into
  `configs/analyzer-profiles/distro/<protocol>/`. Filename collisions:
  `distro/` wins. After editing, run `python3
  tools/contextualize/oe_context.py apply` to materialize the merged set
  into `configs/analyzer-profiles/.active/` (which Docker Compose mounts).
  See [`docs/analyzer-profiles.md`](docs/analyzer-profiles.md).
- **Cut a release.** When you're ready to tag, use the bundled
  `release.yml` workflow (`gh workflow run release.yml`) with a distro
  version, OE version, and bridge version. The workflow builds a tarball,
  validates that all image pins are versioned, and creates a GitHub Release
  with the upstream OE and bridge release notes folded in. See
  [`docs/release-workflow.md`](docs/release-workflow.md).

## Updating an existing distro from the template

Once a distro has been generated, re-run Copier from inside the generated
directory to pull in template changes:

```bash
cd my-distro
copier update
```

Copier preserves your previous answers via `.copier-answers.yml` and writes
`.rej` files for any conflicts. The post-generate secret-rotation task is
**not** re-run on update (the template's `_skip_if_exists` list protects
`.env.example`), so your stored secrets stay intact.

## Repo layout

| Path | Purpose |
| ---- | ------- |
| `copier.yml` | Copier questions, tasks, and exclusions — the entry point for `copier copy`. |
| `docker-compose.yml.jinja` | Compose stack: db, OE, frontend, FHIR, analyzer bridge, proxy. All services on a named `openelis-<slug>-network`. |
| `.env.example.jinja` | Environment file with sentinels (`__GENERATED_SECRET__`) the post-generate task replaces with per-distro random values. |
| `configs/properties/` | OE Spring properties seed payload, including `${FHIRSTORE_PASSWORD}` env-var placeholder. |
| `configs/configuration/backend/` | Generic backend seed (CSVs, questionnaires). Add country-specific overrides in your generated distro. |
| `configs/analyzer-profiles/core/` | Vendor analyzer profiles, upstream-managed. Currently vendored; planned to be sourced from a standalone profiles repo via a sync tool. |
| `configs/analyzer-profiles/distro/` | Distro-specific overrides and additions. Empty by default. |
| `context/config-surfaces.yml.jinja` | Manifest of every contextualization surface and its docs anchor. Source of truth for both docs and the CLI. |
| `context/profiles/demo/context.yml.jinja` | Demo values for contextualization, applied via `oe_context.py apply --profile demo`. |
| `tools/contextualize/` | The `oe_context.py` CLI (doctor, apply, sync_analyzer_profiles skeleton). |
| `tools/copier_tasks/` | Build-time-only Python scripts invoked from `copier.yml _tasks`. Excluded from the rendered distro. |
| `scripts/` | Release-engineering scripts (build-tarball, check-release-pins, pin-versions, build-release-notes) — templatized from the Madagascar distro. |
| `.github/workflows/release.yml.jinja` | Manual-dispatch release workflow that ships in every generated distro. |
| `docs/` | Generated-distro documentation: contextualization, configuration, analyzer profiles, release workflow. |

The template's own `.github/workflows/pr.yml` (the file that exercises
`copier copy` on every PR) is excluded from rendered output — it tests the
template itself, not the distros it generates.

## For template maintainers

- **Add a Copier question:** edit `copier.yml`, add a new top-level key
  with `type`, `default`, and `help`. Reference it in any `.jinja` file
  via `{{ var_name }}`. Always quote user-typed strings in YAML contexts
  with `| tojson`.
- **Add a new config surface:** add an entry to
  `context/config-surfaces.yml.jinja` (id, path, docs_url) and a matching
  section in `docs/contextualization.md.jinja`. The `oe_context.py
  doctor` walks the manifest and fails if a surface lacks a docs
  reference, so the two stay in sync.
- **Add a templated file:** drop `<path>.jinja` anywhere in the tree.
  Copier renders all `.jinja` files into their non-jinja paths. Files
  without `.jinja` are copied verbatim. Use `_exclude:` in `copier.yml`
  for files that live in the template source but shouldn't ship to
  generated distros.
- **Random-secret post-generate task:** the
  `tools/copier_tasks/generate_secrets.py` script replaces every
  `__GENERATED_SECRET__` sentinel in `.env.example` with a distinct
  `secrets.token_urlsafe(32)` value. Add new secret-bearing variables to
  `.env.example.jinja` using the same sentinel. The task is run by
  `copier.yml _tasks`; `_skip_if_exists: [.env.example]` keeps `copier
  update` from rotating values silently.
- **Run the demo-render CI locally:**
  ```bash
  copier copy --trust --defaults . /tmp/demo-distro
  cd /tmp/demo-distro
  python3 tools/contextualize/oe_context.py doctor
  python3 tools/contextualize/oe_context.py apply --profile demo \
      --non-interactive --dry-run
  docker compose config
  ```
  This is the same sequence the `.github/workflows/pr.yml` workflow
  runs on every PR.

## License and provenance

This template was bootstrapped from the
[openelis-madagascar-distro](https://github.com/DIGI-UW/openelis-madagascar-distro)
deployment repo. Release machinery, container layout, and contextualization
patterns are lifted and generalized from that source.
