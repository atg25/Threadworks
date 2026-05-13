---
id: SP-05-05
phase: 5
status: active
created: 2026-05-12
activated_date: 2026-05-13
---

# SP-05-05 — User preferences (sizes, brands, budget, style keywords)

Goal
----
Add user preference controls to `UserLive.Settings`: sizes (multi-checkbox), brands (comma-separated), budget min/max (decimals), and style keywords (comma-separated). Persist as JSON arrays and decimals.

Scope
-----
- In: `lib/chat_app_web/live/user_live/settings.ex` template changes, `ChatApp.Accounts.save_preferences/2` upsert logic, validation tests.
- Out: search personalization engine (future phase), card filtering UI (SP-05-03 may consume preferences later).

Tests
-----
Unit

- Name: preferences_parse_brands_trims_and_filters_empty_tokens
  - Inputs: raw string `"Nike,  , Adidas,,Reformation "` from form input.
  - Expected: parsed list `["Nike","Adidas","Reformation"]`.
  - Guards against: empty tokens, whitespace preserved, or incorrect splitting.

- Name: preferences_persist_sizes_as_json_array
  - Inputs: selected sizes `["S","M","L"]` and form submit.
  - Expected: DB `UserPreferences.sizes` equals `["S","M","L"]` (JSON array); re-mount shows boxes checked.
  - Guards against: wrong storage format or missing reload logic.

- Name: preferences_rejects_non_numeric_budget_values
  - Inputs: `budget_min = "abc", budget_max = "50"` submitted.
  - Expected: validation error for `budget_min` and no persistence.
  - Guards against: invalid numeric values saved silently.

- Name: preferences_rejects_budget_min_greater_than_max
  - Inputs: `budget_min = "100", budget_max = "50"` submitted.
  - Expected: validation error about range; no persistence.
  - Guards against: impossible range accepted.

Integration / E2E

- Name: preferences_form_happy_path_persists_and_renders
  - Inputs: sizes `["S","M"]`, brands `"Nike, Reformation"`, budget_min="10", budget_max="150", style_keywords="vintage, street"` and submit.
  - Expected: DB `UserPreferences` updated with arrays for `sizes`, `brands`, `style_keywords` and `budget_min`/`budget_max` stored as `Decimal` (two decimals). Re-mount shows same values.
  - Guards against: type mismatches or stale UI.

- Name: preferences_handles_empty_optional_fields
  - Inputs: blank brands and style keywords submitted.
  - Expected: persisted `brands == []` and `style_keywords == []` (empty arrays) and no crash.
  - Guards against: nil values or JSON null vs empty-array confusion.

Implementation tasks
--------------------

- [x] Add form controls in `UserLive.Settings` template: size checkboxes, brands text input, budget min/max numeric inputs, style keywords input.
- [x] Implement `ChatApp.Accounts.save_preferences(user_id, attrs)` to upsert `user_preferences` row and coerce values to correct types (`Decimal` for budgets, JSON arrays for lists).
- [x] Add validation: numeric budgets and `min <= max` when both present.
- [x] Add tests for parsing, validation, persistence, and UI reload.
- [x] Add accessibility labels for inputs.

Definition of done
------------------

- [ ] All unit and integration tests pass in CI.
- [ ] Preferences persist with exact types: arrays for list fields and `Decimal` for budgets.
- [ ] Manual check: change preferences, submit, reload settings page and verify values.
- [ ] PR documents storage schema and conversion logic.
