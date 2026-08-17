# Canonical Project Repositories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a captain-owned repository the canonical Treehouse anchor and guarded landing surface for every migrated primary or peer project.

**Architecture:** One sourceable project library parses the existing private Markdown registry and resolves project identity, canonical path, delivery mode, and autonomy posture. Existing task, synchronization, and landing scripts consume that resolver, while one Git update library gives synchronization and landing the same tracked-change and untracked-collision safety contract.

**Tech Stack:** Bash, Git, Treehouse, shell fixture tests.

**Spec:** `docs/superpowers/specs/2026-08-16-canonical-project-repositories-design.md`

## Global Constraints

- No managed-clone fallback is allowed for a migrated primary or peer project.
- Secondmate project clones and Orca worktree ownership remain explicit exceptions.
- No pull request is created by validated-main delivery.
- The existing temporary remote task branch remains allowed.
- Non-conflicting untracked files survive synchronization and landing.
- Existing managed clones are not deleted.
- Validation remains focused on the affected resolver, Treehouse identity, synchronization, and landing paths.

---

### Task 1: Canonical project registry resolver

**Files:**
- Create: `bin/fm-project-lib.sh`
- Create: `bin/fm-project-resolve.sh`
- Create: `bin/fm-project-path-set.sh`
- Modify: `bin/fm-project-mode.sh`
- Create: `tests/fm-project-path.test.sh`
- Modify: `bin/fm-test-run.sh`

**Interfaces:**
- Produces: `fm_project_resolve <project-id>` with `FM_PROJECT_ID`, `FM_PROJECT_PATH`, `FM_PROJECT_MODE`, and `FM_PROJECT_YOLO` outputs.
- Produces: `fm_project_common_dir <repository-path>` returning one physical absolute Git common directory.
- Produces: `fm-project-resolve.sh <project-id>` printing `id<TAB>path<TAB>mode<TAB>yolo`.
- Produces: `fm-project-path-set.sh <project-id> <absolute-repository-path> [--mode <mode>]` for an atomic private-registry migration.

- [ ] **Step 1: Write the failing resolver tests**

Create literal registry fixtures for a valid canonical path, missing path, relative path, non-root path, duplicate id, duplicate physical path, and a primary-home path inside `FM_HOME/projects`.
Assert that a secondmate-marked fixture retains its clone-path exception.

- [ ] **Step 2: Run the resolver test and verify the expected failures**

Run: `bash tests/fm-project-path.test.sh`
Expected: FAIL because the resolver and migration commands do not exist.

- [ ] **Step 3: Implement the minimal resolver and migration commands**

Parse top-level project entries plus one following indented `path:` field.
Canonicalize with `pwd -P`, require `git rev-parse --show-toplevel` to equal the path, reject duplicate physical identities, and make `fm-project-mode.sh` consume the same parsed mode and yolo result.
Make migration use a temporary file plus atomic rename and refuse while any live task metadata names the prior path.

- [ ] **Step 4: Run the focused resolver test**

Run: `bash tests/fm-project-path.test.sh`
Expected: PASS with every refusal leaving the registry byte-identical.

- [ ] **Step 5: Commit the resolver unit**

```bash
git add bin/fm-project-lib.sh bin/fm-project-resolve.sh bin/fm-project-path-set.sh bin/fm-project-mode.sh tests/fm-project-path.test.sh bin/fm-test-run.sh
git commit -m "feat(projects): resolve canonical repositories"
```

### Task 2: Route primary and peer work through the canonical repository

**Files:**
- Modify: `bin/fm-brief.sh`
- Modify: `bin/fm-spawn.sh`
- Modify: `bin/fm-fleet-sync.sh`
- Modify: `bin/fm-bootstrap.sh`
- Modify: `bin/fm-home-seed.sh`
- Modify: `tests/fm-brief.test.sh`
- Modify: `tests/fm-fleet-sync.test.sh`
- Modify: `tests/fm-spawn-worktree-settle.test.sh`
- Modify: `tests/fm-peer-home.test.sh`

**Interfaces:**
- Consumes: `fm_project_resolve` and `fm_project_common_dir` from Task 1.
- Produces: task metadata fields `project_id=`, `project=`, and `project_git_common=`.

- [ ] **Step 1: Add failing consumer tests**

Assert that briefing and synchronization use the registered external path while a retained `$FM_HOME/projects/<id>` clone is ignored.
Assert that a peer spawn records the canonical id, path, and Git common directory.
Assert that a Treehouse result with a different Git common directory is rejected before worker launch.
Assert that secondmate fixtures continue using their provisioned clones.

- [ ] **Step 2: Run only the affected tests and verify the failures**

Run: `bash tests/fm-brief.test.sh && bash tests/fm-fleet-sync.test.sh && bash tests/fm-spawn-worktree-settle.test.sh && bash tests/fm-peer-home.test.sh`
Expected: FAIL where scripts still infer `$FM_HOME/projects/<id>`.

- [ ] **Step 3: Replace path inference with the resolver**

Make bare project ids resolve centrally.
Make no-argument fleet synchronization enumerate registry ids instead of directory entries for primary and peer homes.
Preserve current clone enumeration for marked secondmate homes.
Make peer seeding write canonical path bindings rather than clone projects.
Add the Git common-directory identity assertion after Treehouse acquisition and before launch.

- [ ] **Step 4: Re-run the affected tests**

Run: `bash tests/fm-brief.test.sh && bash tests/fm-fleet-sync.test.sh && bash tests/fm-spawn-worktree-settle.test.sh && bash tests/fm-peer-home.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit the routing unit**

```bash
git add bin/fm-brief.sh bin/fm-spawn.sh bin/fm-fleet-sync.sh bin/fm-bootstrap.sh bin/fm-home-seed.sh tests/fm-brief.test.sh tests/fm-fleet-sync.test.sh tests/fm-spawn-worktree-settle.test.sh tests/fm-peer-home.test.sh
git commit -m "feat(projects): anchor work to canonical repositories"
```

### Task 3: Preserve non-conflicting untracked files during guarded updates

**Files:**
- Create: `bin/fm-git-update-lib.sh`
- Modify: `bin/fm-fleet-sync.sh`
- Modify: `bin/fm-merge-main.sh`
- Modify: `bin/fm-merge-local.sh`
- Modify: `tests/fm-fleet-sync.test.sh`
- Modify: `tests/fm-merge-main.test.sh`

**Interfaces:**
- Produces: `fm_git_require_clean_tracked <repository>`.
- Produces: `fm_git_preflight_tree_update <repository> <current-treeish> <target-treeish>` using a temporary index and `git read-tree -n -m -u`.
- Produces: `fm_git_verify_task_project_identity <meta-file>` for canonical-path and common-directory checks before landing.

- [ ] **Step 1: Add failing update tests**

In real local Git fixtures, prove that a non-conflicting `notes.md` survives synchronization and landing.
Prove that tracked, staged, unmerged, wrong-branch, divergence, remote-moved, exact untracked-file collision, and file-directory collision cases refuse without changing `HEAD`, index bytes, or working-file hashes.

- [ ] **Step 2: Run the focused update tests and verify the failures**

Run: `bash tests/fm-fleet-sync.test.sh && bash tests/fm-merge-main.test.sh`
Expected: FAIL because current scripts reject every untracked file and do not bind landing to registry identity.

- [ ] **Step 3: Implement the shared guarded-update helpers**

Separate tracked and index dirt from untracked files.
Initialize a temporary index from the current tree and use Git's dry-run read-tree update against the actual worktree to detect both exact and structural collisions.
Use the same helpers in synchronization and both local landing paths.
Before validated-main landing, re-resolve `project_id` and require the metadata path and common directory to match the current canonical repository.

- [ ] **Step 4: Re-run the focused update tests**

Run: `bash tests/fm-fleet-sync.test.sh && bash tests/fm-merge-main.test.sh`
Expected: PASS with untracked preservation and refusal invariants proven.

- [ ] **Step 5: Commit the guarded-update unit**

```bash
git add bin/fm-git-update-lib.sh bin/fm-fleet-sync.sh bin/fm-merge-main.sh bin/fm-merge-local.sh tests/fm-fleet-sync.test.sh tests/fm-merge-main.test.sh
git commit -m "fix(git): preserve safe untracked files on landing"
```

### Task 4: Update the operating contract and migrate Martyrdome

**Files:**
- Modify: `AGENTS.md`
- Modify: `.agents/skills/project-management/SKILL.md`
- Modify: `.agents/skills/secondmate-provisioning/SKILL.md`
- Modify: `docs/architecture.md`
- Modify: `docs/configuration.md`
- Modify: `docs/scripts.md`
- Modify: `docs/documentation-audiences.json`
- Modify outside the branch after code verification: `/Users/davidkol/fm-homes/martyrdome/data/projects.md`

**Interfaces:**
- Consumes: migration command from Task 1.
- Produces: one documented canonical repository model and an explicit secondmate exception.

- [ ] **Step 1: Update the single owners**

Replace primary and peer clone language with canonical repository language.
Keep exact parser and mutation mechanics in the resolver and migration script headers.
Keep AGENTS.md to trigger, safety, and ownership statements, with conditional detail in the project-management skill.

- [ ] **Step 2: Run maintained-document checks**

Run: `bin/fm-doc-audience-check.sh && git diff --check`
Expected: both commands exit zero.

- [ ] **Step 3: Commit the documentation unit**

```bash
git add AGENTS.md .agents/skills/project-management/SKILL.md .agents/skills/secondmate-provisioning/SKILL.md docs/architecture.md docs/configuration.md docs/scripts.md docs/documentation-audiences.json docs/firstmate-assessment.md docs/superpowers/specs/2026-08-16-canonical-project-repositories-design.md docs/superpowers/plans/2026-08-16-canonical-project-repositories.md
git commit -m "docs: define canonical project repository ownership"
```

- [ ] **Step 4: Migrate the private Martyrdome entry after the implementation is green**

Run: `FM_HOME=/Users/davidkol/fm-homes/martyrdome bin/fm-project-path-set.sh Martyrdome /Users/davidkol/projects/Godot/Martyrdome --mode validated-main`
Expected: the registry records the canonical path and validated-main mode while the old managed clone remains untouched.

### Task 5: Focused real workflow verification

**Files:**
- Modify only if evidence uncovers a bug: files owned by Tasks 1 through 4.

**Interfaces:**
- Consumes: the completed canonical resolver, Treehouse anchoring, and guarded landing path.
- Produces: direct evidence that the captain's approved workflow works without a pull request.

- [ ] **Step 1: Run the focused automated set**

Run: `bash tests/fm-project-path.test.sh && bash tests/fm-spawn-worktree-settle.test.sh && bash tests/fm-fleet-sync.test.sh && bash tests/fm-merge-main.test.sh && bin/fm-doc-audience-check.sh && bin/fm-lint.sh && git diff --check`
Expected: every command exits zero.

- [ ] **Step 2: Run one real Treehouse identity smoke**

Acquire a temporary Treehouse worktree from a scratch repository, verify distinct worktree roots and equal physical Git common directories, then return it through Treehouse.
Expected: identity checks pass and the scratch primary checkout remains unchanged.

- [ ] **Step 3: Verify the migrated Martyrdome binding read-only**

Run: `FM_HOME=/Users/davidkol/fm-homes/martyrdome bin/fm-project-resolve.sh Martyrdome`
Expected: one record containing the canonical Godot path and `validated-main` mode.

- [ ] **Step 4: Stop before shared landing and push**

Report the exact checks, commits, and private migration result.
Request the captain's separately informed validation, landing, and push approval required by the standing rule.
