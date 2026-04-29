import { describe, expect, test } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const chatLivePath = resolve(process.cwd(), "../lib/chat_app_web/live/chat_live.ex");
const sidebarPath = resolve(process.cwd(), "../lib/chat_app_web/live/sidebar_component.ex");
const chatCssPath = resolve(process.cwd(), "css/chat.css");

describe("SP-03-19B mobile drawer hooks contract", () => {
  test("sidebar behaves as off-canvas drawer on mobile viewports", () => {
    const sidebarComponent = readFileSync(sidebarPath, "utf8");

    expect(sidebarComponent).toContain("absolute");
    expect(sidebarComponent).toContain("z-30");
    expect(sidebarComponent).toContain("md:relative");
  });

  test("mobile CSS only hides the collapsed sidebar", () => {
    const chatCss = readFileSync(chatCssPath, "utf8");

    expect(chatCss).not.toMatch(/@media\s*\(max-width:\s*767px\)\s*\{\s*\.ui-chat-sidebar\s*\{\s*display:\s*none;/s);
    expect(chatCss).toContain('.ui-chat-sidebar[data-sidebar-collapsed="true"]');
    expect(chatCss).toContain('.ui-chat-sidebar[data-sidebar-collapsed="false"]');
    expect(chatCss).toContain("display: flex;");
  });

  test("clicking the mobile backdrop overlay closes the sidebar", () => {
    const chatLive = readFileSync(chatLivePath, "utf8");

    expect(chatLive).toContain("data-mobile-backdrop");
    expect(chatLive).toContain("close_sidebar");
    expect(chatLive).toContain("md:hidden");
  });
});
