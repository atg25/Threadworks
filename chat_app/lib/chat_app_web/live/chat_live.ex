defmodule ChatAppWeb.ChatLive do
  @moduledoc """
  The single LiveView at "/" - owns the chat state machine: composer input,
  is_sending flag, streamed assistant buffer, message list, and per-session
  rate-limit key.

  Uses `Phoenix.LiveView` directly (not `ChatAppWeb, :live_view`) so we can
  pass `container: {:div, style: "height: 100%;"}` - the wrapping div must
  carry `height: 100%` to propagate the body's height down to the inner
  `<section>`; without it, `h-full` on the section resolves to 0.

  The streaming task is supervised under `ChatApp.TaskSupervisor` and its
  pid is held in `assigns.stream_task_pid` so `terminate/2` can kill it on
  LiveView teardown.
  """

  use Phoenix.LiveView,
    container: {:div, style: "height: 100%;"}

  # Helpers equivalent to ChatAppWeb, :live_view
  use Gettext, backend: ChatAppWeb.Gettext
  import Phoenix.HTML

  use Phoenix.VerifiedRoutes,
    endpoint: ChatAppWeb.Endpoint,
    router: ChatAppWeb.Router,
    statics: ChatAppWeb.static_paths()

  alias ChatApp.Chat
  alias ChatApp.Markdown

  @impl true
  def mount(params, _session, socket) do
    # Keep URL-driven hero toggles out of production — gated by an app-env flag
    # so this call is safe at runtime (no Mix module dependency in a release).
    hero_state =
      if Application.get_env(:chat_app, :allow_hero_override, false) do
        parse_hero_state(params)
      else
        true
      end

    session_id =
      if connected?(socket) do
        :crypto.strong_rand_bytes(16) |> Base.encode16()
      else
        nil
      end

    {:ok,
     assign(socket,
       messages: [],
       errors: [],
       input: "",
       is_sending: false,
       stream_buffer: "",
       stream_task_pid: nil,
       session_id: session_id,
       rate_limit_error: nil,
       at_bottom: true,
       hero_state: hero_state
     )}
  end

  @impl true
  def handle_event("send_message", %{"input" => text}, socket) do
    socket = ensure_session_id(socket)

    case check_rate_limit(socket) do
      {:rate_limited, limited_socket} ->
        {:noreply, limited_socket}

      :ok ->
        text = String.trim(text)

        socket =
          socket
          |> maybe_recover_stale_send()
          |> assign(rate_limit_error: nil)

        if text == "" || socket.assigns.is_sending do
          {:noreply, socket}
        else
          user_msg = %{role: :user, content: text}
          messages = socket.assigns.messages ++ [user_msg]
          pid = self()

          {:ok, task_pid} =
            Task.Supervisor.start_child(ChatApp.TaskSupervisor, fn ->
              try do
                openai_module().stream(messages, pid)
              rescue
                e -> send(pid, {:stream_error, Exception.message(e)})
              end
            end)

          {:noreply,
           assign(socket,
             messages: messages,
             input: "",
             is_sending: true,
             stream_buffer: "",
             stream_task_pid: task_pid,
             hero_state: false,
             at_bottom: true
           )}
        end
    end
  end

  @impl true
  def handle_event("update_input", %{"input" => value}, socket) do
    {:noreply, assign(socket, input: value)}
  end

  @impl true
  # Invariant: ChatScroll.js always pushes a JS boolean for :at_bottom (see assets/js/hooks/ChatScroll.js).
  def handle_event("scroll_position", %{"at_bottom" => at_bottom}, socket)
      when is_boolean(at_bottom) do
    {:noreply, assign(socket, at_bottom: at_bottom)}
  end

  @impl true
  def handle_info({:stream_token, token}, socket) do
    buffer = socket.assigns.stream_buffer <> token
    messages = Chat.upsert_assistant_message(socket.assigns.messages, buffer)
    {:noreply, assign(socket, messages: messages, stream_buffer: buffer)}
  end

  @impl true
  def handle_info(:stream_done, socket) do
    socket = ensure_socket_changed(socket)
    messages = maybe_drop_empty_assistant(socket.assigns.messages, socket.assigns.stream_buffer)

    {:noreply,
     assign(socket,
       messages: messages,
       is_sending: false,
       stream_buffer: "",
       stream_task_pid: nil
     )}
  end

  @impl true
  def handle_info({:stream_error, reason}, socket) do
    socket = ensure_socket_changed(socket)
    messages = drop_last_assistant(socket.assigns.messages)
    error_index = length(messages) - 1
    error = %{for_index: error_index, reason: reason}
    errors = append_error(socket.assigns.errors, error)

    {:noreply,
     assign(socket,
       messages: messages,
       errors: errors,
       is_sending: false,
       stream_buffer: "",
       stream_task_pid: nil
     )}
  end

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns[:stream_task_pid] do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: Process.exit(pid, :shutdown)
        :ok

      _ ->
        :ok
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      data-chat-surface="true"
      data-chat-surface-mode="embedded"
      class="relative grid h-full min-h-0 flex-1 grid-rows-[auto_minmax(0,1fr)_auto] bg-background"
    >
      <header
        class="ui-chat-header-surface relative z-20 flex shrink-0 items-center justify-between gap-[var(--space-3)] border-b border-[var(--border-color)] px-[var(--space-6)] py-[var(--space-3)]"
        data-chat-surface-header="true"
        data-chat-surface-header-mode="embedded"
      >
        <div class="flex min-w-0 items-center gap-[var(--space-4)]">
          <span class="brand-mark" aria-hidden="true">CA</span>
          <div class="flex min-w-0 flex-col gap-1.5">
            <p class="brand-wordmark truncate">
              Chat<em>App</em>
            </p>
            <span class="brand-status-pill">Chat</span>
          </div>
        </div>
      </header>

      <div
        class="relative flex h-full min-h-0 w-full flex-col overflow-hidden"
        data-chat-message-region="true"
      >
        <div
          class={[
            "ui-chat-viewport-glow pointer-events-none absolute inset-x-0 top-0",
            if(@hero_state, do: "h-24 opacity-45", else: "h-32 opacity-70")
          ]}
          aria-hidden="true"
        />

        <div
          id="chat-viewport"
          class="ui-chat-transcript-plane ui-chat-transcript-frame z-10 flex h-full min-h-0 flex-1 flex-col overflow-y-auto overscroll-contain"
          data-chat-message-viewport="true"
          data-chat-transcript-mode="embedded"
          phx-hook="ChatScroll"
        >
          <div
            class={[
              "ui-chat-message-stack shrink-0 mx-auto w-full max-w-[var(--chat-content-width)] flex min-h-full flex-col",
              if(@hero_state, do: "justify-center", else: "justify-end")
            ]}
            data-chat-message-stack="true"
            data-message-list-state={if @hero_state, do: "hero", else: "conversation"}
            data-message-list-mode="embedded"
          >
            <%= if @hero_state do %>
              <.hero_intro />
            <% else %>
              <%= for msg <- @messages do %>
                <.message_bubble message={msg} />
              <% end %>
              <%= for err <- @errors do %>
                <div
                  class="ui-chat-message-error mx-auto max-w-[80%] rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-xs text-red-700"
                  data-chat-message-error="true"
                  data-role="assistant"
                >
                  Error: <%= err.reason %>
                </div>
              <% end %>

              <%= if @is_sending && @stream_buffer == "" do %>
                <div
                  class="ui-chat-message-assistant rounded-[1.4rem] px-[var(--space-4)] py-[var(--space-3)] text-sm"
                  data-chat-message-role="assistant"
                >
                  <span class="inline-flex items-center gap-1.5" aria-label="Assistant is responding">
                    <span
                      class="size-2 rounded-full bg-accent-interactive animate-pulse"
                      style="animation-delay: 0ms"
                    />
                    <span
                      class="size-2 rounded-full bg-accent-interactive animate-pulse"
                      style="animation-delay: 180ms"
                    />
                    <span
                      class="size-2 rounded-full bg-accent-interactive animate-pulse"
                      style="animation-delay: 360ms"
                    />
                  </span>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <div
          id="scroll-cta-dock"
          class="ui-chat-scroll-cta-dock absolute left-0 right-0 z-10 flex justify-center pointer-events-none hidden"
          style="bottom: calc(var(--chat-scroll-cta-offset) + var(--safe-area-inset-bottom))"
        >
          <button
            id="scroll-to-bottom"
            class="ui-chat-scroll-pill pointer-events-auto focus-ring"
            aria-label="Scroll to bottom"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
              aria-hidden="true"
            >
              <polyline points="6 9 12 15 18 9" />
            </svg>
            Scroll to bottom
          </button>
        </div>
      </div>

      <div class="flex flex-col" data-chat-bottom-rail="true">
        <%= if @rate_limit_error do %>
          <div
            class="mx-auto mb-2 w-full max-w-3xl rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-xs text-red-700"
            role="alert"
          >
            <%= @rate_limit_error %>
          </div>
        <% end %>

        <div
          class="ui-chat-composer-plane relative flex-none px-[var(--space-3)] pt-[var(--space-1)] pb-[var(--space-2)]"
          data-chat-composer-row="true"
        >
          <div
            aria-hidden="true"
            class="ui-chat-composer-seam pointer-events-none absolute inset-x-[var(--space-16)] top-0 h-px"
          />

          <div class="mx-auto w-full max-w-3xl" data-chat-composer-shell="true">
            <form
              phx-submit="send_message"
              phx-change="update_input"
              class={[
                "ui-chat-composer-frame ui-chat-composer-frame-hover",
                "relative flex min-h-[var(--chat-composer-min-height)] items-stretch",
                "gap-[var(--space-2)] overflow-hidden rounded-[var(--chat-composer-radius)]",
                "transition-all duration-300"
              ]}
              data-chat-composer-form="true"
              data-chat-composer-state={if String.trim(@input) != "", do: "ready", else: "idle"}
            >
              <textarea
                id="chat-input"
                name="input"
                phx-hook="ChatComposer"
                rows="1"
                placeholder="Ask..."
                class="flex-1 resize-none bg-transparent px-[var(--chat-composer-field-padding-inline)] py-[var(--chat-composer-field-padding-block)] text-sm outline-none"
                style="max-height: 192px; overflow-y: hidden;"
                disabled={@is_sending}
                data-chat-composer-field="true"
              ><%= @input %></textarea>

              <button
                type="submit"
                disabled={@is_sending}
                class="ui-chat-send-button focus-ring shrink-0 self-center rounded-[var(--fva-shell-radius-control)] p-[var(--space-3)] mr-[var(--space-2)] transition-all active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed"
                aria-label="Send message"
                data-chat-send-state={
                  if @is_sending || String.trim(@input) == "", do: "idle", else: "ready"
                }
              >
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2.5"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <line x1="22" y1="2" x2="11" y2="13" />
                  <polygon points="22 2 15 22 11 13 2 9 22 2" />
                </svg>
              </button>
            </form>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp openai_module do
    Application.get_env(:chat_app, :openai_module, ChatApp.OpenAI)
  end

  defp message_bubble(%{message: %{role: :user}} = assigns) do
    ~H"""
    <div
      class="ui-chat-message-user ml-auto max-w-[80%] rounded-[1.4rem] px-[var(--space-4)] py-[var(--space-3)] text-[0.95rem] leading-relaxed font-medium"
      data-chat-message-bubble={true}
      data-chat-message-role="user"
      data-role="user"
    >
      <%= @message.content %>
    </div>
    """
  end

  defp message_bubble(%{message: %{role: :assistant}} = assigns) do
    ~H"""
    <div
      class="ui-chat-message-assistant rounded-[1.4rem] px-[var(--space-4)] py-[var(--space-3)] text-[0.95rem] leading-relaxed"
      data-chat-message-bubble={true}
      data-chat-message-role="assistant"
      data-role="assistant"
    >
      <div class="prose prose-sm max-w-none">
        <%= raw(Markdown.to_html(@message.content)) %>
      </div>
    </div>
    """
  end

  defp hero_intro(assigns) do
    ~H"""
    <div
      data-homepage-chat-intro="true"
      class="mx-auto flex w-full max-w-3xl flex-col items-center justify-center px-[var(--space-4)] text-center animate-in fade-in slide-in-from-top-4 duration-700 ease-out fill-mode-both pb-[var(--hero-stack-body)]"
    >
      <div
        class="theme-label flex flex-wrap items-center justify-center gap-x-[var(--hero-badge-gap)] gap-y-[var(--phi-2)] text-[length:var(--hero-badge-font-size)] font-bold uppercase tracking-[0.22em]"
        style="margin-bottom: var(--hero-stack-kicker);"
      >
        <span data-homepage-service-chip="true" class="text-accent-interactive">Chat</span>
        <span aria-hidden="true" class="text-foreground/30">/</span>
        <span data-homepage-service-chip="true" class="text-foreground/70">Search</span>
        <span aria-hidden="true" class="text-foreground/30">/</span>
        <span data-homepage-service-chip="true" class="text-foreground/70">Publish</span>
      </div>

      <h2
        class="theme-display text-foreground text-balance"
        style="max-width: var(--hero-title-max-width); font-size: var(--hero-title-font-size); line-height: var(--hero-title-line-height); letter-spacing: var(--tier-display-tracking); font-weight: 560;"
      >
        One compact system for <em class="not-italic accent-underline">AI-assisted</em> work
      </h2>

      <p
        class="theme-body text-foreground/74 measure-comfortable mx-auto"
        style="font-size: var(--hero-body-font-size); line-height: var(--hero-body-line-height); margin-top: var(--hero-stack-body);"
      >
        Chat with your AI assistant. Ask anything.
      </p>

      <div
        class="grid w-full gap-3 text-left sm:grid-cols-3"
        style="margin-top: var(--hero-stack-section);"
        data-homepage-proof-strip="true"
      >
        <%= for %{title: title, body: body} <- proof_points() do %>
          <div class="brand-proof-card" data-homepage-proof-card="true">
            <p class="text-[0.68rem] font-bold uppercase tracking-[0.16em] text-accent-interactive">
              <%= title %>
            </p>
            <p class="text-[0.92rem] leading-[1.55] text-foreground/82">
              <%= body %>
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp proof_points do
    [
      %{
        title: "One compact system",
        body: "Chat, search, jobs, and publishing stay inside one app footprint."
      },
      %{
        title: "Background AI workflows",
        body: "Deferred jobs keep long-running work visible, retryable, and under control."
      },
      %{
        title: "Governed by default",
        body:
          "Role-aware tools, prompts, and workflow actions stay aligned with the operator model."
      }
    ]
  end

  defp parse_hero_state(%{"hero_state" => value}) when value in ["false", "0"], do: false
  defp parse_hero_state(%{"hero_state" => value}) when value in ["true", "1"], do: true
  defp parse_hero_state(_params), do: true

  defp check_rate_limit(socket) do
    case Hammer.check_rate(rate_key(socket), 60_000, 20) do
      {:allow, _count} ->
        :ok

      {:deny, _limit} ->
        message = "Slow down — you're sending messages too fast. Please wait a minute."

        {:rate_limited,
         put_flash(
           assign(socket, rate_limit_error: message),
           :error,
           message
         )}
    end
  end

  @doc false
  def rate_limit_key_for_session(session_id) when is_binary(session_id) do
    "chatlive:#{session_id}"
  end

  defp rate_key(socket) do
    rate_limit_key_for_session(socket.assigns.session_id || "nil")
  end

  defp drop_last_assistant(messages) do
    case List.last(messages) do
      %{role: :assistant} -> List.delete_at(messages, -1)
      _ -> messages
    end
  end

  defp maybe_drop_empty_assistant(messages, stream_buffer) do
    if stream_buffer == "" do
      case List.last(messages) do
        %{role: :assistant, content: ""} -> List.delete_at(messages, -1)
        _ -> messages
      end
    else
      messages
    end
  end

  defp maybe_recover_stale_send(socket) do
    case {socket.assigns.is_sending, socket.assigns.stream_task_pid} do
      {true, pid} when is_pid(pid) ->
        if Process.alive?(pid),
          do: socket,
          else: assign(socket, is_sending: false, stream_task_pid: nil)

      _ ->
        socket
    end
  end

  defp append_error(errors, error) do
    if List.last(errors) == error do
      errors
    else
      errors ++ [error]
    end
  end

  defp ensure_session_id(socket) do
    case socket.assigns.session_id do
      nil -> assign(socket, session_id: :crypto.strong_rand_bytes(16) |> Base.encode16())
      _ -> socket
    end
  end

  defp ensure_socket_changed(%Phoenix.LiveView.Socket{assigns: assigns} = socket) do
    if Map.has_key?(assigns, :__changed__) do
      socket
    else
      %{socket | assigns: Map.put(assigns, :__changed__, %{})}
    end
  end
end
