# Contributing

Read these rules before opening a pull request.

## 1. AI Code and Responsibility
You can use AI/LLM tools to write code, documentation, or anything related to this product. You own every single bug it creates. If the code corrupts memory, leaks resources or crashes, you take full responsibility. Know every line you submit.

## 2. Sign Off Your Commits
Sign every commit using the `-s` flag:

```sh
git commit -s -m "example commit with signed off"
```

PRs with unsigned commits will be rejected.

## 3. Test Everything Before Submitting
Build the project. Run your tests. Confirm your changes work and verify that you did not break other parts of the codebase. Submitting code that does not build, contains obvious bugs or lacks testing gets your pull request closed on the spot.

## 4. Describe Your Changes
Write a clear description for your pull request. State what was changed, why you changed it and how to test it. Empty pull request descriptions will be closed.

## 5. Keep Pull Requests Small
One pull request covers one bug fix, one feature or one cleanup task. Keep diffs focused. Do not drop massive PRs that rewrite the entire program at once.

## 6. License
All contributions fall under the GNU General Public License v2 (GPL-2.0). By submitting code, you license your work under GPL-2.0.