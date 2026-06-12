# Security Policy

## Scope

fern-core is a TUI framework. It does no networking, no cryptography,
and no privilege escalation.

In scope:

- Memory safety bugs (use-after-free, out-of-bounds, double-free) reachable
  from application input
- ANSI/OSC parser bugs that let crafted terminal input escape their intended
  context in ways that affect the embedding application
- Build system issues that would inject malicious code into a user's binary

Out of scope:

- Bugs that only affect your own machine when running examples
- Issues that require physical access to the terminal or shell
- Vulnerabilities in Zig's standard library or the compiler itself.

## Reporting

fern is a small BDFN project. Security-relevant bugs are reported and
discussed publicly in GitHub Issues under the label "security".

We follow the same model as stb and miniaudio: bugs are discussed in the
open, and fixes may take time. If that does not work for your use case,
factor it into whether fern-core is the right dependency for you.

If you find something serious enough that you do not want to disclose it
publicly before a fix is available, email the maintainer directly. Contact
info is in the commit history and on the GitHub profile of the primary
committer.

## Supported Versions

Only the latest release gets security fixes. Older releases are not patched.

## CVEs

We do not issue CVEs. The overhead is not worth it at this scale. If a
downstream packager needs one, they can request it through MITRE.
