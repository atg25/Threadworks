defmodule ChatAppWeb.SidebarComponent do
  use Phoenix.Component
  import ChatAppWeb.CoreComponents, only: [icon: 1]

  attr :conversations, :list, required: true
  attr :current_id, :integer, required: true
  attr :current_message_count, :integer, default: 0
  attr :collapsed, :boolean, default: false

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :show_empty_state,
        show_empty_state?(assigns.conversations, assigns.current_message_count)
      )

    ~H"""
    <aside
      id="chat-sidebar"
      data-sidebar-collapsed={to_string(@collapsed)}
      aria-hidden={to_string(@collapsed)}
      style={if @collapsed, do: "width: 0px;", else: "width: 16rem;"}
      class={[
        "ui-chat-sidebar absolute inset-y-0 left-0 z-30 flex h-full shrink-0 flex-col border-r border-foreground/10 bg-background/40 transition-[width,opacity,border-color] duration-200 ease-out md:relative md:inset-auto md:z-auto md:w-64",
        if(@collapsed,
          do: "overflow-hidden border-r-transparent opacity-0 pointer-events-none",
          else: "overflow-hidden opacity-100 pointer-events-auto"
        )
      ]}
    >
      <%= unless @collapsed do %>
        <div class="p-3">
          <button
            type="button"
            phx-click="new_conversation"
            data-sidebar-action="new_conversation"
            class="w-full rounded-md border border-foreground/20 px-3 py-2 text-sm hover:bg-foreground/5 inline-flex items-center justify-center gap-2"
          >
            <.icon name="hero-plus" class="size-4" data-sidebar-action-icon="plus" />
            <span>New conversation</span>
          </button>
        </div>

        <%= if @show_empty_state do %>
          <div
            data-sidebar-empty-state="true"
            class="mx-3 mb-2 rounded-md border border-dashed border-foreground/20 p-3 text-xs text-foreground/65"
          >
            <div class="mb-2 inline-flex items-center justify-center rounded-md bg-foreground/5 p-2">
              <svg
                viewBox="0 0 24 24"
                class="size-4"
                fill="none"
                stroke="currentColor"
                stroke-width="1.8"
              >
                <path d="M4 6h16M4 12h10M4 18h7" stroke-linecap="round" />
              </svg>
            </div>
            <p>No conversations yet</p>
          </div>
        <% end %>

        <ul class="flex-1 overflow-y-auto p-2">
          <%= for conv <- visible_conversations(@conversations, @show_empty_state) do %>
            <li
              class="group flex items-center justify-between gap-2 rounded-md px-2 py-1.5 hover:bg-foreground/5"
              data-conversation-id={conv.id}
            >
              <button
                type="button"
                phx-click="switch_conversation"
                phx-value-id={conv.id}
                class={
                  "flex-1 truncate text-left text-sm " <>
                    if(conv.id == @current_id, do: "font-semibold", else: "text-foreground/70")
                }
              >
                {conv.title || "Untitled"}
              </button>

              <div class="flex gap-1">
                <button
                  type="button"
                  phx-click="rename_conversation_prompt"
                  phx-value-id={conv.id}
                  class="icon-btn text-xs text-foreground/50 hover:text-foreground"
                  aria-label="Rename"
                  data-sidebar-action="rename_conversation"
                >
                  <.icon name="hero-pencil-square" class="size-4" data-sidebar-action-icon="rename" />
                </button>
                <button
                  type="button"
                  phx-click="delete_conversation"
                  phx-value-id={conv.id}
                  data-confirm="Delete this conversation?"
                  class="icon-btn text-xs text-foreground/50 hover:text-[color:var(--status-error)]"
                  aria-label="Delete"
                  data-sidebar-action="delete_conversation"
                >
                  <.icon name="hero-trash" class="size-4" data-sidebar-action-icon="delete" />
                </button>
              </div>
            </li>
          <% end %>
        </ul>
      <% end %>
    </aside>
    """
  end

  defp visible_conversations(_conversations, true), do: []
  defp visible_conversations(conversations, false), do: conversations

  defp show_empty_state?([], _current_message_count), do: true

  defp show_empty_state?([conv], 0) do
    conv.title in [nil, "New conversation"]
  end

  defp show_empty_state?(_conversations, _current_message_count), do: false
end
