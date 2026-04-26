defmodule ChatAppWeb.CoreComponents do
  @moduledoc """
  The minimum set of UI primitives this app actually uses:

    * `flash/1` and `flash_group/1` for connection-status and server-error toasts.
    * `icon/1` for Heroicons (used by flash and by error pages).
    * `show/2` and `hide/2` JS commands.
    * `translate_error/1` and `translate_errors/2` for gettext error formatting.

  daisyUI is NOT a dependency. The chat surface uses `assets/css/chat.css`
  custom classes (`.ui-chat-*`); flash toasts use Tailwind utility classes
  inline.
  """
  use Phoenix.Component
  use Gettext, backend: ChatAppWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={render_slot(@inner_block) != [] || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed right-4 top-4 z-50 w-full max-w-sm animate-in slide-in-from-top-2 fade-in duration-300"
      {@rest}
    >
      <div class={[
        "relative flex items-start gap-3 rounded-[1.2rem] border-l-4 border border-l-current px-4 py-3.5 text-sm shadow-[0_22px_48px_-26px_color-mix(in_oklab,var(--shadow-base)_44%,transparent)] backdrop-blur",
        @kind == :info &&
          "border-accent-interactive/25 border-l-[color:var(--accent-interactive)] bg-surface/95 text-foreground",
        @kind == :error &&
          "border-[color:var(--status-error)]/35 border-l-[color:var(--status-error)] bg-[color:var(--status-error)]/8 text-foreground"
      ]}>
        <.icon
          :if={@kind == :info}
          name="hero-information-circle"
          class="size-5 shrink-0 text-[color:var(--accent-interactive)]"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="size-5 shrink-0 text-[color:var(--status-error)]"
        />
        <div class="min-w-0 flex-1">
          <p :if={@title} class="font-bold tracking-tight">{@title}</p>
          <p class="leading-snug">{render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}</p>
        </div>
        <button
          type="button"
          class="group -m-1 inline-flex size-8 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-foreground/8 focus-ring"
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark" class="size-4 opacity-50 group-hover:opacity-90" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(ChatAppWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ChatAppWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
