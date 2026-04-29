const ChatScroll = {
  mounted() {
    this.isAtBottom = true;
    this.hasMovedUp = false;
    this.revealArmed = false;
    this.lastScrollTop = this.el.scrollTop;
    this.dock = null;
    this.button = null;

    this._onScroll = (event) => this.onScroll(event);
    this._onClick = () => this.scrollToBottom();
    this._ensureDockRefs();

    document.querySelectorAll("#scroll-cta-dock").forEach((dock) => {
      if (dock !== this.dock) dock.classList.add("hidden");
    });

    if (this.dock) this.dock.classList.add("hidden");

    this._updateDockVisibility();
    this._rafId = requestAnimationFrame(() => {
      this.scrollToBottom();
      this.el.addEventListener("scroll", this._onScroll, { passive: true });

      this._rafId = requestAnimationFrame(() => {
        this.lastScrollTop = this.el.scrollTop;
        this.revealArmed = true;
      });
    });
  },

  updated() {
    if (this._rafId) cancelAnimationFrame(this._rafId);
    this._ensureDockRefs();

    this._rafId = requestAnimationFrame(() => {
      if (this.isAtBottom) this.scrollToBottom();
      this._updateDockVisibility();
    });
  },

  destroyed() {
    if (this._rafId) cancelAnimationFrame(this._rafId);
    if (this._onScroll) this.el.removeEventListener("scroll", this._onScroll);
    if (this.button && this._onClick)
      this.button.removeEventListener("click", this._onClick);
  },

  onScroll(event) {
    if (!this.revealArmed) {
      this.isAtBottom = true;
      this.pushEvent("scroll_position", { at_bottom: true });
      this._updateDockVisibility();
      this.lastScrollTop = this.el.scrollTop;
      return;
    }

    const { scrollTop, scrollHeight, clientHeight } = this.el;
    const hasOverflow = scrollHeight > clientHeight + 1;
    const computedAtBottom =
      !hasOverflow || scrollHeight - scrollTop - clientHeight < 40;
    const movedUp = scrollTop < this.lastScrollTop - 1;
    const syntheticReveal =
      event && event.isTrusted === false && hasOverflow && scrollTop <= 1;
    this.hasMovedUp = this.hasMovedUp || movedUp || syntheticReveal;

    this.isAtBottom = this.hasMovedUp ? computedAtBottom : true;
    this.pushEvent("scroll_position", { at_bottom: this.isAtBottom });
    this.lastScrollTop = scrollTop;

    this._updateDockVisibility();
  },

  _updateDockVisibility() {
    const dock = this.dock;
    if (!dock) return;

    const isHeroState =
      this.el.dataset.chatHeroState === "true" ||
      document.querySelector("[data-homepage-chat-intro]") !== null ||
      this.el.querySelector("[data-message-list-state='hero']") !== null;
    if (isHeroState) {
      this.hasMovedUp = false;
      this.isAtBottom = true;
      dock.classList.add("hidden");
      return;
    }

    if (!this.hasMovedUp) {
      dock.classList.add("hidden");
      return;
    }

    const { scrollHeight, clientHeight } = this.el;
    const hasOverflow = scrollHeight > clientHeight + 1;
    dock.classList.toggle("hidden", this.isAtBottom || !hasOverflow);
  },

  _ensureDockRefs() {
    const nextDock =
      this.el.parentElement?.querySelector("#scroll-cta-dock") || null;
    const nextButton = nextDock?.querySelector("#scroll-to-bottom") || null;

    if (this.button && this.button !== nextButton) {
      this.button.removeEventListener("click", this._onClick);
    }

    this.dock = nextDock;
    this.button = nextButton;

    if (this.button) {
      this.button.removeEventListener("click", this._onClick);
      this.button.addEventListener("click", this._onClick);
    }
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
    this.lastScrollTop = this.el.scrollTop;
    this.isAtBottom = true;
    this.pushEvent("scroll_position", { at_bottom: true });
    this._updateDockVisibility();
  },
};

export default ChatScroll;
