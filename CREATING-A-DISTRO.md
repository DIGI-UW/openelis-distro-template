# Creating a new OpenELIS distro from this template

This guide walks through generating a new country/site distro from
`openelis-distro-template` and getting it to a "boots cleanly on demo
defaults" state. Aimed at the person creating the new repo — once they're
done, the [README in the generated distro](README.md.jinja) covers
day-two operations.

The worked example below uses Papua New Guinea (`openelis-png-distro`) but
the same flow applies to any country/site.

## Prerequisites

- Python 3.10+ and either `pipx` or `pip --user`.
- Docker Desktop (macOS/Windows) or Docker Engine + Compose v2 (Linux).
- On Apple Silicon: nothing special required in most cases. OpenELIS
  the codebase runs anywhere Java does, but the published
  `itechuw/openelis-global-2` and `itechuw/openelis-analyzer-bridge`
  images are amd64-only — Docker Desktop emulates them via Rosetta
  by default and the stack boots fine, just a bit slower than native.
  If you hit `no matching manifest for linux/arm64/v8`, enable
  Rosetta in Docker Desktop → Settings → General, or set
  `DOCKER_DEFAULT_PLATFORM=linux/amd64`.
- `gh` CLI authenticated to GitHub (only needed if you'll cut a release
  from the new repo's release workflow).

## Phase 1 — Create the repo and initialize it (~5 minutes)

1. On the template repo page, click **Use this template → Create a new
   repository**. Name your new repo (e.g. `openelis-png-distro`),
   choose an org/visibility, and create it.

2. Clone the new repo and `cd` into it:
   ```bash
   git clone git@github.com:<your-org>/openelis-png-distro.git
   cd openelis-png-distro
   ```

3. Run the init script:
   ```bash
   ./scripts/init.sh
   ```
   You'll be prompted for the answers below. Sensible PNG choices shown:

   | Prompt | PNG value | Notes |
   | ------ | --------- | ----- |
   | `context_slug` | `png` | Lowercase. Flows into compose project name, network name, tarball basename. |
   | `context_name` | `Papua New Guinea` | Free-form. Ends up in OE banner, common.properties country field. |
   | `project_name` | `OpenELIS PNG Distro` | Display name on README, release titles. |
   | `timezone` | `Pacific/Port_Moresby` | IANA timezone, passed as `TZ` to every container. |
   | `default_nationality` | `PNG` | OE `DEFAULT_NATIONALITY` env var. |
   | `facility_id` | `png-default` | OE `org.openelisglobal.facility.id`. |
   | `public_hostname` | `openelis.health.gov.pg` | TLS cert subject + redirect target. |
   | `tarball_basename` | `openelis-png-distro` (default) | `<basename>-<version>.tar.gz` for releases. |

   The script:
   - Installs Copier via `pipx` if it isn't already on your PATH (fails
     with instructions if `pipx` is also missing).
   - Runs Copier in place, rendering every `.jinja` file against your
     answers.
   - Runs the post-generate tasks: replaces `__GENERATED_SECRET__`
     sentinels in `.env.example` with `secrets.token_urlsafe(32)` random
     values, and materializes
     `configs/analyzer-profiles/.active/` from
     `core/ + distro/`.
   - Deletes the template-only scaffolding (`copier.yml`,
     `CREATING-A-DISTRO.md`, `tools/copier_tasks/`,
     `.github/workflows/pr.yml`) and self-deletes.

   After it finishes, the repo is no longer a template — it's a
   self-contained distro.

4. Watch for these output lines confirming the post-generate tasks ran:
   ```
   generate_secrets: replaced 2 sentinel(s)
   merge_profiles: 12 copied, 0 overridden (distro/ wins)
   ```

### Scripted (non-interactive) init

For automation, pass `--defaults` plus `--data key=value` for every
prompt you want to override:

```bash
./scripts/init.sh \
    --data context_slug=png \
    --data 'context_name=Papua New Guinea' \
    --data 'project_name=OpenELIS PNG Distro' \
    --data 'timezone=Pacific/Port_Moresby' \
    --data 'default_nationality=PNG' \
    --data 'facility_id=png-default' \
    --data 'public_hostname=openelis.health.gov.pg' \
    --defaults
```

### Alternative: run Copier directly without the button

```bash
pipx install copier
copier copy --trust gh:DIGI-UW/openelis-distro-template openelis-png-distro
```

Same result. Use whichever you prefer.

You'll be prompted for the answers below. Sensible PNG choices shown:

| Prompt | PNG value | Notes |
| ------ | --------- | ----- |
| `context_slug` | `png` | Lowercase. Flows into compose project name, network name, tarball basename. |
| `context_name` | `Papua New Guinea` | Free-form. Ends up in OE banner, common.properties country field. |
| `project_name` | `OpenELIS PNG Distro` | Display name on README, release titles. |
| `timezone` | `Pacific/Port_Moresby` | IANA timezone, passed as `TZ` to every container. |
| `default_nationality` | `PNG` | OE `DEFAULT_NATIONALITY` env var. |
| `facility_id` | `png-default` | OE `org.openelisglobal.facility.id`. |
| `public_hostname` | `openelis.health.gov.pg` | TLS cert subject + redirect target. |
| `tarball_basename` | `openelis-png-distro` (default) | `<basename>-<version>.tar.gz` for releases. |

After the prompt loop, watch for two task-output lines:

```
generate_secrets: replaced 2 sentinel(s)
merge_profiles: 12 copied, 0 overridden (distro/ wins)
```

If you see "0 sentinel(s)" or no `merge_profiles` line, the trust prompt
was declined or `--trust` was missing — re-run from a clean directory
with `--trust`.

## Phase 2 — Verify boot-by-default (~15 minutes)

```bash
# init.sh already left .env.example with rendered random secrets.
cp .env.example .env
docker compose up -d
```

Validate the stack:

```bash
docker compose ps                       # All 6 services Up
curl -sf http://localhost:8080/OpenELIS-Global/ -o /dev/null && echo OK
python3 tools/contextualize/oe_context.py doctor
```

`doctor` should print `OK: config surfaces, docs, and files are
consistent.` (with a `WARN` that `.env` still matches `.env.example` —
expected on first boot).

Tear down:

```bash
docker compose down -v
```

## Phase 3 — PNG-specific contextualization (variable)

Now replace demo values with real PNG configuration. The
[contextualization manifest](context/config-surfaces.yml.jinja)
enumerates the surfaces; the [contextualization guide that ships in the
generated distro](docs/contextualization.md.jinja) walks each one in
order.

Concrete checklist for a country distro:

- **System properties** (`configs/properties/SystemConfiguration.properties`):
  banner text, phone validation rules, EQA defaults, currency.
- **Common properties** (`configs/properties/common.properties`): facility
  ID, country, state/province, district seed values.
- **Backend seed payload** (`configs/configuration/backend/`): NCE
  categories/types, observation history types, questionnaires.
- **Analyzer profiles** (`configs/analyzer-profiles/distro/<protocol>/`):
  drop PNG-specific JSON profiles here. Same filename as a `core/` file
  overrides; new filename adds. Run `oe_context.py apply` to materialize.
- **TLS / hostname**: set up Let's Encrypt or your own cert workflow.
  This template ships docker-compose only; cert acquisition is per-distro
  (the MG distro's `generate-letsencrypt-certs.sh` is a reference).
- **Image pinning**: while you're iterating, leave the `:develop` tags.
  Before a real release, run `./scripts/pin-versions.sh <oe-version>
  <bridge-version>` and commit.

## Phase 4 — Pre-production gate (~10 minutes)

Before pointing real users at the distro:

1. **Rotate the generated secrets.** Edit `.env`, replace
   `POSTGRES_PASSWORD` and `FHIRSTORE_PASSWORD`. Then:
   ```bash
   python3 tools/contextualize/oe_context.py doctor --prod
   ```
   `--prod` fails if either secret still matches `.env.example`. Move
   the rotated `.env` into your secret store, never commit it.
2. **Pin upstream images.** Tagging a release while `image:` lines still
   say `:develop` will fail the workflow's `check-release-pins.sh` gate.
3. **Run the smoke test.** Boot the stack, log in, fetch a sample, hit a
   FHIR endpoint to confirm `FHIRSTORE_PASSWORD` flowed correctly.
4. **Customize the README.** The generated `README.md` describes the
   demo flow. Replace with PNG-specific operator notes (deploy host,
   monitoring, who to call, where backups live).

## Phase 5 — First release (~30 minutes)

```bash
./scripts/pin-versions.sh 3.2.1.6 3.0.1            # pick concrete versions
git commit -am "chore: pin to OE 3.2.1.6 + bridge 3.0.1 for v0.1.0"
git push

gh workflow run release.yml \
  -f distro_version=0.1.0 \
  -f oe_version=3.2.1.6 \
  -f bridge_version=3.0.1
```

The workflow tags `0.1.0`, builds an `openelis-png-distro-0.1.0.tar.gz`,
assembles release notes from upstream OE and bridge releases, and
publishes a draft GitHub Release for review.

## Updating later from the template

Template improvements (security fixes, new doctor checks, new release
scripts) propagate via `copier update`:

```bash
cd openelis-png-distro
copier update
```

`.env.example` is in `_skip_if_exists`, so your stored secrets are
preserved. For other files, copier merges where it can and writes
`.rej` files for conflicts — review and resolve manually.

## Known limitations and gotchas

- **arm64 hosts:** the published itechuw OpenELIS and bridge images are
  amd64-only. The codebase itself supports any Java-capable platform.
  Docker Desktop on Apple Silicon emulates amd64 transparently via
  Rosetta — works out of the box at a perf cost. If a pull fails with
  `no matching manifest for linux/arm64/v8`, enable Rosetta in Docker
  Desktop or set `DOCKER_DEFAULT_PLATFORM=linux/amd64`.
- **Port 80 / 8080 / 8442 collisions:** the defaults assume nothing else
  is bound on the host. Edit `.env` (`OPENELIS_PROXY_PORT`,
  `OPENELIS_HTTP_PORT`, `ANALYZER_BRIDGE_PORT`) if a conflict exists.
- **Production TLS:** out of scope for this template — bring your own
  cert flow. The MG distro's `compose.letsencrypt.yaml` is a working
  reference but isn't templatized yet.
- **Data migration from a previous OE deployment:** also out of scope.
  MG's `scripts/converters/` is the reference for the typical patterns.
- **FHIRSTORE_PASSWORD propagation:** the value flows via Spring's
  `${FHIRSTORE_PASSWORD}` placeholder in `common.properties`, resolved
  from the OE container's env. If you change OE to skip Spring property
  loading, you'll need to rewrite this with `oe_context.py apply`-time
  materialization instead.

## Reporting back to the template

If you hit a gap that should be fixed in the template itself (a missing
surface, a doctor check that's wrong, a broken script), open an issue or
PR against
[openelis-distro-template](https://github.com/DIGI-UW/openelis-distro-template).
Improvements landed there propagate to every existing distro via
`copier update`.
