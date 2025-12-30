# Testing Approach - Waitlist Feature

## Philosophy

Simple, practical tests. Test what matters, skip the ceremony.

We trust Rails to work correctly (validations, caching, strong params, CSRF).
We test **our business logic** and critical user flows.

## What We Test

### Model (`spec/models/waitlist_signup_spec.rb`)

**Email Normalization** - Core business logic
- Downcases emails (`USER@EXAMPLE.COM` → `user@example.com`)
- Strips whitespace (`  user@example.com  ` → `user@example.com`)
- Prevents duplicates regardless of case

**Basic Validations** - Critical path
- Email format must be valid
- Locale is required
- Only `en` or `de` allowed

**Why we skip:**
- Testing every validation message (trust Rails)
- Testing Rails built-in uniqueness constraint
- Testing database-level NOT NULL constraints

---

### Controller (`spec/requests/waitlist_signups_spec.rb`)

**Happy Path** - Main user flow
- Valid email creates signup
- Returns success JSON response

**Locale Detection** - Core feature
- URL `/de/waitlist` captures `locale: "de"`
- URL `/en/waitlist` captures `locale: "en"`

**Duplicate Handling** - Edge case that matters
- Second signup with same email returns friendly message
- Still returns `success: true` (not an error to user)

**Validation** - Failure path
- Invalid email rejects with error message

**Why we skip:**
- Rate limiting (relies on Rails.cache, test manually)
- CSRF protection (Rails handles it, verify in browser)
- Strong params (Rails convention, would need to bypass to break)
- Email delivery (test manually, or check letter_opener in dev)

---

## What We Don't Test

### Email Delivery
**Why:**
- Templates are static HTML/text
- Mailer just calls `mail()` (Rails handles it)
- Can verify in development via letter_opener or mailer previews

**Manual verification (live form):**
```bash
bin/dev
# Visit /smart-search, fill out form
# Email opens in browser automatically (letter_opener)
```

**Preview without submitting form:**
```bash
bin/dev
open http://localhost:3000/rails/mailers/waitlist_mailer
# See both EN and DE versions
```
**Location:** `test/mailers/previews/waitlist_mailer_preview.rb`
**Note:** Previews live in `test/` by Rails convention, even though we use RSpec.

### Rate Limiting
**Why:**
- Simple wrapper around `Rails.cache.read/write`
- Trust Rails caching infrastructure works
- Test environment doesn't configure cache persistence

**Manual verification:**
```bash
# Hit the endpoint 6 times
for i in {1..6}; do
  curl -X POST http://localhost:3000/en/waitlist \
    -H "Content-Type: application/json" \
    -H "X-CSRF-Token: $(grep csrf_token tmp/development_secret.txt | cut -d: -f2)" \
    -d "{\"waitlist_signup\":{\"email\":\"test$i@example.com\"}}"
  echo
done

# 6th request should return: {"success":false,"errors":["Too many requests..."]}
```

### JavaScript
**Why:**
- Simple Ajax form submission
- Browser testing would be overkill for this
- JavaScript is thin wrapper around `fetch()`

**Manual verification:**
- Click form in browser
- Check success/error messages appear
- Verify button disables during submission

### CSRF Protection
**Why:**
- Rails default, enabled in ApplicationController
- Would need to actively disable to break

**Manual verification:**
- Try POST without CSRF token → should fail with 422

---

## Running Tests

```bash
# All waitlist tests
bundle exec rspec spec/models/waitlist_signup_spec.rb spec/requests/waitlist_signups_spec.rb

# Watch mode during development
bundle exec rspec spec/models/waitlist_signup_spec.rb spec/requests/waitlist_signups_spec.rb --fail-fast
```

## Test Results

```
WaitlistSignup
  email normalization
    downcases email addresses
    strips whitespace
    prevents duplicate emails regardless of case
  requires a valid email format
  requires a locale
  only allows en or de locales

Waitlist Signups
  POST /en/waitlist
    creates a signup with valid email
    captures locale from URL
    handles duplicate email gracefully
    rejects invalid email

10 examples, 0 failures
```

---

## Adding Tests in Future

**When to add a test:**
- You find a bug in production → write a test that catches it
- You add complex business logic → test the logic
- You're not sure if something works → write a test to prove it

**When NOT to add a test:**
- Testing Rails framework features
- Testing every possible input combination
- Testing implementation details (internal methods)
- Testing third-party libraries

Keep it lean. Keep it practical. Test what matters.
