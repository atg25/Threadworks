import re

with open('lib/chat_app/conversations.ex', 'r') as f:
    content = f.read()

# Fix the messes
content = content.replace("with_owned_repo(fn ->", "")
content = content.replace("do: Repo.get!(Conversation, id) end)", "do: Repo.get!(Conversation, id)")

# Now fix any remaining "end)"
content = content.replace("end)", "end")

with open('lib/chat_app/conversations.ex', 'w') as f:
    f.write(content)
