# Repository Guidelines

## Project Structure & Module Organization

This workspace currently contains no application source, tests, assets, or dependency manifests. No framework or language is established yet. The `.agents/`, `.codex/`, and `.aws/` directories are environment configuration locations; do not use them for application code or commit credentials from them.

When adding the initial implementation, establish clear directories such as `src/` for application code, `tests/` for automated tests, and `assets/` for static resources. Organize modules by feature and document the actual layout in a root `README.md`.

## Build, Test, and Development Commands

No build, test, or local development commands are currently configured. Add reproducible commands alongside the first implementation and document their prerequisites in `README.md`. Prefer a single documented entry point for each task: dependency installation, local development, testing, linting, and production builds. Do not assume commands such as `npm test` work until the corresponding configuration exists.

## Coding Style & Naming Conventions

Follow the conventions of the language selected for the implementation. Use consistent indentation within each language and configure its formatter and linter before introducing substantial code. Choose descriptive names, keep modules focused, and match filenames to their primary feature or exported component. Avoid unrelated formatting changes in functional patches.

## Testing Guidelines

No testing framework or coverage threshold is configured. Select an appropriate framework when introducing executable code. Keep tests in `tests/` or a clearly documented colocated layout, and use descriptive names identifying the behavior under test. Include regression tests for bug fixes and cover meaningful success and failure paths. Document the exact test command before requesting review.

## Commit & Pull Request Guidelines

Git history is unavailable in this workspace, so no existing commit convention can be verified. Use concise, imperative commit subjects, such as `Add recipe storage`, and keep each commit focused.

Pull requests should explain the change, link relevant issues, and report validation commands and results. Include screenshots for visible interface changes. Call out configuration changes, new dependencies, and any checks that could not be run.
