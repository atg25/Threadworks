content = File.read!("lib/chat_app/conversations.ex")
content = String.replace(content, ~r/\s*end\s*end/, "\n  end")
File.write!("lib/chat_app/conversations.ex", content)
