# Test Directory

This project uses **RSpec** for tests (see `spec/` directory).

But `test/` still exists because **mailer previews live here by Rails convention.**

## What's Here

```
test/
└── mailers/
    └── previews/
        └── waitlist_mailer_preview.rb
```

## Why `test/` Exists When We Use RSpec

**Mailer previews are NOT tests.** They're development tools.

Rails convention: previews live in `test/mailers/previews/` regardless of your test framework.

Don't fight Rails conventions. This is fine.

## Using Mailer Previews

```bash
bin/dev
open http://localhost:3000/rails/mailers/waitlist_mailer
```

View emails in your browser without submitting the form.

## Actual Tests

All RSpec tests are in `spec/`:
```bash
bundle exec rspec
```

---

**TL;DR:**
- `test/mailers/previews/` = Development tools (view emails)
- `spec/` = Actual tests (RSpec)

Rails convention. Don't overthink it.
