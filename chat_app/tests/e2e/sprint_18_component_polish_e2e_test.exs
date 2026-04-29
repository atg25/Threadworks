defmodule ChatAppWeb.Sprint18ComponentPolishE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  feature "sidebar displays empty state illustration when zero conversations exist", %{session: session} do
    session =
      session
      |> execute_script("window.sessionStorage.setItem('chat_app:session_id', 'e2e-sprint18-empty')")
      |> visit("/")

    assert_has(session, Query.css("[data-sidebar-empty-state] svg"))
    assert_has(session, Query.text("No conversations yet"))
  end

  feature "assistant markdown inherits theme foreground color", %{session: session} do
    session =
      session
      |> visit("/")
      |> fill_in(Query.css("#chat-input"),
        with: "# Header\\n\\nParagraph with **bold** text for color inheritance."
      )
      |> send_keys([:enter])

    session = assert_has(session, Query.css("[data-assistant-markdown] h1"))

    session =
      execute_script(
        session,
        """
        (() => {
          const root = document.querySelector('[data-assistant-markdown]');
          const rootColor = root ? getComputedStyle(root).color : null;
          const inherited = ['h1', 'p', 'strong'].every((selector) => {
            const node = root?.querySelector(selector);
            return node && getComputedStyle(node).color === rootColor;
          });

          document.body.dataset.proseColorInherited = inherited ? 'true' : 'false';
        })();
        """
      )

    assert_has(session, Query.css("body[data-prose-color-inherited='true']"))
  end

  feature "assistant markdown keeps inline and block code visually distinct", %{session: session} do
    session =
      session
      |> visit("/")
      |> fill_in(Query.css("#chat-input"), with: "check code backgrounds")
      |> send_keys([:enter])

    session = assert_has(session, Query.css("[data-assistant-markdown] p code"))
    session = assert_has(session, Query.css("[data-assistant-markdown] pre"))

    session =
      execute_script(
        session,
        """
        (() => {
          const root = document.querySelector('[data-assistant-markdown]');
          const paragraph = root?.querySelector('p');
          const inlineCode = root?.querySelector('p code');
          const pre = root?.querySelector('pre');

          const paragraphColor = paragraph ? getComputedStyle(paragraph).color : null;
          const inlineCodeStyle = inlineCode ? getComputedStyle(inlineCode) : null;
          const preStyle = pre ? getComputedStyle(pre) : null;

          const inlineReady = inlineCodeStyle && inlineCodeStyle.backgroundColor !== 'rgba(0, 0, 0, 0)' && inlineCodeStyle.color !== paragraphColor;
          const preReady = preStyle && preStyle.backgroundColor !== 'rgba(0, 0, 0, 0)' && preStyle.color !== paragraphColor;

          document.body.dataset.codeBackgroundsDistinct = inlineReady && preReady ? 'true' : 'false';
        })();
        """
      )

    assert_has(session, Query.css("body[data-code-backgrounds-distinct='true']"))
  end

  feature "typing indicator renders as a 3-line skeleton block", %{session: session} do
    session =
      session
      |> visit("/")
      |> fill_in(Query.css("#chat-input"), with: "trigger delayed stream")
      |> send_keys([:enter])

    assert_has(session, Query.css("[data-typing-skeleton]"))
    assert_has(session, Query.css("[data-typing-skeleton-line='1']"))
    assert_has(session, Query.css("[data-typing-skeleton-line='2']"))
    assert_has(session, Query.css("[data-typing-skeleton-line='3']"))
    refute_has(session, Query.css("[data-typing-dots]"))
  end
end
