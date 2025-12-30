# Waitlist Email Implementation

## Summary

| Environment | Method | Configuration Required | Cost |
|-------------|--------|------------------------|------|
| **Development** | letter_opener (browser preview) | None ✅ | $0 |
| **Production** | SMTP | 5 environment variables | $0 (free tiers available) |

---

## Development Setup (Zero Configuration)

The waitlist works **immediately** in development with **no configuration**:

```bash
bundle install    # Installs letter_opener gem
bin/dev          # Start server
```

Visit http://localhost:3000/smart-search and fill out the form:
- Email saves to SQLite
- Beautiful HTML email opens in new browser tab automatically
- No actual email sent (no SMTP needed)

### Preview Emails Without Submitting Form

You can also preview the emails directly:

```bash
bin/dev
open http://localhost:3000/rails/mailers/waitlist_mailer
```

See both English and German versions side-by-side.

---

## Production Setup (SMTP Required)

### Why SMTP for Production?

Your app deploys via **Kamal** (Docker containers). Docker containers:
- Don't include sendmail
- Run as non-root (can't install/run sendmail easily)
- Use SMTP as the standard email solution

### Free SMTP Options

You need an SMTP server. Here are the best **free options**:

#### Option 1: Gmail (Easiest, 500 emails/day)

**Setup:**
1. Create/use a Gmail account
2. Enable 2-factor authentication
3. Create "App Password": https://myaccount.google.com/apppasswords
4. Use the 16-character password

**Environment variables:**
```bash
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_DOMAIN=scorebase.org
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-16-char-app-password
MAILER_FROM=noreply@scorebase.org
```

**Limits:** 500 emails/day (plenty for waitlist)

#### Option 2: Resend (Best for scaling, 3,000 emails/month)

**Setup:**
1. Sign up at https://resend.com (free, no credit card)
2. Create API key
3. Verify domain (optional but recommended)

**Environment variables:**
```bash
SMTP_ADDRESS=smtp.resend.com
SMTP_PORT=587
SMTP_DOMAIN=scorebase.org
SMTP_USERNAME=resend
SMTP_PASSWORD=re_your_api_key_here
MAILER_FROM=noreply@scorebase.org
```

**Limits:** 3,000 emails/month, 100/day

**Best for:** When you launch Pro (also handles transactional emails)

#### Option 3: Brevo (formerly Sendinblue, 300 emails/day)

**Setup:**
1. Sign up at https://www.brevo.com
2. Get SMTP credentials from Settings → SMTP & API

**Environment variables:**
```bash
SMTP_ADDRESS=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_DOMAIN=scorebase.org
SMTP_USERNAME=your-brevo-email
SMTP_PASSWORD=your-smtp-key
MAILER_FROM=noreply@scorebase.org
```

**Limits:** 300 emails/day

#### Option 4: Mailgun (10,000 emails/month for 3 months)

**Setup:**
1. Sign up at https://www.mailgun.com
2. Verify domain (required)
3. Get SMTP credentials

**Environment variables:**
```bash
SMTP_ADDRESS=smtp.mailgun.org
SMTP_PORT=587
SMTP_DOMAIN=scorebase.org
SMTP_USERNAME=postmaster@your-domain
SMTP_PASSWORD=your-mailgun-password
MAILER_FROM=noreply@scorebase.org
```

**Limits:** 10k emails/month (trial), then pay-as-you-go

---

## Configuring Kamal with SMTP

### 1. Add secrets to Kamal

Edit `.kamal/secrets`:

```bash
#!/bin/bash

# Existing secrets
KAMAL_REGISTRY_PASSWORD="..."
RAILS_MASTER_KEY="..."

# Add SMTP configuration (example using Gmail)
SMTP_ADDRESS="smtp.gmail.com"
SMTP_PORT="587"
SMTP_DOMAIN="scorebase.org"
SMTP_USERNAME="your-email@gmail.com"
SMTP_PASSWORD="your-16-char-app-password"
MAILER_FROM="noreply@scorebase.org"
```

### 2. Update deploy.yml

Edit `config/deploy.yml` and add to `env.secret`:

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
    - SMTP_ADDRESS
    - SMTP_PORT
    - SMTP_DOMAIN
    - SMTP_USERNAME
    - SMTP_PASSWORD
    - MAILER_FROM
```

### 3. Deploy

```bash
kamal deploy
```

---

## Testing Production SMTP Locally

Want to test SMTP before deploying?

```bash
# Set environment variables
export SMTP_ADDRESS=smtp.gmail.com
export SMTP_PORT=587
export SMTP_DOMAIN=scorebase.org
export SMTP_USERNAME=your-email@gmail.com
export SMTP_PASSWORD=your-app-password
export MAILER_FROM=noreply@scorebase.org

# Run in production mode
RAILS_ENV=production bin/rails console

# Send test email
signup = WaitlistSignup.new(email: "test@example.com", locale: "en")
WaitlistMailer.confirmation(signup).deliver_now
```

Check your inbox!

---

## What Gets Sent

Beautiful HTML emails in English and German:

**Features:**
- Refined editorial design (Georgia serif headlines, clean typography)
- Email-client compatible (works in Gmail, Outlook, Apple Mail, etc.)
- Both HTML and plain text versions
- Gold accent color (#c4a661) matching your brand
- Mobile-responsive

**Content:**
- Thank you message
- Explanation of ScoreBase Pro
- Example query showing the power of smart search
- Pricing ($2.99/month)
- Links to free catalog

**Language:** Based on signup URL
- `/en/smart-search` → English email
- `/de/smart-search` → German email

---

## Viewing Waitlist Signups

### Rails Console

```ruby
# Count
WaitlistSignup.count

# View all
WaitlistSignup.order(created_at: :desc).limit(20).each do |s|
  puts "#{s.email} (#{s.locale}) - #{s.created_at}"
end

# Export to CSV
require 'csv'
CSV.generate do |csv|
  csv << ['Email', 'Language', 'Signed Up']
  WaitlistSignup.order(created_at: :desc).each do |s|
    csv << [s.email, s.locale, s.created_at.to_s]
  end
end
```

### SQLite Command

```bash
sqlite3 storage/production.sqlite3
SELECT email, locale, created_at FROM waitlist_signups ORDER BY created_at DESC;
```

---

## Troubleshooting

### Development: Email doesn't open in browser

Check terminal output for the letter_opener URL:
```
Letter opener: http://localhost:3000/letter_opener/...
```

Copy/paste that URL into your browser.

### Production: Emails not sending

**Check environment variables are set:**
```bash
kamal app exec --interactive 'env | grep SMTP'
```

Should show all SMTP_* variables.

**Check logs:**
```bash
kamal app logs
# Look for errors like "Net::SMTPAuthenticationError"
```

**Common issues:**
- Gmail: Using regular password instead of app password
- Wrong port (use 587, not 465)
- Firewall blocking outbound port 587

### Emails go to spam

Normal for low-volume senders. To improve:

1. **Verify your domain** (SPF/DKIM records)
2. **Use authenticated email** - send from `noreply@scorebase.org`, not `noreply@gmail.com`
3. **Warm up** - Start with small batches

For Resend/Mailgun, they provide SPF/DKIM records you add to Cloudflare DNS.

---

## Cost Comparison

| Service | Free Tier | Best For |
|---------|-----------|----------|
| **Gmail** | 500/day | Quick setup, testing |
| **Resend** | 3k/month | Scaling, Pro launch |
| **Brevo** | 300/day | Alternative to Gmail |
| **Mailgun** | 10k/month (3 mo trial) | High volume |

**Recommendation:** Start with Gmail (easiest), switch to Resend when you launch Pro.

---

## Architecture Summary

```
Development Flow:
User → Fills form → Email saved to SQLite → letter_opener → Browser tab opens

Production Flow:
User → Fills form → Email saved to SQLite → Background job → SMTP → User's inbox
```

**Key components:**
- `WaitlistSignup` model: Stores emails + locale
- `WaitlistMailer`: Sends confirmation emails
- `WaitlistSignupsController`: Handles form submission
- `letter_opener`: Dev preview (gem)
- SMTP: Production delivery (any provider)

**Files:**
- Templates: `app/views/waitlist_mailer/confirmation.{en,de}.{html,text}.erb`
- Controller: `app/controllers/waitlist_signups_controller.rb`
- Mailer: `app/mailers/waitlist_mailer.rb`
- Model: `app/models/waitlist_signup.rb`
- Config: `config/environments/{development,production}.rb`

---

## Next Steps

1. **Development:** Already works, just run `bin/dev`
2. **Production:** Choose SMTP provider (Gmail for quick start)
3. **Configure:** Add 5 environment variables to Kamal
4. **Deploy:** `kamal deploy`
5. **Test:** Submit form on scorebase.org, check inbox

That's it. No Dockerfile changes needed, no sendmail required.
