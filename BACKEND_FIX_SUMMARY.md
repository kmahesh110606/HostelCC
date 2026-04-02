# Backend Fix Summary: Menu Rating Restrictions & Poll Reset

## Changes Made

### 1. Prevent Duplicate Menu Ratings ✓

**Problem:** Students could rate the same menu item multiple times in the same month, inflating feedback data.

**Solution:** Added a database-level uniqueness constraint to enforce one rating per student per menu item per month.

**Files Modified:**
- `mess/models.py` — Added `unique_together = ("student", "menu_item", "month")` to `Feedback` model
- `mess/migrations/0010_prevent_duplicate_rating.py` — Created migration to apply constraint
- `mess/views.py` — Enhanced `FeedbackViewSet.perform_create()` to check and report when duplicate rating is attempted
- `mess/web_views.py` — Added `IntegrityError` handling for duplicate ratings with user-friendly message

**Behavior:**
- API: Returns HTTP 400 with error message: "You have already rated this menu item this month. You can only rate each menu item once per month."
- Web: Shows warning: "You have already rated this menu item this month. Your previous rating was not updated."

---

### 2. Add Admin Action to Reset Poll Votes ✓

**Problem:** Old poll data (votes and options) from past months accumulated in the database, wasting space and potentially affecting performance.

**Solution:** Added a Django admin action to delete all poll votes/options for selected month(s) in bulk.

**Files Modified:**
- `mess/admin.py` — Added admin action `reset_poll_votes_by_month()` to `MenuPollVoteAdmin` class
- Enhanced `MenuPollOptionAdmin` to display vote count and filtering options

**How to Use:**
1. Navigate to Django Admin → Mess Polls → Poll Votes
2. Select one or more votes from past months
3. From the "Action" dropdown, select "Reset poll votes for selected month(s)"
4. Click "Go"
5. The system will delete all votes and options for the selected months and display a confirmation message

**Result:**
- All votes and poll options for the month(s) are deleted
- DB space is freed
- Students can vote again when new polls are created for the next month
- Confirmation message shows total deleted records

---

## Database Migration

Run:
```bash
python manage.py migrate mess
```

This will apply the `0010_prevent_duplicate_rating` migration constraints.

---

## Testing Checklist

- [ ] Try rating the same menu item twice → Should see "already rated" message
- [ ] Rate different items in same month → Should work fine
- [ ] Check admin interface → Can see "Reset poll votes" action
- [ ] Select past month votes and reset → Votes/options deleted, message shown
- [ ] Poll voting in next month works again after reset
