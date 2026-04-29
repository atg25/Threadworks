const PromptOnEvent = {
  mounted() {
    this.handleEvent("prompt_rename", ({ id, current }) => {
      const next = window.prompt("Rename conversation:", current || "");
      if (next != null && next.trim() !== "") {
        this.pushEvent("rename_conversation", { id, title: next.trim() });
      }
    });
  },
};

export default PromptOnEvent;
