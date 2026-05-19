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
- On Apple Silicon: enable Rosetta-based amd64 emulation in Docker
  Desktop, or set `DOCKER_DEFAULT_PLATFORM=linux/amd64`. The upstream
  OpenELIS images don't all ship arm64 manifests.
- `gh` CLI authenticated to GitHub (only needed if you'll cut a release
  from the new repo's release workflow).

## Phase 1 — Generate the repo (~5 minutes)

```bash
pipx install copier
copier copy --trust \
  gh:DIGI-UW/openelis-distro-template \
  openelis-png-distro
```

`--trust` is required: the template runs a Copier post-generate task to
materialize per-distro random secrets and merge the analyzer-profile
tree. Without `--trust`, the task is gated behind a prompt; if you
decline, `.env.example` keeps the `__GENERATED_SECRET__` sentinels and
`configs/analyzer-profiles/.active/` is empty.

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
cd openelis-png-distro
git init && git add -A && git commit -m "chore: bootstrap openelis-png-distro from template"

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

- **arm64 hosts:** upstream OE images are amd64-only on some tags.
  Enable Rosetta or `DOCKER_DEFAULT_PLATFORM=linux/amd64`.
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
