# Ticket 017 — JavaScript Testing Infrastructure

**Status**: 📋 Future Sprint
**Estimate**: 3h
**Priority**: 🟢 Low
**Dependencies**: #016 (modularized JavaScript structure)

---

## Problem Statement

During ticket #016, we discovered that Phoenix 1.8's default setup uses esbuild via an Elixir wrapper without Node.js dependencies. This makes adding JavaScript testing tools like Jest complex, as it requires bootstrapping an entire Node.js toolchain that doesn't currently exist in the project.

The lack of JavaScript tests means:
- Chart formatting logic can't be unit tested
- Module refactoring lacks safety net
- Regressions in date/number formatting go undetected
- Pure functions remain untested despite being easily testable

---

## Technical Context

Current setup:
- Phoenix 1.8.1 with esbuild 0.10 (Elixir wrapper)
- No package.json (only empty package-lock.json stub)
- No npm/Node.js toolchain configured
- esbuild configured in `config/config.exs` using Elixir
- TypeScript config exists but only for IDE support

---

## Proposed Approach

1. **Set up Node.js environment**
   - Create proper `package.json` with project metadata
   - Install esbuild as npm dependency (alongside Elixir version)
   - Configure npm scripts for building and testing

2. **Configure Jest**
   - Install Jest and required presets (`@babel/preset-env`, `jest-environment-jsdom`)
   - Add `jest-canvas-mock` for Canvas API mocking
   - Create `jest.config.js` with module resolution
   - Set up test directory structure (`assets/js/__tests__/`)

3. **Write initial test suite**
   - Test pure functions in `formatters.js`
   - Test data transformations in `datasets.js`
   - Test geometry calculations
   - Create test utilities for common mocks

4. **Integrate with build pipeline**
   - Add `npm test` to pre-commit hooks
   - Document test running in CLAUDE.md
   - Consider CI integration

---

## Acceptance Criteria

- [ ] `package.json` exists with Jest and dependencies
- [ ] `npm test` runs successfully
- [ ] At least 5 test files covering chart modules
- [ ] Test coverage for date/number formatting functions
- [ ] Documentation updated with testing instructions
- [ ] CI runs tests (if CI exists)

---

## Alternative Approaches Considered

1. **Use Wallaby/Hound** - Elixir-based browser testing, but doesn't test JS modules in isolation
2. **Skip testing** - Risky for complex chart logic
3. **Use simpler test runner** - Considered Vitest, but Jest has better Phoenix community support

---

## Risks

- **Dual build system complexity** - Managing both Elixir esbuild and npm
- **Version conflicts** - esbuild versions might differ
- **CI complexity** - Need Node.js in CI environment
- **Maintenance burden** - Another toolchain to maintain

---

## Notes

- Deferred from ticket #016 to keep sprint on track
- Consider whether full Jest setup is worth complexity
- Could start with simple Node.js test runner if Jest proves too heavy