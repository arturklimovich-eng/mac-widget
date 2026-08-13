# Project Standards

## Git Standards

- Git flow is the standard git workflow for this project

- Base branch standard names are:
  - Production branch: main
  - Development branch: develop
  - Feature branches: feature/\*
  - Bugfix branches: bugfix/\*
  - Release branches: release/\*
  - Hotfix branches: hotfix/\*
  - Support branches: support/\*

- Individual branch names follow the pattern: <base>/<issue_id>-<issue-short-desc>
  where <base> is one of the standard base branch names from git flow.

- Develompent must only occur out of Feature and Bugfix branches,

- Release, Hotfix, Bugfix, and Support branches are Idempotent branches meant to track the state of the codebase at a point-in-time

- All commits must follow the conventional commits standard: [Standard Link](https://www.conventionalcommits.org/en/v1.0.0/)

- Git commits should be focused on a single fix or work item, large, cross functional commits are strongly discouraged.

## Merging

- **Squash Merge** From feature, or bugfix branches into Develop.
- **Merge** From Develop into Master, and master into release, hotfix, or support

## What makes a good commit

- **Keep commits focused** - In general, a commit should have one primary change it is effecting in the codebase.

- **Consistency** – When starting on an existing codebase, the best course of action is typically to follow the established patterns.

- **Commit early and often** – I am a huge proponent of frequent, small commits. It’s hard to keep commits focused or write a good commit message if your commit comprises several hours of work.

- **Push commits early and often** – Commits should be pushed every day, at an absolute minimum. Ideally you’re pushing after every commit, multiple times a day.

- **Don’t mix logic and formatting changes** – It makes it so hard to see what is relevant to the behavior change vs what is noise.

- **Don’t mix logic and refactoring changes** – Just like formatting changes, it can greatly complicate things if you need to track down a bug later. Refactoring is technically meant to change the internal structure of code without changing its external behavior. Combining those concerns is definitely not a focused commit.

- **Don’t mix logic and dependency changes** – Isolate library and dependency upgrades in a separate commit or whole other branch.
