# Vendored dependencies

All files below are ordinary source files, not Git submodules. Builds require no network
dependency resolution. The selected upstream files are unmodified.

| Directory | Upstream release | Commit | Included files |
| --- | --- | --- | --- |
| `lib/openzeppelin-contracts` | [OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | ERC20, its four transitive imports, and MIT license |
| `lib/forge-std` | [forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | `src/` and MIT/Apache-2.0 licenses; used only by tests |

[`dependencies.lock.json`](dependencies.lock.json) records the resolved commit, SHA-256
of the downloaded GitHub source archive, and SHA-256 of every included file. Sources
were extracted from the commit-pinned archives, selecting only the paths above. No
upstream hooks, build configuration, generated binaries, or package installer is needed.

The exact source archives are available at:

- [OpenZeppelin Contracts source](https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/dbb6104ce834628e473d2173bbc9d47f81a9eec3)
- [forge-std source](https://codeload.github.com/foundry-rs/forge-std/tar.gz/77041d2ce690e692d6e03cc812b57d1ddaa4d505)

License texts are included at `lib/openzeppelin-contracts/LICENSE`,
`lib/forge-std/LICENSE-MIT`, and `lib/forge-std/LICENSE-APACHE`.
