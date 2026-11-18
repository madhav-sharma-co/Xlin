<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Source management (Xlin Source Pin)

Xlin Kernel is built from an unmodified upstream **Linux kernel** release. This document explains how that source is pinned, fetched and verified. The source itself is never stored in this repository.

## The Xlin Source Pin

`upstream/UPSTREAM.lock` records exactly which upstream source Xlin uses. It is a plain `key=value` file that scripts parse as data (it is never executed). The pin currently is:

| Field | Value |
|---|---|
| Source project | Linux kernel (stable tree, longterm series 6.18) |
| Version | `6.18.64` |
| Release tag | `v6.18.64` (annotated, signed) |
| Tag object | `084d543c1adb9b29550aae1cce61378982f94d1d` |
| Commit | `fd7cfd39c88596fec816639ad83cbf3e9d316372` |
| Official repository | `https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git` |
| Fallback mirror | `https://github.com/gregkh/linux.git` |
| Release signer | Greg Kroah-Hartman, key `647F28654894E3BD457199BE38DBBDC86092693E` |

Only the full 40-character commit is accepted as the pin; partial hashes are rejected.

### What was verified when the pin was established (2026-11-17 and 2026-11-18)

- The tag `v6.18.64` exists and is an annotated tag; it points to commit `fd7cfd39c88596fec816639ad83cbf3e9d316372` (read from the real tag object).
- The `Makefile` at that commit declares `VERSION=6`, `PATCHLEVEL=18`, `SUBLEVEL=64`, empty `EXTRAVERSION`.
- The tag's signature packet names issuer key `647F28654894E3BD457199BE38DBBDC86092693E`. kernel.org's signature page (<https://www.kernel.org/signature.html>) lists the same fingerprint for Greg Kroah-Hartman.
- kernel.org's front page lists 6.18.64 (2026-11-17) as the current longterm 6.18 release; the 6.18 series is projected to reach end of life in Dec 2028.

### What was not verified at that time

The authoring environment could not reach `git.kernel.org` or kernel.org's key service. Therefore the following were **not** performed then and are performed by `scripts/xlin-verify` instead (and by CI):

- cross-checking the tag against the official repository;
- cryptographic verification of the tag signature.

## Commands

    scripts/xlin-fetch                 # retrieve the pinned source into upstream/src/linux
    scripts/xlin-verify                # verify it and report each check
    scripts/xlin-verify --strict       # also fail if any check had to be skipped (CI mode)
    tests/negative.sh                  # check that wrong pins and bad input are rejected

In the first real run the Git data was about 278 MB and the checked-out tree about 1.7 GB (2 GB in total). `upstream/src/` is ignored by Git.

### Xlin Fetch

- Reads the lock file; fetches the **tag**, never a branch such as `master`.
- Tries the official repository first and uses the mirror only if the official one cannot be reached. A source that does not match the pinned hashes is rejected, removed from consideration, and never triggers a fallback.
- Refuses to touch an existing directory it did not create; safe to run repeatedly (a second run reports "Already fetched").
- Retries network failures three times, then fails with a clear message and accepts nothing.

### Xlin Verify

| Check | Question answered |
|---|---|
| `LOCK` | Is the lock file well formed (strict format, full hashes, tag matches version)? |
| `SOURCE` | Is there a fetched source created by Xlin Fetch? |
| `COMMIT` | Is the checked-out commit exactly the pinned full hash? |
| `TREE` | Do the tracked files match that commit (no edits after checkout)? |
| `TAG` | Is the tag exactly the pinned tag object, pointing at the pinned commit? |
| `VERSION` | Does the `Makefile` of that commit name the pinned release? |
| `OFFICIAL` | Does the official repository independently report the same tag and commit? |
| `SIGNATURE` | Is the tag validly signed by the pinned maintainer key? |

Exit status: `0` no check failed; `1` a check failed; `2` `--strict` and a check was skipped.

### Source identity is not authenticated provenance

- **Identity** (`COMMIT`, `TREE`, `TAG`, `VERSION`, `OFFICIAL`): "this is exactly commit X, the commit of release Y". A Git hash covers the content, so a matching hash proves the source is the same as the one pinned.
- **Provenance** (`SIGNATURE`): "the maintainer's key signed this release". Only a valid signature from the pinned key proves who published it. A matching hash alone does not, because someone could have pinned a hash of a malicious commit.

Xlin Verify reports them separately. If the signature check is skipped, the output says authenticated provenance is **not established** even though identity is verified.

The signer key is obtained through Web Key Directory from `kernel.org`, and its fingerprint must equal the pinned one. The pinned fingerprint is itself cross-checked against kernel.org's signature page. This is a trust-on-first-pin model, not the PGP web of trust.

## Updating the pin

1. Choose a release on the intended series from the official repository; confirm it is still maintained on <https://www.kernel.org/>.
2. Find the tag object and the peeled commit (`git ls-remote --tags <official> refs/tags/vX.Y.Z refs/tags/vX.Y.Z^{}`), the `Makefile` version and the signer fingerprint (`gpg --list-packets` on the tag's signature).
3. Edit `upstream/UPSTREAM.lock`, run `scripts/xlin-fetch` and `scripts/xlin-verify --strict`, run `tests/negative.sh`.
4. Open a pull request. CI repeats this against the real source. Never merge a pin change that fails verification.
