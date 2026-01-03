# User Authentication

## Status: Implemented (Branch: `user_login`)

Rails 8 built-in authentication with registration. Ready for Stripe integration.

## What's Built

### Backend

```
app/controllers/
├── application_controller.rb       # includes Authentication, public by default
├── sessions_controller.rb          # login/logout (generated)
├── passwords_controller.rb         # password reset (generated)
├── users_controller.rb             # registration (we added)
└── scores_controller.rb            # smart_search requires auth

app/models/
├── user.rb                         # has_secure_password, validations
├── session.rb                      # tracks sessions per device
└── current.rb                      # Current.user accessor
```

### Routes

```ruby
resource :session                    # /session/new (login)
resource :user, only: [:new, :create] # /user/new (signup)
resources :passwords, param: :token  # /passwords/new (reset)
```

### Views (Dark Neon Theme)

```
app/views/
├── sessions/new.html.erb           # Sign in
├── users/new.html.erb              # Sign up
└── passwords/
    ├── new.html.erb                # Forgot password
    └── edit.html.erb               # Reset password
```

Styled with `app/assets/tailwind/auth.css` — matches the site's neon aesthetic.

### Pro Landing Page

Updated `app/views/pages/pro.html.erb`:
- Status badge: "Coming Soon" → "Now Available"
- Waitlist removed, replaced with signup/login CTAs
- Hero CTA: "Get Started" → links to `/user/new`
- Pricing CTA: "Subscribe Now" + "Already a member? Sign in"
- Auth-aware: shows "Open Smart Search" when logged in

## Architecture Decision

**Public by default, auth only for paid features.**

```ruby
# ApplicationController
allow_unauthenticated_access  # Everything public

# ScoresController
before_action :require_authentication, only: [:smart_search]
```

Why: 95% of the site is free (catalog, browsing). Only Smart Search is paid.

See also: [pro-architecture.md](pro-architecture.md)

## User Model

```ruby
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
end
```

No `pro` boolean. Account = Pro subscriber. Stripe is source of truth for subscription status.

## What's NOT Built Yet

### Stripe Integration

When ready, add to User model:
```ruby
# stripe_customer_id:string
# subscription_status:string (active, cancelled, past_due)
# subscription_ends_at:datetime
```

Webhook updates these fields. Check `user.subscription_active?` for access control.

### Account Management

No `/account` page yet. Add when needed:
- Change email
- Change password
- View subscription status
- Cancel subscription

---

## Future: Pro Controller Namespace

Current setup mixes free/paid actions in `ScoresController`. Cleaner alternative:

```
app/controllers/
├── application_controller.rb       # Public by default
├── scores_controller.rb            # Free catalog only
└── pro/
    ├── base_controller.rb          # requires auth, pro layout
    ├── search_controller.rb        # Smart Search
    ├── favorites_controller.rb     # Future
    └── collections_controller.rb   # Future
```

**Benefits:**
- Pro controllers use different layout (navbar shows account, not "Pro" button)
- Clean separation of free/paid code
- Easy to add more Pro features

**Implementation:**

```ruby
# app/controllers/pro/base_controller.rb
class Pro::BaseController < ApplicationController
  before_action :require_authentication
  layout "pro"
end

# app/controllers/pro/search_controller.rb
class Pro::SearchController < Pro::BaseController
  def show
    # Smart Search logic (move from ScoresController#smart_search)
  end
end
```

**Routes:**
```ruby
namespace :pro do
  resource :search, only: [:show]      # /pro/search
  resources :favorites, only: [:index, :create, :destroy]
  resources :collections
end
```

**When to do this:** When adding favorites/collections, or if navbar logic gets messy.

---

## Navbar UX Decision

We discussed where to put login. Decision: **Don't add a login button to navbar.**

The Pro button handles both flows:
- New users: Pro → Landing page → "Get Started" → Signup
- Returning users: Pro → Landing page → "Sign in" → Login → Smart Search

After login, the Pro button could become "Smart Search" (label swap based on `authenticated?`).

See discussion in session notes.

---

## Files Changed (This Branch)

```
# New files
app/controllers/users_controller.rb
app/views/users/new.html.erb
app/assets/tailwind/auth.css

# Modified
app/controllers/application_controller.rb  (allow_unauthenticated_access)
app/controllers/scores_controller.rb       (require_authentication for smart_search)
app/models/user.rb                         (added validations)
app/views/sessions/new.html.erb            (restyled)
app/views/passwords/new.html.erb           (restyled)
app/views/passwords/edit.html.erb          (restyled)
app/views/pages/pro.html.erb               (removed waitlist, added CTAs)
app/assets/tailwind/pro.css                (added live badge, CTA styles)
app/assets/tailwind/application.css        (import auth.css)
config/locales/en.yml                      (new pro.* keys)
config/locales/de.yml                      (new pro.* keys)
config/routes.rb                           (resource :user)
```

## Next Steps

1. **Test the flow** — sign up, sign in, access smart search, password reset
2. **Stripe integration** — see [Stripe docs](https://stripe.com/docs/billing/subscriptions/build-subscriptions)
3. **Email delivery** — configure Action Mailer for password resets
4. **Pro namespace** — optional, do when adding favorites/collections
