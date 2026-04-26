---
status: complete
---

# Sprint 1.1 — Project Scaffold & Dependency Configuration

**Spec:** spec-1  
**Goal:** Generate a clean Phoenix 1.7 + LiveView app, pin all dependencies, configure env vars, and verify the project compiles and boots with a passing baseline test suite.  
**Depends on:** nothing — this is the foundation  
**Delivers:** a bootable Phoenix app at `http://localhost:4000` with all spec-1 deps installed

---

## TDD Approach

Write all tests **before** implementing. Run `mix test` — every test must fail (red). Implement only what is needed to make each test pass (green). Commit green state after each section.

---

## Step 1 — Generate the Phoenix app

```bash
# From /Users/agard/NJIT/IS322/Final/
mix phx.new chat_app \
  --no-ecto \
  --no-dashboard \
  --no-mailer \
  --live \
  --app chat_app

cd chat_app
```

Flags explained:

- `--no-ecto` — no DB in spec-1
- `--no-dashboard` — removes LiveDashboard dep noise
- `--no-mailer` — not needed
- `--live` — scaffold includes LiveView

---

## Step 2 — Pin dependencies in `mix.exs`

Replace the generated `deps/0` with the exact versions from the spec:

```elixir
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:phoenix_html, "~> 4.0"},
    {:plug_cowboy, "~> 2.7"},
    {:req, "~> 0.5"},
    {:earmark, "~> 1.4"},
    {:jason, "~> 1.4"},
    {:dotenvy, "~> 0.8", only: :dev},
    # test
    {:floki, ">= 0.30.0", only: :test}
  ]
end
```

Then:

```bash
mix deps.get
```

---

## Step 3 — Node dependencies

```bash
cd assets
npm install --save-dev tailwindcss@latest \
  @tailwindcss/vite \
  tailwindcss-animate \
  @tailwindcss/typography
cd ..
```

Verify `package.json` contains all four packages.

---

## Step 4 — Config: `config/runtime.exs`

Add the OpenAI key fetch. `System.fetch_env!/1` intentionally raises at boot if the var is absent — this is correct behavior for production. In test env we supply a stub value.

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :chat_app, :openai_api_key, System.fetch_env!("OPENAI_API_KEY")
end

if config_env() == :dev do
  config :chat_app, :openai_api_key, System.fetch_env!("OPENAI_API_KEY")
end
```

---

## Step 5 — Test env config stub

Add to `config/test.exs` so tests never need a real API key:

```elixir
config :chat_app, :openai_api_key, "sk-test-stub"
```

---

## Step 6 — `.env` file and `.gitignore`

Create `.env` (never commit this):

```
OPENAI_API_KEY=sk-YOUR_KEY_HERE
```

Ensure `.gitignore` contains:

```
# env
.env

# build artifacts
/priv/static/assets/
/_build/
/deps/
```

---

## Step 7 — Write tests FIRST (Red)

### `test/chat_app_web/router_test.exs`

```elixir
defmodule ChatAppWeb.RouterTest do
  use ChatAppWeb.ConnCase, async: true

  # Positive: root path is reachable
  test "GET / returns 200", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200)
  end

  # Negative: unknown routes return 404 (Phoenix default)
  test "GET /does-not-exist returns 404", %{conn: conn} do
    assert_error_sent 404, fn ->
      get(conn, "/does-not-exist")
    end
  end
end
```

> **Note:** This test will fail because the route `"/"` is not yet wired to a LiveView — `ChatLive` does not exist yet. That is correct. The route returns whatever Phoenix scaffolded. We'll fix this in sprint 1.3. For now, just confirm the test file compiles and the 404 case passes.

### `test/chat_app/config_test.exs`

```elixir
defmodule ChatApp.ConfigTest do
  use ExUnit.Case, async: true

  # Positive: API key is configured in test env
  test "openai_api_key is present in application env" do
    key = Application.get_env(:chat_app, :openai_api_key)
    assert is_binary(key)
    assert String.length(key) > 0
  end

  # Negative: key must not be nil
  test "openai_api_key is not nil" do
    key = Application.get_env(:chat_app, :openai_api_key)
    refute is_nil(key)
  end
end
```

### `test/chat_app_web/page_controller_test.exs`

Remove the scaffolded page controller test or mark it as skipped — the root route will become a LiveView in sprint 1.3, not a controller action.

```elixir
defmodule ChatAppWeb.PageControllerTest do
  use ChatAppWeb.ConnCase, async: true

  @tag :skip
  test "GET / (scaffold default — skip; replaced by ChatLive in sprint 1.3)" do
    # This test is superseded by sprint-1.3 LiveView tests
    :ok
  end
end
```

---

## Step 8 — Run tests (Red → Green)

```bash
mix test
```

Expected: all tests pass. Phoenix scaffold generates a default `GET /` route (PageController) that returns HTTP 200, so the `RouterTest` positive case passes immediately — no tagging needed. The 404 test also passes. Both router tests are green from the start and continue to pass in sprint 1.3 when the route is re-wired to `ChatLive`.

---

## Step 9 — Verify the app boots

```bash
# Load .env vars first
export $(cat .env | xargs)
mix phx.server
```

Visit `http://localhost:4000` — the default Phoenix welcome page should load. No errors in the terminal.

---

## Acceptance Criteria

- [ ] `mix deps.get` completes with no errors
- [ ] `mix compile` exits 0 with no warnings
- [ ] `mix test` exits 0
- [ ] `Application.get_env(:chat_app, :openai_api_key)` returns `"sk-test-stub"` in test env
- [ ] `.env` is listed in `.gitignore`
- [ ] `mix phx.server` boots and serves the default page at `http://localhost:4000`
- [ ] `package.json` lists `tailwindcss-animate` and `@tailwindcss/typography` in devDependencies

---

## Out of Scope for This Sprint

- CSS files (sprint 1.2)
- LiveView module (sprint 1.3)
- Any UI markup
