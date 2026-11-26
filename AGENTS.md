# ScoreBase contributor guide

ScoreBase is a Rails/SQLite sheet-music search engine for free scores and commercial editions. Rails owns the catalogue; `rag/` is a separate Python service for semantic search.

## Release and privacy boundaries

- Stop after local verification. Deployment is the maintainer’s job. A push to `main` triggers deployment after CI passes. Do not commit or push without explicit authorization; do not run `bin/deploy`, `bin/kamal deploy`, publish images, or restart production services.
- Keep production measurements, partner terms, search analytics and operator-specific procedures out of the public repo. `docs/intern` is an optional symlink to a separate private checkout, not a dependency. Never copy its contents into public diffs or commit credentials. Run `tools/gsc.rb` locally with a service-account key outside the repository (`GSC_KEY`); the account needs access to the Search Console property.

## Local development and verification

- Rails: `bin/setup --skip-server` for initial setup, `bin/dev` to start. Use RSpec for Rails: `bundle exec rspec spec/path/to/example_spec.rb` while iterating, then `bundle exec rspec`. Keep specs focused on observable behavior.
- Lint changed Ruby files with `bin/rubocop path/to/file.rb`. CI also runs `bin/brakeman --no-pager`, `bin/bundler-audit` and `bin/importmap audit`. See `.github/workflows/ci.yml` for test DB preparation, asset build and the full checks.
- Python: from `rag/`, in a Python 3.11+ virtual environment, install dependencies with `python -m pip install -r requirements.txt` and run `python -m pytest`. Start the local API on loopback only: `python -m uvicorn src.api.main:app --host 127.0.0.1 --port 8001`. Keep the runtime image's dependencies in `rag/requirements-prod.txt` separate from development dependencies.
- Prefer short comments only where a future edit could violate a non-obvious constraint. Use bind parameters or Arel for SQL predicates; do not silence a Brakeman finding just to accept interpolated SQL.

## Database and search

- `scores` has six FTS sync triggers (`db/structure.sql`). A Rails SQLite migration that copies and replaces the table must preserve/recreate those triggers. See `db/migrate/20260517143000_remove_clean_title_from_scores.rb`.
- A native `RENAME COLUMN` updates named schema references without copying rows. A simple unconstrained `ADD COLUMN` is also metadata-only. Native `DROP COLUMN` **rewrites row data** and can block other writers; referenced columns may not be droppable. It does not discard unrelated triggers. See `db/migrate/20260719110000_add_last_crawled_at_and_rename_search_columns.rb` for a native migration.
- Review `db/structure.sql` after migrations: keep intentional schema changes, not FTS5 shadow tables emitted by `.schema`. The virtual tables create their own shadows; a bad dump breaks `RAILS_ENV=test bin/rails db:test:prepare`.
- Keep index and query normalization aligned through `MusicText`. Ensemble hub categories come from `HubDataBuilder::ENSEMBLE_CATEGORIES`, not all `smd_category` values (many are formats, not ensembles).
- Sitemap hub `lastmod` values must reflect catalogue data, not build time. `config/sitemap.rb` selects both SMD representatives and eligible Stretta pages. Preserve child-sitemap serving in `bin/docker-entrypoint` and keep the static-cache TTL shorter than the rebuild interval.

## Catalogue changes

- Importers live in `app/services/`; start with `lib/tasks/imslp.rake` for IMSLP priority imports and `lib/tasks/stretta.rake` for Stretta. Keep ordinary imports independent of private research notes.
- `Score::COMMERCIAL_PARTNERS` defines partner currency and price columns. Use `display_price` and `price_currency`; do not convert prices. Adding a partner also needs localized copy and a working purchase redirect. Keep `Score.free` (non-partner sources) distinct from the user-facing free-price filter, which includes priceless partner rows. SQL negation on a nullable price must not lose those rows.
- For Stretta purchases, build the canonical URL from the validated slug on our own row, not request input or the ID-only URL: the latter redirect drops attribution. `Stretta::Importer::UPDATABLE` defines importer-owned fields; preserve normalized/admin-owned values and keep crawl timestamps from changing `updated_at` on an unchanged score.
- Scope pending enrichment jobs by eligible source before sending rows to an LLM. Ordinary imports do not need a manual partner-match rebuild: scheduled jobs for both partners converge changed matches and preserve suppressions. Schedules live in `config/recurring.yml`.

## Operations

- `config/deploy.yml` is authoritative for roles, limits, accessories and aliases. Scope any authorized one-off write to **one** role: an unscoped `app exec --reuse` can execute on both. A reused container shares its memory limit with the serving process; use the job role for heavy work.
- For sitemap diagnosis distinguish the on-disk file, the origin cache (Thruster), and the CDN. Purging the edge before the origin is fresh can re-cache stale content.
- RAG `ready` rows still need a search text. The mLateOn snapshot includes active `templated` and `indexed` rows with nonblank texts and does not change Rails statuses. Check actual coverage with `python -m src.pipeline.mlateon --check PATH` against the intended catalogue.
