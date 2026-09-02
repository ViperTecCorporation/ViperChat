# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification)
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios)
- **Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Local Docker Test Runtime**: neste checkout, rode testes Ruby pelo Docker local/localhost quando `ruby` ou `bundle` não estiverem disponíveis no host. Use o serviço `rails`, por exemplo:
  - `docker compose run --rm rails bundle exec rspec spec/path/to/file_spec.rb`
  - `docker compose run --rm rails bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
  - Se os containers já estiverem de pé, pode usar `docker compose exec rails bundle exec rspec spec/path/to/file_spec.rb`.
- **Frontend tests in Docker/container**: quando o host não conseguir rodar `pnpm test`/`vitest`, rode o teste direto no container de frontend/app disponível em localhost em vez de parar na falha do shell. Se o teste existente não cobre a alteração Vue/JS feita, crie um caso de teste focado para cobrir o componente, composable, store ou helper alterado antes de considerar a validação concluída.
- **Run Project**: `overmind start -f Procfile.dev`
- **Ruby Version**: Manage Ruby via `rbenv` and install the version listed in `.ruby-version` (e.g., `rbenv install $(cat .ruby-version)`)
- **rbenv setup**: Before running any `bundle` or `rspec` commands, init rbenv in your shell (`eval "$(rbenv init -)"`) so the correct Ruby/Bundler versions are used
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.)

## Mandatory Web, Android, and iOS Validation

- Treat ViperChat as one product delivered on Web, Android, and iOS. Any change to the shared frontend or to native behavior must be evaluated for all three platforms; do not consider the work complete after validating only the browser or only one native platform.
- For changes to the frontend bundled by Capacitor (including authentication, conversations, contacts, composer, attachments, media, notifications, routing, translations, and shared assets), always regenerate both native bundles before handoff:
  - Android: `pnpm native:sync:android`
  - iOS: `pnpm native:sync:ios`
- For Android-native changes, also rebuild Android. For iOS-native changes, also rebuild iOS. When a shared frontend, Capacitor plugin, dependency, or native configuration changes, rebuild both platforms.
- Before testing Android, run `adb devices`. If an emulator or physical device is listed as `device`, installing the current build and exercising the affected flow on that device is mandatory. Do not skip this because the user did not explicitly ask for installation or testing.
- When an iOS simulator, physical device, or reachable development Mac is available, synchronize, build, install/run, and exercise the affected flow there. For release-sensitive changes, validate a Release build or Archive whenever signing is available.
- A native smoke test must cover the changed behavior and its adjacent critical path, including login/session persistence, navigation, loading states, back/foreground transitions, permissions, uploads/media, and push notifications when relevant.
- If a platform, toolchain, emulator, or device is unavailable, state exactly what was and was not packaged or tested and why. Never report cross-platform validation as complete when one of the required targets was not actually exercised.
- Keep Web/PWA behavior independent and regression-tested when changing native wrappers, bridges, permissions, or notification handling. A native fix must not silently alter the browser/PWA contract.

## Mandatory Mobile Responsiveness

- Every new or changed frontend screen, modal, drawer, popover, composer, list, and form must be visually checked at mobile widths as well as desktop. At minimum, cover widths around 320, 360, 390, 412/430 px and a representative desktop viewport; test portrait and landscape when the flow can reasonably be used in both.
- Do not accept horizontal overflow, clipped borders or actions, content hidden under headers/navigation, disproportionate scaling, unexpected zoom, unreachable controls, or dialogs rendered outside the viewport.
- Account for iOS safe areas, rounded corners/notches, the software keyboard, and Android status/navigation bars. Fixed positioning and viewport-height layouts must include these constraints without consuming unnecessary application space.
- Prefer responsive Tailwind utilities and flexible sizing over fixed widths, fixed heights, absolute positioning, or device-specific pixel offsets. Any unavoidable exception must be justified by the component's layout contract.
- Validate long translations, dynamic content, scrolling, touch targets, keyboard open/close behavior, and initial rendering after login or app resume. A passing unit test does not replace this visual and interaction check.
- If a browser device emulator or connected native device is available, perform the responsive check there as part of the task without waiting for a separate reminder from the user.

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- Prefer the smallest production-ready change that solves the current problem.
- Build for the expected production path first. Do not add speculative guards, fallbacks, retries, or edge-case handling unless the caller can actually hit that case or production has proven it necessary.
- When an impossible or misconfigured state would indicate a setup/deployment bug, let it fail loudly instead of silently skipping behavior.
- For locked/internal configs that must exist in production, prefer direct reads (`find`, `find_by!`, required hash keys) over silent fallbacks.
- Do not add validation or response checks unless the code uses the result or the check changes behavior meaningfully.
- Prefer existing repo dependencies/client libraries over hand-rolled protocol code for auth, signing, parsing, or API plumbing.
- Avoid one-use private helpers unless they hide real complexity or make the main flow meaningfully easier to read.
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- In specs, avoid custom helper methods for setup/data. Prefer `let` values and direct per-example setup; only add a helper when it removes meaningful repeated complexity.
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Cherry-pick Integration Workflow

- Create a target branch only when the task asks for one or when the integration needs isolation; otherwise, use the current branch after confirming it is the intended destination.
- Fetch the source branch first, then inspect the exact commit range before applying it:
  - `git fetch origin develop`
  - `git log --oneline --reverse <start_commit>^..origin/develop`
- Cherry-pick commits in chronological order so conflicts stay small and authorship is preserved:
  - `git cherry-pick <commit_sha>`
  - For a range, iterate the ordered list from `git rev-list --reverse <start_commit>^..origin/develop`.
- Preserve original authorship when resolving conflicts. Do not squash imported commits unless explicitly requested; use normal `git cherry-pick --continue` so each imported commit keeps its original author.
- When a commit is only a release/version bump or would downgrade/overwrite ViperChat branding, skip it with `git cherry-pick --skip` and document why in the final summary or a follow-up adaptation commit.
- Resolve conflicts by keeping ViperChat branding and local behavior first, then re-apply the incoming feature changes around that local behavior. Pay special attention to files that mention app names, installation names, white-label copy, logos, package metadata, routes, and localized UI strings.
- After conflict resolution, search for leftover conflict markers and accidental comment syntax before continuing:
  - `rg -n '<<<<<<<|=======|>>>>>>>'`
  - For Vue/JS files, also check that conflict notes were not left as Ruby/shell comments.
- Add small adaptation commits after the cherry-pick sequence when needed, using a conventional commit message such as `fix(viperchat): clean up cherry-pick conflict leftovers`.
- Validate incrementally:
  - Run focused specs for files touched by conflict resolution.
  - Run `pnpm test` for frontend changes.
  - Run `bundle exec rspec` or `bundle exec rspec --fail-fast` for Ruby changes.
  - When the full suite is too slow, keep running `--fail-fast`, fix the first real failure, validate that spec directly, and repeat.
- If the main worktree is on a synced filesystem and Git status/diff starts failing with I/O errors, use a temporary local clone/worktree for heavy test runs and keep commits in the real branch focused and explicit. Do not leave `index.lock` files behind after interrupted Git commands.
- Stop local services started only for testing, such as per-worktree PostgreSQL or Redis, before handing the branch back.

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific

- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)
- **Uno premium features health check**:
  - Operational runbook: `docs/uno-premium-features-health-check.md`
  - Manual check: `bundle exec rails chatwoot:ops:check_uno_premium_features`
  - Scheduled check: `Internal::CheckUnoPremiumFeaturesJob` via `config/schedule.yml`

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.
