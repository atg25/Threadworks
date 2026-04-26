const ChatComposer = {
  mounted() {
    this.resize();
    this.el.addEventListener("input", () => this.resize());
    this.el.addEventListener("keydown", (e) => this.onKeyDown(e));
  },

  updated() {
    this.resize();
  },

  resize() {
    const el = this.el;
    el.style.height = "0px";
    const next = Math.min(el.scrollHeight, 192);
    el.style.height = `${next}px`;
    el.style.overflowY = el.scrollHeight > 192 ? "auto" : "hidden";
  },

  onKeyDown(e) {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      this.el.closest("form")?.requestSubmit();
    }
  },
};

export default ChatComposer;
