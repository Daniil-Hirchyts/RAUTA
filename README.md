# Gym Lib

A deliberately simple, mobile-first exercise finder. Move through three focused stages: choose muscles, select equipment or reuse a saved preset, then browse visual matching exercises from the bundled dataset.

## Local development

```bash
bun install
bun run dev
```

Run the full validation suite with:

```bash
bun run typecheck
bun run lint
bun run test
bun run build
```

Gym Lib uses React, TypeScript, Vite, Tailwind CSS, shadcn/ui, and Zustand. It has no backend and stores filter selections and equipment presets only in the browser's local storage.

See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) for dataset and anatomy-map attribution.
