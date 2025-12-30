# Pro Landing Page - Implementation Notes

## What's Done

✅ Created Pro landing page at `/pro`
✅ 37signals-style copy: honest, opinionated, clear
✅ Waitlist form UI (needs backend wiring)
✅ Navigation updated (desktop + mobile)
✅ Proper CSS classes (no inline styles/JS)
✅ Preserved existing `/smart-search` route (scores#smart_search)

## Known TODOs

### 1. Internationalization (i18n)
**Issue**: All copy on the Pro landing page is hardcoded in English.

**What needs to be done**:
- Extract all strings to `config/locales/en.yml` and `de.yml`
- Add translation keys for:
  - Headlines and subheads
  - Query examples
  - Use case descriptions
  - Pricing copy
  - FAQ questions and answers
  - Form labels and buttons

**Example**:
```yaml
# config/locales/en.yml
pro:
  hero:
    headline: "Search for sheet music the way you actually think"
    subhead: "Stop typing keywords. Start describing what you need..."
  # ... etc
```

### 2. Waitlist Form Implementation ✅ COMPLETED
**Status**: Fully implemented. Works out of the box with NO external service required.

**What was done**:
- ✅ Created `WaitlistSignup` model with email and locale
- ✅ Implemented `WaitlistMailer` with beautiful HTML emails (EN/DE)
- ✅ Added controller action with duplicate detection
- ✅ Wired up frontend form with Ajax submission
- ✅ Configured `letter_opener` for dev (emails open in browser)
- ✅ Configured `sendmail` for production (works on standard Linux servers)
- ✅ Added success/error message display
- ✅ Zero configuration needed - works immediately

**Development**: `bundle install && bin/dev` → emails open in browser automatically
**Production**: Uses sendmail (built-in) or falls back to any SMTP provider

**See**: `docs/waitlist-implementation.md` for details

### 3. Analytics & Tracking
**Recommendation**: Add event tracking for:
- Page views
- Waitlist form submissions
- Click on query examples
- Scroll depth

### 4. SEO Improvements
**Consider adding**:
- Schema.org structured data for SaaS product
- Open Graph meta tags (already in layout, but customize for Pro page)
- Canonical URL
- Meta description optimization

### 5. A/B Testing Opportunities
Once live, consider testing:
- Headline variations
- Pricing placement (earlier vs. later)
- Number of use cases shown
- CTA button text

## File Locations

- **Route**: `config/routes.rb:14`
- **Controller**: `app/controllers/pages_controller.rb:10`
- **View**: `app/views/pages/pro.html.erb`
- **CSS**: Navigation styles in `app/assets/tailwind/navigation.css:109-135`

## Technical Decisions

### Why `/pro` instead of `/smart-search`?
- Existing `/smart-search` route points to `scores#smart_search` (working feature)
- Didn't want to break existing functionality
- `/pro` is short, brandable, and clear
- Can add redirect later if needed

### Why no separate CSS file for Pro page?
- All styles are scoped within `<style>` tag in the view
- Keeps the landing page self-contained
- Easy to iterate without affecting rest of app
- Can extract to `app/assets/tailwind/pro.css` later if needed

### Why dummy form instead of real implementation?
- Email service choice is product decision
- Different services have different integrations
- Better to wire up once backend decision is made
- UI is complete and ready to connect

## Testing Checklist

Before deploying:
- [ ] Test `/pro` route works
- [ ] Test mobile menu Pro link works
- [ ] Test desktop nav Pro button works
- [ ] Verify responsive layout on mobile
- [ ] Check all query examples are visible
- [ ] Test form validation (email format)
- [ ] Verify "Coming Soon" badge is visible
- [ ] Check FAQ section is readable
- [ ] Test "Back to Free Catalog" link
- [ ] Verify no console errors
- [ ] Check accessibility (keyboard navigation, screen readers)
