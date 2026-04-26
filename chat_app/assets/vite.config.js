import { defineConfig } from "vite";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [tailwindcss()],
  build: {
    outDir: "../priv/static/assets",
    emptyOutDir: false,
    rollupOptions: {
      input: "css/app.css",
      output: {
        // Stable path — no content hash — so Phoenix can serve /assets/css/app.css.
        // The css/ prefix puts the output in assets/css/ matching Phoenix's static paths.
        assetFileNames: "css/[name][extname]",
      },
    },
  },
});
