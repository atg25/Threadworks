defmodule ChatAppWeb.ChatLive do
  @moduledoc """
  The single LiveView at "/" - owns the chat state machine: composer input,
  is_sending flag, streamed assistant buffer, message list, and per-session
  rate-limit key.

  Uses `Phoenix.LiveView` directly (not `ChatAppWeb, :live_view`) so the
  top-level shell can fill the viewport while the overall page remains
  vertically scrollable.

  The streaming task is supervised under `ChatApp.TaskSupervisor` and its
  pid is held in `assigns.stream_task_pid` so `terminate/2` can kill it on
  LiveView teardown.
  """

  use Phoenix.LiveView,
    container: {:div, style: "min-height: 100%;"}

  # Helpers equivalent to ChatAppWeb, :live_view
  use Gettext, backend: ChatAppWeb.Gettext
  import Phoenix.HTML

  use Phoenix.VerifiedRoutes,
    endpoint: ChatAppWeb.Endpoint,
    router: ChatAppWeb.Router,
    statics: ChatAppWeb.static_paths()

  alias Phoenix.LiveView.JS
  alias ChatApp.Accounts
  alias ChatApp.Conversations
  alias ChatApp.Markdown
  alias ChatApp.Clothing
  alias ChatApp.AI.QueryUnderstander
  alias ChatApp.AI.ResponseParser
  alias ChatAppWeb.SidebarComponent
  import ChatAppWeb.CoreComponents, only: [icon: 1]

  @refresh_sources ["ebay", "depop", "poshmark"]

  @impl true
  def mount(params, session, socket) do
    # Keep URL-driven hero toggles out of production — gated by an app-env flag
    # so this call is safe at runtime (no Mix module dependency in a release).
    hero_state =
      if Application.get_env(:chat_app, :allow_hero_override, false) do
        parse_hero_state(params)
      else
        true
      end

    session_id = derive_session_id(socket, session)

    socket =
      assign(socket,
        messages: [],
        errors: [],
        input: "",
        is_sending: false,
        stream_buffer: "",
        stream_task_pid: nil,
        session_id: session_id,
        conversation_id: nil,
        current_conversation_id: nil,
        current_conversation: nil,
        conversations: [],
        sidebar_open: false,
        usage_totals: %{total_tokens: 0, total_cost_cents: 0},
        settings_open: false,
        settings_saved: false,
        settings_error: nil,
        assistant_message_id: nil,
        persist_dirty: false,
        persist_token_count: 0,
        persist_timer_ref: nil,
        rate_limit_error: nil,
        at_bottom: true,
        hero_state: hero_state,
        new_chat_nonce: 0,
        saved_item_ids: MapSet.new(),
        last_scraped_at: nil,
        rag_status: :idle,
        response_parser_buffer: "",
        pending_cards: []
      )

    if connected?(socket) do
      current_user = current_user_from_session(session, socket)
      user_id = current_user && current_user.id

      saved_item_ids =
        if is_integer(user_id), do: Clothing.list_saved_item_ids(user_id), else: MapSet.new()

      last_scraped_at =
        if is_integer(user_id), do: latest_saved_item_scrape_at(user_id), else: nil

      conversation = Conversations.get_or_create_active(session_id)
      conversations = Conversations.list_conversations(session_id)

      messages =
        conversation.id
        |> Conversations.list_messages()
        |> Enum.map(&to_live_message/1)

      {:ok,
       assign(socket,
         session_id: session_id,
         conversation_id: conversation.id,
         current_conversation_id: conversation.id,
         current_conversation: conversation,
         conversations: conversations,
         usage_totals: Conversations.usage_for_conversation(conversation.id),
         messages: messages,
         current_user: current_user,
         saved_item_ids: saved_item_ids,
         last_scraped_at: last_scraped_at,
         hero_state: socket.assigns.hero_state && messages == []
       )}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("send_message", %{"input" => text}, socket) do
    socket = ensure_session_id(socket)
    socket = ensure_conversation(socket)

    socket =
      socket
      |> maybe_recover_stale_send()
      |> assign(rate_limit_error: nil)

    text = String.trim(text)

    if text == "" || socket.assigns.is_sending do
      {:noreply, socket}
    else
      case check_rate_limit(socket) do
        {:rate_limited, limited_socket} ->
          {:noreply, limited_socket}

        :ok ->
          first_message? = Conversations.list_messages(socket.assigns.conversation_id) == []

          {:ok, user_row} =
            Conversations.append_message(socket.assigns.conversation_id, :user, text)

          if first_message? do
            Conversations.rename_conversation(
              socket.assigns.conversation_id,
              Conversations.auto_title_from_first_message(text)
            )
          end

          user_msg = %{id: user_row.id, role: :user, content: text}
          messages = socket.assigns.messages ++ [user_msg]

          send(self(), {:do_rag, text})

          {:noreply,
           assign(socket,
             messages: messages,
             input: "",
             is_sending: true,
             rag_status: :searching,
             stream_buffer: "",
             stream_task_pid: nil,
             assistant_message_id: nil,
             persist_dirty: false,
             persist_token_count: 0,
             persist_timer_ref: nil,
             settings_saved: false,
             conversations: Conversations.list_conversations(socket.assigns.session_id),
             hero_state: false,
             at_bottom: true
           )}
      end
    end
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    socket = cancel_stream(socket)
    conversation = Conversations.create_conversation(socket.assigns.session_id, %{})

    {:noreply,
     assign(socket,
       conversations: Conversations.list_conversations(socket.assigns.session_id),
       current_conversation: conversation,
       usage_totals: Conversations.usage_for_conversation(conversation.id),
       messages: [],
       errors: [],
       input: "",
       conversation_id: conversation.id,
       current_conversation_id: conversation.id,
       assistant_message_id: nil,
       persist_dirty: false,
       persist_token_count: 0,
       persist_timer_ref: nil,
       rate_limit_error: nil,
       settings_open: false,
       settings_saved: false,
       settings_error: nil,
       at_bottom: true,
       hero_state: true,
       new_chat_nonce: socket.assigns.new_chat_nonce + 1
     )}
  end

  @impl true
  def handle_event("new_conversation_header", params, socket) do
    handle_event("new_conversation", params, socket)
  end

  @impl true
  def handle_event("switch_conversation", %{"id" => id}, socket) do
    with {:ok, conversation} <- conversation_for_session(socket, id) do
      socket = cancel_stream(socket)

      messages =
        Conversations.list_messages(conversation.id)
        |> Enum.map(&to_live_message/1)

      {:noreply,
       assign(socket,
         conversation_id: conversation.id,
         current_conversation_id: conversation.id,
         current_conversation: conversation,
         conversations: Conversations.list_conversations(socket.assigns.session_id),
         usage_totals: Conversations.usage_for_conversation(conversation.id),
         messages: messages,
         settings_saved: false,
         settings_error: nil,
         errors: [],
         hero_state: messages == []
       )}
    else
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_settings", _params, socket) do
    {:noreply,
     assign(socket,
       settings_open: !socket.assigns.settings_open,
       settings_error: nil,
       settings_saved: false
     )}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, sidebar_open: !socket.assigns.sidebar_open)}
  end

  @impl true
  def handle_event("close_sidebar", _params, socket) do
    {:noreply, assign(socket, sidebar_open: false)}
  end

  @impl true
  def handle_event("save_item", %{"item-id" => item_id}, socket) do
    with {:ok, item_id_int} <- parse_item_id(item_id),
         user_id when is_integer(user_id) <- user_id(socket),
         {:ok, item} <- fetch_item(item_id_int),
         %Decimal{} = price_at_save <- Map.get(item, :price),
         {:ok, _} <- Clothing.save_item(user_id, item_id_int, price_at_save) do
      {:noreply,
       assign(socket, saved_item_ids: MapSet.put(socket.assigns.saved_item_ids, item_id_int))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Unable to save item")}
    end
  end

  @impl true
  def handle_event("unsave_item", %{"item-id" => item_id}, socket) do
    with {:ok, item_id_int} <- parse_item_id(item_id),
         user_id when is_integer(user_id) <- user_id(socket),
         :ok <- Clothing.unsave_item(user_id, item_id_int) do
      {:noreply,
       assign(socket, saved_item_ids: MapSet.delete(socket.assigns.saved_item_ids, item_id_int))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Unable to remove saved item")}
    end
  end

  @impl true
  def handle_event("refresh_listings", _params, socket) do
    sources = configured_refresh_sources()

    if sources == [] do
      {:noreply, put_flash(socket, :info, "No sources configured")}
    else
      case enqueue_refresh_jobs(sources) do
        :ok ->
          {:noreply, put_flash(socket, :info, "Refreshing listings in the background")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Unable to refresh listings")}
      end
    end
  end

  @impl true
  def handle_event("save_settings", %{"settings" => settings_params}, socket) do
    socket = ensure_conversation(socket)

    attrs = %{
      model: Map.get(settings_params, "model"),
      system_prompt: Map.get(settings_params, "system_prompt"),
      temperature: Map.get(settings_params, "temperature")
    }

    case Conversations.update_conversation_settings(socket.assigns.conversation_id, attrs) do
      {:ok, conversation} ->
        {:noreply,
         assign(socket,
           current_conversation: conversation,
           settings_open: false,
           settings_saved: true,
           settings_error: nil,
           conversations: Conversations.list_conversations(socket.assigns.session_id)
         )}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           settings_open: true,
           settings_saved: false,
           settings_error: settings_error_message(changeset)
         )}
    end
  end

  @impl true
  def handle_event("rename_conversation_prompt", %{"id" => id}, socket) do
    with {:ok, conversation} <- conversation_for_session(socket, id) do
      {:noreply,
       push_event(socket, "prompt_rename", %{
         id: conversation.id,
         current: conversation.title || ""
       })}
    else
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("rename_conversation", %{"id" => id, "title" => title}, socket) do
    with {:ok, conversation} <- conversation_for_session(socket, id) do
      Conversations.rename_conversation(conversation.id, title)

      {:noreply,
       assign(socket, conversations: Conversations.list_conversations(socket.assigns.session_id))}
    else
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_conversation", %{"id" => id}, socket) do
    with {:ok, conversation} <- conversation_for_session(socket, id) do
      socket = cancel_stream(socket)
      _ = Conversations.delete_conversation(conversation.id)

      conversations = Conversations.list_conversations(socket.assigns.session_id)

      active =
        case conversations do
          [latest | _] -> latest
          [] -> Conversations.create_conversation(socket.assigns.session_id, %{})
        end

      messages =
        Conversations.list_messages(active.id)
        |> Enum.map(&%{id: &1.id, role: &1.role, content: &1.content})

      {:noreply,
       assign(socket,
         conversation_id: active.id,
         current_conversation_id: active.id,
         current_conversation: active,
         conversations: Conversations.list_conversations(socket.assigns.session_id),
         usage_totals: Conversations.usage_for_conversation(active.id),
         messages: messages,
         settings_saved: false,
         settings_error: nil,
         hero_state: messages == []
       )}
    else
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("stop_generation", _params, socket) do
    {:noreply, cancel_stream(socket)}
  end

  @impl true
  def handle_event("regenerate", _params, socket) do
    cond do
      socket.assigns.is_sending ->
        {:noreply, socket}

      true ->
        case List.last(socket.assigns.messages) do
          %{role: :assistant} = last_assistant ->
            case check_rate_limit(socket) do
              {:rate_limited, limited_socket} ->
                {:noreply, limited_socket}

              :ok ->
                trimmed_messages = List.delete_at(socket.assigns.messages, -1)

                if is_integer(last_assistant[:id]) do
                  Conversations.delete_message(last_assistant.id)
                end

                case List.last(Enum.filter(trimmed_messages, &(&1.role == :user))) do
                  nil ->
                    {:noreply, assign(socket, messages: trimmed_messages)}

                  _last_user ->
                    llm_messages = Enum.map(trimmed_messages, &Map.take(&1, [:role, :content]))
                    Process.send_after(self(), {:start_regenerate, llm_messages}, 50)

                    {:noreply,
                     assign(socket,
                       messages: trimmed_messages,
                       is_sending: true,
                       stream_buffer: "",
                       stream_task_pid: nil,
                       assistant_message_id: nil,
                       persist_dirty: false,
                       persist_token_count: 0,
                       persist_timer_ref: nil,
                       rate_limit_error: nil
                     )}
                end
            end

          _ ->
            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("update_input", params, socket) do
    {:noreply, assign(socket, input: params["input"] || "")}
  end

  @impl true
  # Invariant: ChatScroll.js always pushes a JS boolean for :at_bottom (see assets/js/hooks/ChatScroll.js).
  def handle_event("scroll_position", %{"at_bottom" => at_bottom}, socket)
      when is_boolean(at_bottom) do
    {:noreply, assign(socket, at_bottom: at_bottom)}
  end

  @impl true
  def handle_info({:do_rag, _text}, socket) when socket.assigns.is_sending == false do
    # Stop was clicked or conversation switched before augment ran — discard silently.
    {:noreply, assign(socket, rag_status: :idle, response_parser_buffer: "", pending_cards: [])}
  end

  def handle_info({:do_rag, _text}, socket)
      when socket.assigns.stream_buffer != "" or
             is_integer(socket.assigns.assistant_message_id) do
    # Streaming has already started by another path; avoid clobbering the
    # in-flight assistant message with a second RAG branch.
    {:noreply, socket}
  end

  def handle_info({:do_rag, text}, socket) do
    conversation_tokens = socket.assigns.usage_totals.total_tokens

    {:ok, augmented_prompt, items} =
      style_advisor_module().augment(text, conversation_tokens: conversation_tokens)

    case QueryUnderstander.evaluate(items) do
      {:clarify, question} ->
        socket = ensure_conversation(socket)

        {:ok, row} =
          Conversations.append_message(socket.assigns.conversation_id, :assistant, question)

        assistant_msg = %{id: row.id, role: :assistant, content: question}

        {:noreply,
         assign(socket,
           messages: socket.assigns.messages ++ [assistant_msg],
           rag_status: :idle,
           is_sending: false
         )}

      {:recommend, _items} ->
        {:ok, task_pid} = start_streaming(augmented_prompt, socket)

        socket =
          assign(socket,
            rag_status: :streaming,
            response_parser_buffer: socket.assigns.response_parser_buffer,
            pending_cards: socket.assigns.pending_cards,
            stream_task_pid: task_pid
          )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_token, token}, socket)
      when token in ["", nil] and socket.assigns.is_sending == false and
             socket.assigns.stream_buffer == "" do
    {:noreply, socket}
  end

  def handle_info({:stream_token, token}, socket) do
    socket = ensure_conversation(socket)
    {assistant_id, messages} = ensure_assistant_row(socket, socket.assigns.stream_buffer)

    buffer = socket.assigns.stream_buffer <> token

    {cards, remaining_buffer} =
      ResponseParser.parse(token, socket.assigns.response_parser_buffer)

    new_cards =
      Enum.flat_map(cards, fn card ->
        case Clothing.get_item(card.item_id) do
          nil -> []
          item -> [%{item: item, reason: card.reason}]
        end
      end)

    pending_cards = socket.assigns.pending_cards ++ new_cards
    messages = upsert_assistant_message(messages, assistant_id, buffer, pending_cards)

    socket =
      socket
      |> assign(
        messages: messages,
        stream_buffer: buffer,
        assistant_message_id: assistant_id,
        response_parser_buffer: remaining_buffer,
        pending_cards: pending_cards
      )
      |> schedule_persist_timer()
      |> bump_persist_token_count()
      |> maybe_persist_by_token_threshold()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_usage, usage}, socket) do
    socket = ensure_conversation(socket)

    if is_integer(socket.assigns.assistant_message_id) do
      _ =
        Conversations.record_usage(
          socket.assigns.conversation_id,
          socket.assigns.assistant_message_id,
          Conversations.settings_model_or_default(socket.assigns.current_conversation),
          usage
        )
    end

    {:noreply,
     assign(socket,
       usage_totals: Conversations.usage_for_conversation(socket.assigns.conversation_id)
     )}
  end

  @impl true
  def handle_info({:stream_retrying, _attempt}, socket) do
    if is_integer(socket.assigns.assistant_message_id) do
      _ = Conversations.delete_message(socket.assigns.assistant_message_id)
    end

    messages = drop_last_assistant(socket.assigns.messages)

    errors =
      append_error(socket.assigns.errors, %{
        for_index: max(length(messages) - 1, 0),
        reason: "retry"
      })

    {:noreply,
     assign(socket,
       messages: messages,
       errors: errors,
       stream_buffer: "",
       assistant_message_id: nil,
       persist_dirty: false,
       persist_token_count: 0,
       persist_timer_ref: nil,
       response_parser_buffer: "",
       pending_cards: []
     )}
  end

  @impl true
  def handle_info(:stream_done, socket) do
    if socket.assigns.is_sending == false and socket.assigns.stream_task_pid == nil and
         socket.assigns.stream_buffer == "" do
      {:noreply, socket}
    else
      socket = ensure_socket_changed(socket)
      buffer = socket.assigns.stream_buffer

      {assistant_id, messages} =
        if is_integer(socket.assigns.assistant_message_id) or buffer != "" do
          {id, list} = ensure_assistant_row(socket, buffer)
          {id, upsert_assistant_message(list, id, buffer)}
        else
          socket = ensure_conversation(socket)

          {:ok, row} =
            Conversations.append_message(socket.assigns.conversation_id, :assistant, "")

          {row.id, socket.assigns.messages}
        end

      if is_integer(assistant_id) do
        Conversations.update_assistant_message(assistant_id, buffer)
      end

      render_messages =
        if buffer == "" do
          case List.last(messages) do
            %{role: :assistant, content: ""} -> List.delete_at(messages, -1)
            _ -> messages
          end
        else
          messages
        end

      pending =
        case socket.assigns.pending_cards do
          [] -> cards_from_content(buffer)
          existing -> existing
        end

      pending =
        if pending == [] do
          case List.last(render_messages) do
            %{role: :assistant, content: content} when is_binary(content) ->
              cards_from_content(content)

            _ ->
              []
          end
        else
          pending
        end

      render_messages =
        if pending != [] do
          case List.last(render_messages) do
            %{role: :assistant} = last ->
              List.replace_at(render_messages, -1, Map.put(last, :cards, pending))

            _ ->
              render_messages
          end
        else
          render_messages
        end

      {:noreply,
       assign(socket,
         messages: render_messages,
         is_sending: false,
         rag_status: :idle,
         stream_buffer: "",
         stream_task_pid: nil,
         assistant_message_id: nil,
         persist_dirty: false,
         persist_token_count: 0,
         persist_timer_ref: nil,
         response_parser_buffer: "",
         pending_cards: []
       )}
    end
  end

  @impl true
  def handle_info(:persist_assistant_buffer, socket) do
    socket = assign(socket, persist_timer_ref: nil)

    socket =
      if socket.assigns.is_sending && socket.assigns.persist_dirty &&
           is_integer(socket.assigns.assistant_message_id) do
        Conversations.update_assistant_message(
          socket.assigns.assistant_message_id,
          socket.assigns.stream_buffer
        )

        assign(socket, persist_dirty: false)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_stopped}, socket)
      when socket.assigns.is_sending == false and socket.assigns.stream_buffer == "" do
    {:noreply, socket}
  end

  def handle_info({:stream_stopped}, socket) do
    {:noreply,
     assign(socket,
       is_sending: false,
       rag_status: :idle,
       stream_buffer: "",
       stream_task_pid: nil,
       assistant_message_id: nil,
       persist_dirty: false,
       persist_token_count: 0,
       persist_timer_ref: nil,
       response_parser_buffer: "",
       pending_cards: []
     )}
  end

  @impl true
  def handle_info({:start_regenerate, llm_messages}, socket) do
    if socket.assigns.is_sending and socket.assigns.stream_task_pid == nil do
      pid = self()

      {:ok, task_pid} =
        Task.Supervisor.start_child(ChatApp.TaskSupervisor, fn ->
          try do
            openai_module().stream(llm_messages, pid, openai_stream_opts(socket))
          rescue
            e -> send(pid, {:stream_error, Exception.message(e)})
          end
        end)

      {:noreply, assign(socket, stream_task_pid: task_pid)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_error, _reason}, socket)
      when socket.assigns.is_sending == false and socket.assigns.stream_buffer == "" do
    {:noreply, socket}
  end

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
       rag_status: :idle,
       stream_buffer: "",
       stream_task_pid: nil,
       response_parser_buffer: "",
       pending_cards: []
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

  defp display_stream_error_reason(reason) when reason in [nil, ""] do
    "Unknown error"
  end

  defp display_stream_error_reason("retry") do
    "Retrying…"
  end

  defp display_stream_error_reason(reason) when is_binary(reason) do
    case reason do
      "HTTP 401" -> "HTTP 401 — OpenAI key missing/invalid (set OPENAI_API_KEY)"
      "HTTP 403" -> "HTTP 403 — OpenAI access forbidden"
      "HTTP 429" -> "HTTP 429 — OpenAI rate limited"
      "HTTP 500" -> "HTTP 500 — OpenAI server error"
      "HTTP 502" -> "HTTP 502 — OpenAI upstream error"
      "HTTP 503" -> "HTTP 503 — OpenAI temporarily unavailable"
      "HTTP 504" -> "HTTP 504 — OpenAI gateway timeout"
      other -> other
    end
  end

  defp display_stream_error_reason(reason), do: to_string(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <div id="prompt-bridge" phx-hook="PromptOnEvent" class="hidden"></div>
    <%!-- sidebar uses heroicon controls and emits data-sidebar-action-icon markers --%>
    <div data-page-shell class="h-screen overflow-y-auto overflow-x-hidden bg-background">
      <div class="flex min-h-screen flex-col bg-background">
        <div class="flex h-screen min-h-[42rem]">
          <SidebarComponent.render
            conversations={@conversations}
            current_id={@current_conversation_id || @conversation_id || 0}
            current_message_count={length(@messages)}
            collapsed={!@sidebar_open}
          />
          <section
            data-chat-surface="true"
            data-chat-surface-mode="embedded"
            data-rag-status={to_string(@rag_status)}
            class="relative grid h-full min-h-0 flex-1 grid-rows-[auto_minmax(0,1fr)_auto] bg-background"
          >
            <%= if @sidebar_open do %>
              <button
                type="button"
                phx-click="close_sidebar"
                data-mobile-backdrop="true"
                aria-label="Close sidebar"
                class="absolute inset-y-0 left-64 right-0 z-20 block h-full border-0 bg-black/40 p-0 md:hidden"
              >
              </button>
            <% end %>
            <header
              class="ui-chat-header-surface relative z-20 flex shrink-0 items-center justify-between gap-[var(--space-3)] border-b border-[var(--border-color)] px-[var(--space-6)] py-[var(--space-3)]"
              data-chat-surface-header="true"
              data-chat-surface-header-mode="embedded"
            >
              <div class="flex min-w-0 items-center gap-[var(--space-4)]">
                <button
                  type="button"
                  phx-click="toggle_sidebar"
                  aria-label={if @sidebar_open, do: "Collapse sidebar", else: "Expand sidebar"}
                  data-sidebar-toggle="true"
                  class="icon-btn focus-ring inline-flex size-10 shrink-0 text-foreground/70 hover:text-foreground"
                >
                  <.icon name="hero-bars-3" class="size-4" />
                </button>

                <button
                  type="button"
                  phx-click="new_conversation"
                  aria-label="Start a new conversation"
                  title="New conversation"
                  data-new-chat-trigger="true"
                  class="focus-ring group inline-flex size-10 shrink-0 items-center justify-center rounded-[0.95rem] border border-foreground/10 bg-background/70 text-foreground/72 shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:border-foreground/20 hover:bg-background hover:text-foreground hover:shadow-md active:translate-y-0 active:scale-95"
                >
                  <.icon
                    name="hero-pencil-square"
                    class="size-5 transition-transform duration-200 group-hover:scale-105"
                  />
                </button>
                <div class="flex min-w-0 flex-col gap-1.5">
                  <p class="brand-wordmark truncate">
                    Threadworks AI
                  </p>
                  <span class="brand-status-pill">Chat</span>
                </div>
              </div>

              <div class="ml-auto flex items-center gap-2">
                <button
                  type="button"
                  phx-click="toggle_settings"
                  aria-label="Conversation settings"
                  class="icon-btn focus-ring inline-flex size-10 shrink-0 text-foreground/70 hover:text-foreground"
                >
                  <.icon name="hero-cog-6-tooth" class="size-4" />
                </button>

                <div
                  role="group"
                  aria-label="Theme"
                  data-theme-source="js"
                  class="theme-toggle flex items-center rounded-full p-1"
                >
                  <button
                    type="button"
                    aria-label="Use editorial theme"
                    aria-pressed="true"
                    title="Editorial"
                    data-phx-theme="editorial"
                    phx-click={JS.dispatch("phx:set-theme")}
                    class="theme-toggle-button px-2 py-1 text-[0.625rem] font-semibold"
                  >
                    ED
                  </button>
                  <button
                    type="button"
                    aria-label="Use Swiss theme"
                    aria-pressed="false"
                    title="Swiss"
                    data-phx-theme="swiss"
                    phx-click={JS.dispatch("phx:set-theme")}
                    class="theme-toggle-button px-2 py-1 text-[0.625rem] font-semibold"
                  >
                    SW
                  </button>
                  <button
                    type="button"
                    aria-label="Use mid-century theme"
                    aria-pressed="false"
                    title="Mid-century"
                    data-phx-theme="mid-century"
                    phx-click={JS.dispatch("phx:set-theme")}
                    class="theme-toggle-button px-2 py-1 text-[0.625rem] font-semibold"
                  >
                    MC
                  </button>
                  <button
                    type="button"
                    aria-label="Use techno-brutalist theme"
                    aria-pressed="false"
                    title="Techno-brutalist"
                    data-phx-theme="techno-brutalist"
                    phx-click={JS.dispatch("phx:set-theme")}
                    class="theme-toggle-button px-2 py-1 text-[0.625rem] font-semibold"
                  >
                    TB
                  </button>
                </div>
              </div>
            </header>

            <%= if @settings_saved do %>
              <div data-settings-saved class="px-4 py-2 text-xs text-[color:var(--status-success)]">
                Settings saved
              </div>
            <% end %>

            <%= if @settings_error do %>
              <div class="px-4 py-2 text-xs text-[color:var(--status-error)]" role="alert">
                {@settings_error}
              </div>
            <% end %>

            <%= if @settings_open do %>
              <div
                data-settings-drawer
                class="border-b border-foreground/10 bg-background/70 px-4 py-3"
              >
                <form phx-submit="save_settings" novalidate class="grid gap-2 sm:grid-cols-3">
                  <label class="text-xs text-foreground/70">
                    Model
                    <select
                      name="settings[model]"
                      class="mt-1 w-full rounded border border-foreground/20 bg-transparent px-2 py-1 text-sm"
                    >
                      <option
                        value="gpt-4o-mini"
                        selected={
                          Conversations.settings_model_or_default(@current_conversation) ==
                            "gpt-4o-mini"
                        }
                      >
                        gpt-4o-mini
                      </option>
                      <option
                        value="gpt-4o"
                        selected={
                          Conversations.settings_model_or_default(@current_conversation) == "gpt-4o"
                        }
                      >
                        gpt-4o
                      </option>
                    </select>
                  </label>

                  <label class="text-xs text-foreground/70 sm:col-span-2">
                    System prompt <textarea
                      name="settings[system_prompt]"
                      rows="2"
                      class="mt-1 w-full rounded border border-foreground/20 bg-transparent px-2 py-1 text-sm"
                    ><%= @current_conversation && @current_conversation.system_prompt || "" %></textarea>
                  </label>

                  <label class="text-xs text-foreground/70">
                    Temperature
                    <input
                      type="number"
                      step="0.1"
                      min="0"
                      max="2"
                      name="settings[temperature]"
                      value={(@current_conversation && @current_conversation.temperature) || ""}
                      class="mt-1 w-full rounded border border-foreground/20 bg-transparent px-2 py-1 text-sm"
                    />
                  </label>

                  <div class="sm:col-span-2 flex items-end gap-2">
                    <button
                      type="submit"
                      class="rounded border border-foreground/20 px-3 py-1 text-xs font-semibold hover:bg-foreground/5"
                    >
                      Save
                    </button>
                  </div>
                </form>
              </div>
            <% end %>

            <%= if @current_conversation && is_binary(@current_conversation.system_prompt) &&
              String.trim(@current_conversation.system_prompt) != "" do %>
              <div data-system-prompt-present="true" class="hidden"></div>
            <% end %>

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
                data-chat-hero-state={to_string(@hero_state)}
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
                    <div
                      id={"hero-landing-#{@new_chat_nonce}"}
                      data-new-chat-landing={to_string(@new_chat_nonce > 0)}
                      class={[
                        "animate-in fade-in fill-mode-both",
                        if(@new_chat_nonce > 0,
                          do: "zoom-in-90 slide-in-from-top-12 duration-1000 ease-out",
                          else: "zoom-in-95 slide-in-from-top-4 duration-700 ease-out"
                        )
                      ]}
                    >
                      <.hero_intro />
                    </div>
                  <% else %>
                    <%= for msg <- @messages do %>
                      <.message_bubble message={msg} saved_item_ids={@saved_item_ids} />
                    <% end %>
                    <%= if @rag_status == :searching do %>
                      <div
                        data-rag-indicator="searching"
                        class="ui-chat-rag-searching px-4 py-2 text-sm text-foreground/60"
                      >
                        Searching catalog...
                      </div>
                    <% end %>
                    <%= for err <- @errors do %>
                      <div
                        class="ui-chat-message-error mx-auto max-w-[80%] rounded-lg border border-[color:color-mix(in_oklab,var(--status-error)_40%,transparent)] bg-[color:color-mix(in_oklab,var(--status-error)_10%,transparent)] px-3 py-2 text-xs text-foreground break-words"
                        data-chat-message-error="true"
                        data-role="assistant"
                      >
                        Error: {display_stream_error_reason(err.reason)}
                      </div>
                    <% end %>

                    <%= if @is_sending && @stream_buffer == "" do %>
                      <div
                        class="ui-chat-message-assistant rounded-[1.4rem] px-[var(--space-4)] py-[var(--space-3)] text-sm"
                        data-chat-message-role="assistant"
                      >
                        <div
                          data-typing-skeleton="true"
                          aria-label="Assistant is responding"
                          style="display:flex; align-items:center; gap:0.4rem; padding:0.25rem 0;"
                        >
                          <span style="display:inline-block; width:0.45rem; height:0.45rem; border-radius:999px; background:currentColor; opacity:0.3; animation:tw-typing-bounce 1.2s ease-in-out infinite; animation-delay:0ms;" />
                          <span style="display:inline-block; width:0.45rem; height:0.45rem; border-radius:999px; background:currentColor; opacity:0.3; animation:tw-typing-bounce 1.2s ease-in-out infinite; animation-delay:200ms;" />
                          <span style="display:inline-block; width:0.45rem; height:0.45rem; border-radius:999px; background:currentColor; opacity:0.3; animation:tw-typing-bounce 1.2s ease-in-out infinite; animation-delay:400ms;" />
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>

              <div
                id="scroll-cta-dock"
                class="ui-chat-scroll-cta-dock absolute left-0 right-0 z-10 flex justify-center pointer-events-none hidden"
                style={
              "bottom: calc(var(--chat-scroll-cta-offset) + var(--safe-area-inset-bottom))" <>
                if(@hero_state, do: "; display: none", else: "")
            }
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
              <%= if Phoenix.Flash.get(@flash, :info) do %>
                <div
                  class="mx-auto mb-2 w-full max-w-3xl rounded-lg border border-[color:color-mix(in_oklab,var(--status-success)_40%,transparent)] bg-[color:color-mix(in_oklab,var(--status-success)_10%,transparent)] px-3 py-2 text-xs text-foreground break-words"
                  role="alert"
                >
                  {Phoenix.Flash.get(@flash, :info)}
                </div>
              <% end %>

              <%= if Phoenix.Flash.get(@flash, :error) do %>
                <div
                  class="mx-auto mb-2 w-full max-w-3xl rounded-lg border border-[color:color-mix(in_oklab,var(--status-error)_40%,transparent)] bg-[color:color-mix(in_oklab,var(--status-error)_10%,transparent)] px-3 py-2 text-xs text-foreground break-words"
                  role="alert"
                >
                  {Phoenix.Flash.get(@flash, :error)}
                </div>
              <% end %>

              <%= if @rate_limit_error do %>
                <div
                  class="mx-auto mb-2 w-full max-w-3xl rounded-lg border border-[color:color-mix(in_oklab,var(--status-error)_40%,transparent)] bg-[color:color-mix(in_oklab,var(--status-error)_10%,transparent)] px-3 py-2 text-xs text-foreground break-words"
                  role="alert"
                >
                  {@rate_limit_error}
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
                      style="max-height: 192px; overflow-y: auto;"
                      disabled={@is_sending}
                      data-chat-composer-field="true"
                    ><%= @input %></textarea>

                    <%= if show_regenerate?(@messages, @is_sending) do %>
                      <div class="shrink-0 self-center ml-[var(--space-1)]">
                        <button
                          type="button"
                          phx-click="regenerate"
                          data-message-action="regenerate"
                          class="icon-btn focus-ring rounded-[var(--fva-shell-radius-control)] p-[var(--space-3)] transition-all active:scale-95 text-foreground/60 hover:text-foreground"
                          aria-label="Regenerate"
                        >
                          <.icon name="hero-arrow-path" class="size-4" />
                        </button>
                      </div>
                    <% end %>

                    <%= if @is_sending do %>
                      <div id="composer-action-stop" class="shrink-0 self-center mr-[var(--space-2)]">
                        <button
                          type="button"
                          phx-click="stop_generation"
                          class="ui-chat-send-button focus-ring rounded-[var(--fva-shell-radius-control)] p-[var(--space-3)] transition-all active:scale-95"
                          aria-label="Stop generation"
                        >
                          Stop
                        </button>
                      </div>
                    <% else %>
                      <div id="composer-action-send" class="shrink-0 self-center mr-[var(--space-2)]">
                        <button
                          type="submit"
                          class="ui-chat-send-button focus-ring rounded-[var(--fva-shell-radius-control)] p-[var(--space-3)] transition-all active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed"
                          aria-label="Send message"
                          data-chat-send-state={
                            if String.trim(@input) == "", do: "idle", else: "ready"
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
                      </div>
                    <% end %>
                  </form>

                </div>
              </div>
            </div>
          </section>
        </div>

        <footer
          id="site-footer"
          data-site-footer
          class="border-t border-foreground/10 bg-[color:color-mix(in_oklab,var(--background)_92%,black_8%)] px-[var(--space-6)] py-10"
        >
          <div class="mx-auto flex w-full max-w-6xl flex-col gap-8">
            <div class="grid gap-8 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)_minmax(18rem,0.9fr)]">
              <section class="space-y-3">
                <p class="text-[0.68rem] font-semibold uppercase tracking-[0.24em] text-foreground/42">
                  About Andrew
                </p>
                <p class="text-xl font-semibold tracking-tight text-foreground">
                  Andrew Gardner
                </p>
                <p class="max-w-[38rem] text-[0.98rem] leading-7 text-foreground/72">
                  Developer building practical software, AI-driven tools, and polished interfaces with an emphasis
                  on clarity, responsiveness, and strong product feel.
                </p>
              </section>

              <section class="space-y-3">
                <p class="text-[0.68rem] font-semibold uppercase tracking-[0.24em] text-foreground/42">
                  About The Project
                </p>
                <p class="text-xl font-semibold tracking-tight text-foreground">
                  Threadworks AI
                </p>
                <p class="text-[0.98rem] leading-7 text-foreground/72">
                  An NJIT IS322 final project built with Phoenix LiveView, combining streaming AI chat,
                  persistent conversations, and a configurable interface inside a compact single-page console.
                </p>
              </section>

              <nav aria-label="Andrew Gardner links" class="grid gap-3 sm:grid-cols-3 lg:grid-cols-1">
                <a
                  href="https://linkedin.com/in/andrew-gardner2026/"
                  target="_blank"
                  rel="noreferrer"
                  class="rounded-2xl border border-foreground/12 bg-background/55 px-4 py-4 transition-all duration-200 hover:-translate-y-0.5 hover:border-foreground/20 hover:bg-background/78 hover:shadow-sm"
                >
                  <span class="block text-[0.68rem] font-semibold uppercase tracking-[0.2em] text-foreground/45">
                    LinkedIn
                  </span>
                  <span class="mt-2 block text-sm font-semibold text-foreground">
                    Professional profile
                  </span>
                  <span class="mt-1 block text-xs leading-5 text-foreground/58">
                    Experience, background, and current work.
                  </span>
                </a>

                <a
                  href="https://github.com/atg25"
                  target="_blank"
                  rel="noreferrer"
                  class="rounded-2xl border border-foreground/12 bg-background/55 px-4 py-4 transition-all duration-200 hover:-translate-y-0.5 hover:border-foreground/20 hover:bg-background/78 hover:shadow-sm"
                >
                  <span class="block text-[0.68rem] font-semibold uppercase tracking-[0.2em] text-foreground/45">
                    GitHub
                  </span>
                  <span class="mt-2 block text-sm font-semibold text-foreground">
                    Code and repositories
                  </span>
                  <span class="mt-1 block text-xs leading-5 text-foreground/58">
                    Public projects, experiments, and build history.
                  </span>
                </a>

                <a
                  href="https://andrewg.vercel.app/"
                  target="_blank"
                  rel="noreferrer"
                  class="rounded-2xl border border-foreground/12 bg-background/55 px-4 py-4 transition-all duration-200 hover:-translate-y-0.5 hover:border-foreground/20 hover:bg-background/78 hover:shadow-sm"
                >
                  <span class="block text-[0.68rem] font-semibold uppercase tracking-[0.2em] text-foreground/45">
                    Portfolio
                  </span>
                  <span class="mt-2 block text-sm font-semibold text-foreground">
                    Selected work
                  </span>
                  <span class="mt-1 block text-xs leading-5 text-foreground/58">
                    Projects, resume, and contact details.
                  </span>
                </a>
              </nav>
            </div>

            <div class="flex flex-col gap-2 border-t border-foreground/10 pt-4 text-sm text-foreground/55 md:flex-row md:items-center md:justify-between">
              <p>
                Built by Andrew Gardner for NJIT IS322.
              </p>
              <p>
                Phoenix LiveView, SQLite persistence, and streaming AI responses.
              </p>
            </div>
          </div>
        </footer>
      </div>

      <button
        type="button"
        aria-label="Scroll to footer"
        onclick="document.querySelector('[data-page-shell]').scrollTo({top: document.getElementById('site-footer').offsetTop, behavior: 'smooth'})"
        class="fixed bottom-6 right-6 z-50 flex size-10 items-center justify-center rounded-full border border-foreground/20 bg-background/90 shadow-md backdrop-blur-sm transition-all hover:border-foreground/40 hover:shadow-lg active:scale-95"
      >
        <.icon name="hero-chevron-down" class="size-5 text-foreground/70" />
      </button>
    </div>
    """
  end

  defp openai_module do
    Application.get_env(:chat_app, :openai_module, ChatApp.OpenAI)
  end

  defp style_advisor_module do
    Application.get_env(:chat_app, :style_advisor_module, ChatApp.AI.StyleAdvisor)
  end

  defp start_streaming(prompt, socket) do
    pid = self()
    messages = Enum.map(socket.assigns.messages, &Map.take(&1, [:role, :content]))
    base_opts = openai_stream_opts(socket)

    # Merge the RAG-augmented prompt with any user-configured system prompt so
    # both are forwarded to OpenAI as a single system message. The augmented
    # prompt leads; the user's custom prompt (if any) is appended after a blank
    # line so it still takes effect.
    effective_system_prompt =
      case Map.get(base_opts, :system_prompt) do
        user_prompt when is_binary(user_prompt) and user_prompt != "" ->
          prompt <> "\n\n" <> user_prompt

        _ ->
          prompt
      end

    opts = Map.put(base_opts, :system_prompt, effective_system_prompt)

    Task.Supervisor.start_child(ChatApp.TaskSupervisor, fn ->
      try do
        openai_module().stream(messages, pid, opts)
      rescue
        e -> send(pid, {:stream_error, Exception.message(e)})
      end
    end)
  end

  defp message_bubble(%{message: %{role: :user}} = assigns) do
    ~H"""
    <div
      class="ui-chat-message-user ml-auto max-w-[80%] rounded-[1.4rem] px-[var(--space-4)] py-[var(--space-3)] text-[0.95rem] leading-relaxed font-medium"
      data-chat-message-bubble={true}
      data-chat-message-role="user"
      data-role="user"
    >
      {@message.content}
    </div>
    """
  end

  defp message_bubble(%{message: %{role: :assistant}} = assigns) do
    assigns = assign_new(assigns, :cards, fn -> Map.get(assigns.message, :cards, []) end)
    assigns = assign_new(assigns, :saved_item_ids, fn -> MapSet.new() end)
    assigns = assign(assigns, :demo_rag_debug?, ChatApp.Demo.enabled?())
    assigns = assign(assigns, :demo_rag_sources, demo_rag_sources(assigns.cards))

    ~H"""
    <div
      class="ui-chat-message-assistant group rounded-[1.4rem] px-[var(--space-4)] py-[var(--space-3)] text-[0.95rem] leading-relaxed"
      data-chat-message-bubble={true}
      data-chat-message-role="assistant"
      data-role="assistant"
    >
      <div class="prose prose-theme-inherit prose-sm max-w-none" data-assistant-markdown="true">
        {raw(Markdown.to_html(strip_html_comments(@message.content)))}
      </div>
      <%= for card <- @cards do %>
        <ChatAppWeb.ProductCard.product_card
          item={card.item}
          reason={card.reason}
          saved={MapSet.member?(@saved_item_ids, card.item.id)}
        />
      <% end %>
      <p
        :if={@demo_rag_debug? and @cards != []}
        class="mt-3 rounded-md border border-foreground/10 bg-foreground/[0.03] px-3 py-2 text-xs text-foreground/62"
        data-demo-rag-debug="true"
      >
        Retrieved from hybrid search: vector + keyword results over local catalog.
        <span class="font-medium">{length(@cards)} items</span>
        <span :if={@demo_rag_sources != ""}>from {@demo_rag_sources}</span>.
      </p>
      <div class="mt-2 flex gap-2 opacity-0 transition-opacity group-hover:opacity-100">
        <button
          type="button"
          phx-click={JS.dispatch("phx:copy", detail: %{text: @message.content})}
          data-message-action="copy"
          class="icon-btn rounded border border-foreground/20 text-xs text-foreground/70"
          aria-label="Copy"
        >
          <.icon name="hero-clipboard" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  defp demo_rag_sources(cards) do
    cards
    |> Enum.map(fn %{item: item} -> item.source end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(&source_label/1)
    |> Enum.join(", ")
  end

  defp source_label("ebay"), do: "eBay"
  defp source_label("depop"), do: "Depop"
  defp source_label("poshmark"), do: "Poshmark"
  defp source_label(source), do: source

  defp hero_intro(assigns) do
    ~H"""
    <div
      data-homepage-chat-intro="true"
      class="mx-auto flex w-full max-w-3xl flex-col items-center justify-center px-[var(--space-4)] text-center pb-[var(--hero-stack-body)]"
    >
      <div
        class="theme-label flex flex-wrap items-center justify-center gap-x-[var(--hero-badge-gap)] gap-y-[var(--phi-2)] text-[length:var(--hero-badge-font-size)] font-bold uppercase tracking-[0.22em]"
        style="margin-bottom: var(--hero-stack-kicker);"
      >
        <span data-homepage-service-chip="true" class="text-accent-interactive">Style</span>
        <span aria-hidden="true" class="text-foreground/30">/</span>
        <span data-homepage-service-chip="true" class="text-foreground/70">Search</span>
        <span aria-hidden="true" class="text-foreground/30">/</span>
        <span data-homepage-service-chip="true" class="text-foreground/70">Discover</span>
      </div>

      <h2
        class="theme-display text-foreground text-balance"
        style="max-width: var(--hero-title-max-width); font-size: var(--hero-title-font-size); line-height: var(--hero-title-line-height); letter-spacing: var(--tier-display-tracking); font-weight: 560;"
      >
        Your personal <em class="not-italic accent-underline">AI style</em> consultant
      </h2>

      <p
        class="theme-body text-foreground/74 measure-comfortable mx-auto"
        style="font-size: var(--hero-body-font-size); line-height: var(--hero-body-line-height); margin-top: var(--hero-stack-body);"
      >
        Describe your vibe, occasion, or budget. Get curated outfit ideas backed by real listings.
      </p>

      <div
        class="grid w-full gap-3 text-left sm:grid-cols-3"
        style="margin-top: var(--hero-stack-section);"
        data-homepage-proof-strip="true"
      >
        <%= for %{title: title, body: body} <- proof_points() do %>
          <div class="brand-proof-card" data-homepage-proof-card="true">
            <p class="text-[0.68rem] font-bold uppercase tracking-[0.16em] text-accent-interactive">
              {title}
            </p>
            <p class="text-[0.92rem] leading-[1.55] text-foreground/82">
              {body}
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
        title: "Style advice on demand",
        body: "Tell us your vibe, occasion, or budget and get personalized outfit recommendations instantly."
      },
      %{
        title: "Real listings, curated",
        body: "Every suggestion is backed by actual secondhand inventory from Depop, Poshmark, and eBay."
      },
      %{
        title: "Semantic search",
        body: "Natural-language queries surface the right pieces — no keyword guessing required."
      }
    ]
  end

  defp parse_hero_state(%{"hero_state" => value}) when value in ["false", "0"], do: false
  defp parse_hero_state(%{"hero_state" => value}) when value in ["true", "1"], do: true
  defp parse_hero_state(_params), do: true

  defp check_rate_limit(socket) do
    if Application.get_env(:chat_app, :disable_rate_limit, false) do
      :ok
    else
      case Hammer.check_rate(rate_key(socket), 60_000, 20) do
        {:allow, _count} ->
          :ok

        {:deny, _limit} ->
          message = "Slow down — you're sending messages too fast. Please wait a minute."

          {:rate_limited, assign(socket, rate_limit_error: message)}
      end
    end
  end

  @doc false
  def rate_limit_key_for_session(session_id) when is_binary(session_id) do
    "chatlive:#{session_id}"
  end

  defp rate_key(socket) do
    base = rate_limit_key_for_session(socket.assigns.session_id || "nil")
    instance = socket.id || Integer.to_string(:erlang.phash2(self()))
    base <> ":" <> instance
  end

  def drop_last_assistant(messages) do
    case List.last(messages) do
      %{role: :assistant} -> List.delete_at(messages, -1)
      _ -> messages
    end
  end

  defp show_regenerate?(messages, is_sending)
       when is_list(messages) and is_boolean(is_sending) do
    not is_sending and
      Enum.any?(messages, &(&1.role == :user)) and
      match?(%{role: :assistant}, List.last(messages))
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
      nil -> assign(socket, session_id: random_session_id())
      _ -> socket
    end
  end

  defp ensure_conversation(socket) do
    case socket.assigns.conversation_id do
      id when is_integer(id) ->
        case safe_get_conversation(id) do
          nil ->
            conversation = Conversations.get_or_create_active(socket.assigns.session_id)

            assign(socket,
              conversation_id: conversation.id,
              current_conversation_id: conversation.id,
              current_conversation: conversation,
              conversations: Conversations.list_conversations(socket.assigns.session_id)
            )

          _ ->
            socket
        end

      _ ->
        conversation = Conversations.get_or_create_active(socket.assigns.session_id)

        assign(socket,
          conversation_id: conversation.id,
          current_conversation_id: conversation.id,
          current_conversation: conversation,
          conversations: Conversations.list_conversations(socket.assigns.session_id)
        )
    end
  end

  defp safe_get_conversation(id) when is_integer(id) do
    Conversations.get_conversation!(id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp conversation_for_session(socket, id_param) do
    with {:ok, conversation_id} <- parse_conversation_id(id_param),
         conversation when not is_nil(conversation) <- safe_get_conversation(conversation_id),
         true <- conversation.session_id == socket.assigns.session_id do
      {:ok, conversation}
    else
      _ -> :error
    end
  end

  defp parse_conversation_id(id) when is_integer(id), do: {:ok, id}

  defp parse_conversation_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {conversation_id, ""} -> {:ok, conversation_id}
      _ -> :error
    end
  end

  defp parse_conversation_id(_id), do: :error

  defp openai_stream_opts(socket) do
    conversation = socket.assigns.current_conversation

    %{}
    |> maybe_put(:model, if(conversation, do: conversation.model, else: nil))
    |> maybe_put(:system_prompt, if(conversation, do: conversation.system_prompt, else: nil))
    |> maybe_put(:temperature, if(conversation, do: conversation.temperature, else: nil))
  end

  defp maybe_put(opts, _key, value) when value in [nil, ""], do: opts
  defp maybe_put(opts, key, value), do: Map.put(opts, key, value)

  defp settings_error_message(changeset) do
    case changeset.errors do
      [{field, _} | _] -> "#{field} is invalid"
      _ -> "settings are invalid"
    end
  end

  defp ensure_assistant_row(socket, current_buffer) do
    if is_integer(socket.assigns.assistant_message_id) do
      {socket.assigns.assistant_message_id, socket.assigns.messages}
    else
      {:ok, row} =
        Conversations.append_message(socket.assigns.conversation_id, :assistant, current_buffer)

      messages = upsert_assistant_message(socket.assigns.messages, row.id, current_buffer)
      {row.id, messages}
    end
  end

  defp upsert_assistant_message(messages, message_id, buffer) do
    upsert_assistant_message(messages, message_id, buffer, [])
  end

  defp upsert_assistant_message(messages, message_id, buffer, cards) do
    assistant = %{id: message_id, role: :assistant, content: buffer, cards: cards}

    case List.last(messages) do
      %{role: :assistant} -> List.replace_at(messages, -1, assistant)
      _ -> messages ++ [assistant]
    end
  end

  defp to_live_message(%{id: id, role: role, content: content}) do
    base = %{id: id, role: role, content: content}

    case role do
      :assistant ->
        cards = cards_from_content(content)
        if cards == [], do: base, else: Map.put(base, :cards, cards)

      _ ->
        base
    end
  end

  defp cards_from_content(content) when is_binary(content) do
    cards =
      case Jason.decode(content) do
        {:ok, %{"cards" => full_cards}} when is_list(full_cards) ->
          Enum.flat_map(full_cards, fn
            %{"item_id" => item_id, "reason" => reason} -> [%{item_id: item_id, reason: reason}]
            _ -> []
          end)

        _ ->
          {parsed_cards, _remaining_buffer} = ResponseParser.parse(content, "")
          parsed_cards
      end

    Enum.flat_map(cards, fn card ->
      case coerce_item_id(card.item_id) do
        :error ->
          []

        {:ok, item_id} ->
          case Clothing.get_item(item_id) do
            nil -> []
            item -> [%{item: item, reason: card.reason}]
          end
      end
    end)
  end

  defp cards_from_content(_), do: []

  defp coerce_item_id(item_id) when is_integer(item_id) and item_id > 0, do: {:ok, item_id}
  defp coerce_item_id(item_id) when is_integer(item_id), do: :error

  defp coerce_item_id(item_id) when is_binary(item_id) do
    case Integer.parse(item_id) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  defp coerce_item_id(_), do: :error

  defp configured_refresh_sources do
    config = Application.get_env(:chat_app, :scrape_queries, [])
    entries = List.wrap(config)

    source_entries =
      entries
      |> Enum.flat_map(&refresh_source_entry/1)
      |> Enum.uniq_by(& &1.source)

    if source_entries == [] do
      case Enum.find(entries, &valid_refresh_query?/1) do
        nil -> []
        query -> Enum.map(@refresh_sources, &%{source: &1, query: query})
      end
    else
      source_entries
    end
  end

  defp refresh_source_entry(%{"source" => source, "query" => query})
       when source in @refresh_sources and is_binary(query) and query != "" do
    [%{source: source, query: query}]
  end

  defp refresh_source_entry(%{source: source, query: query})
       when source in @refresh_sources and is_binary(query) and query != "" do
    [%{source: source, query: query}]
  end

  defp refresh_source_entry(%{"source" => source}) when source in @refresh_sources do
    [%{source: source, query: "vintage"}]
  end

  defp refresh_source_entry(%{source: source}) when source in @refresh_sources do
    [%{source: source, query: "vintage"}]
  end

  defp refresh_source_entry({source, query})
       when source in @refresh_sources and is_binary(query) and query != "" do
    [%{source: source, query: query}]
  end

  defp refresh_source_entry({source}) when source in @refresh_sources do
    [%{source: source, query: "vintage"}]
  end

  defp refresh_source_entry(source) when source in @refresh_sources do
    [%{source: source, query: "vintage"}]
  end

  defp refresh_source_entry(_entry), do: []

  defp valid_refresh_query?(query), do: is_binary(query) and String.trim(query) != ""

  defp enqueue_refresh_jobs(sources) do
    results =
      Enum.map(sources, fn %{source: source, query: query} ->
        %{"source" => source, "query" => query}
        |> ChatApp.ETL.Workers.ScrapeWorker.new()
        |> ChatApp.Repo.insert()
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_persist_timer(socket) do
    if socket.assigns.persist_timer_ref == nil do
      ref = Process.send_after(self(), :persist_assistant_buffer, 250)
      assign(socket, persist_timer_ref: ref, persist_dirty: true)
    else
      assign(socket, persist_dirty: true)
    end
  end

  defp bump_persist_token_count(socket) do
    assign(socket, persist_token_count: socket.assigns.persist_token_count + 1)
  end

  defp maybe_persist_by_token_threshold(socket) do
    if rem(socket.assigns.persist_token_count, 10) == 0 and
         is_integer(socket.assigns.assistant_message_id) do
      Conversations.update_assistant_message(
        socket.assigns.assistant_message_id,
        socket.assigns.stream_buffer
      )

      assign(socket, persist_dirty: false)
    else
      socket
    end
  end

  defp derive_session_id(socket, session) do
    connect_params = if connected?(socket), do: get_connect_params(socket) || %{}, else: %{}

    cond do
      is_binary(socket.assigns[:session_id]) ->
        socket.assigns.session_id

      is_binary(Map.get(connect_params, "session_id")) ->
        Map.get(connect_params, "session_id")

      is_map(session) and is_binary(Map.get(session, "session_id")) ->
        Map.get(session, "session_id")

      Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test ->
        "test-session"

      is_map(session) and is_binary(Map.get(session, "_csrf_token")) ->
        :crypto.hash(:sha256, Map.get(session, "_csrf_token")) |> Base.encode16(case: :lower)

      is_binary(Map.get(connect_params, "_csrf_token")) ->
        :crypto.hash(:sha256, Map.get(connect_params, "_csrf_token"))
        |> Base.encode16(case: :lower)

      true ->
        random_session_id()
    end
  end

  defp random_session_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16()

  defp parse_item_id(item_id) when is_binary(item_id) do
    case Integer.parse(item_id) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_item_id(item_id) when is_integer(item_id), do: {:ok, item_id}
  defp parse_item_id(_), do: :error

  defp fetch_item(item_id) do
    case Clothing.get_item(item_id) do
      nil -> :error
      item -> {:ok, item}
    end
  end

  defp latest_saved_item_scrape_at(user_id) do
    user_id
    |> Clothing.list_saved_items()
    |> Enum.map(fn saved -> saved.item && saved.item.last_scraped_at end)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end

  defp user_id(socket) do
    case Map.get(socket.assigns, :current_user) do
      %{id: id} when is_integer(id) -> id
      _ -> nil
    end
  end

  defp current_user_from_session(session, socket) do
    case Map.get(socket.assigns, :current_user) do
      nil ->
        case session do
          %{"user_token" => token} when is_binary(token) ->
            case Accounts.get_user_by_session_token(token) do
              {user, _authenticated_at} -> user
              user -> user
            end

          _ ->
            nil
        end

      user ->
        user
    end
  end

  defp ensure_socket_changed(%Phoenix.LiveView.Socket{assigns: assigns} = socket) do
    if Map.has_key?(assigns, :__changed__) do
      socket
    else
      %{socket | assigns: Map.put(assigns, :__changed__, %{})}
    end
  end

  defp strip_html_comments(text) when is_binary(text) do
    text
    |> String.replace(~r/<!--.*?-->/s, "")
    |> String.replace(~r/\{\"cards\":\s*\[.*?\]\}/s, "")
    |> String.trim()
  end

  defp cancel_stream(socket) do
    if is_pid(socket.assigns[:stream_task_pid]) and Process.alive?(socket.assigns.stream_task_pid) do
      Process.exit(socket.assigns.stream_task_pid, :shutdown)
    end

    if is_integer(socket.assigns[:assistant_message_id]) do
      Conversations.update_assistant_message(
        socket.assigns.assistant_message_id,
        socket.assigns.stream_buffer
      )
    end

    assign(socket,
      is_sending: false,
      rag_status: :idle,
      stream_buffer: "",
      stream_task_pid: nil,
      assistant_message_id: nil,
      persist_dirty: false,
      persist_token_count: 0,
      persist_timer_ref: nil,
      response_parser_buffer: "",
      pending_cards: []
    )
  end
end
