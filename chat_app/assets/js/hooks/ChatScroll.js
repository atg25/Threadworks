const ChatScroll = {
  mounted() {
    this.isAtBottom = true;
    this.el.addEventListener("scroll", () => this.onScroll(), {
      passive: true,
    });

    const btn = document.getElementById("scroll-to-bottom");
    if (btn) btn.addEventListener("click", () => this.scrollToBottom());

    this._updateDockVisibility();
    this.scrollToBottom();
  },

  updated() {
    if (this.isAtBottom) this.scrollToBottom();
  },

  onScroll() {
    const { scrollTop, scrollHeight, clientHeight } = this.el;
    this.isAtBottom = scrollHeight - scrollTop - clientHeight < 40;
    this.pushEvent("scroll_position", { at_bottom: this.isAtBottom });

    this._updateDockVisibility();
  },

  _updateDockVisibility() {
    const dock = document.getElementById("scroll-cta-dock");
    if (dock) dock.classList.toggle("hidden", this.isAtBottom);
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

export default ChatScroll;
