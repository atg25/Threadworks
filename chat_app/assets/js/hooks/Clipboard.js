let clipboardHandlersRegistered = false;

const copyText = (text) => {
  if (typeof text !== "string") return;
  if (!navigator.clipboard?.writeText) return;

  navigator.clipboard.writeText(text);
};

export const registerClipboardHandlers = () => {
  if (clipboardHandlersRegistered) return;
  if (typeof window === "undefined" || typeof document === "undefined") return;

  clipboardHandlersRegistered = true;

  window.addEventListener("phx:copy", (event) => {
    copyText(event?.detail?.text);
  });

  document.addEventListener("click", (event) => {
    const trigger = event.target?.closest?.(".ui-code-block-copy");
    if (!trigger) return;

    copyText(trigger.getAttribute("data-copy-text"));
  });
};

registerClipboardHandlers();
