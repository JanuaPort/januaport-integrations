# januaport-integrations

**English** · [Deutsch](README.de.md)

Outbound for JanuaPort: connector specs, spec formats, catalogue and example configurations, i.e. everything JanuaPort talks to in other systems.

JanuaPort is a self-hosted MCP gateway. It connects AI assistants to a company's existing systems with
fine-grained permissions and records access in an append-only audit log. The core of JanuaPort is
proprietary software of JanuaPort GmbH and is not part of this repository. This repository is one of the
open edges around it.

- **License:** Apache License 2.0 ([`LICENSE`](LICENSE), [`NOTICE`](NOTICE))
- **Links:** [januaport.ai](https://januaport.ai) · [Security policy](SECURITY.md) · [Contributing](CONTRIBUTING.md)
- **Language:** The format contracts and guides in `docs/` are currently written in German.

No customer data, no keys, no operator values in this repository.

---

## What this is about

JanuaPort turns an existing system (ERP, accounting, mailbox, file storage) into finely permissioned MCP
tools for AI agents. **What JanuaPort addresses in those systems is defined here:** a spec describes in
YAML which calls to another system are allowed and how their response reaches the agent. Each spec becomes
MCP tools when it is loaded; the gateway adds permissions, pseudonymisation and audit on top.
Pseudonymisation is deterministic and rule-based, with no language model in the path, and off unless
configured: it replaces with fixed tokens only the fields the operator declares and, in free text, only
what the operator assigns a pattern to (for example IBAN, e-mail, phone). Names in free text are not
detected.

A spec is **configuration, not code**: it is read, never executed. That is why it can be contributed and
reviewed from outside without anyone touching the gateway.

## What lives here

| Folder | Contents |
|---|---|
| [`connector-specs/`](connector-specs/) | The shipped REST specs, five of them, see the table below. |
| [`upstream-specs/`](upstream-specs/) | Example configuration for an **MCP upstream** (a third-party MCP server under our governance): `github.yaml`. |
| [`docs/`](docs/) | The four format contracts, the build discipline and two operator guides. |
| [`examples/`](examples/) | Attachments to the guides (today: the Exchange script for the single-mailbox limit). |

## The four format contracts

Four kinds of integration, four formats. Which one is right is decided **before** building. The rule of
thumb is in [`docs/connector-treue.md`](docs/connector-treue.md) §8: *if an MCP server already exists for
the system, that is the way.*

| Kind | Contract | For |
|---|---|---|
| REST connector | [`docs/connector-spec.md`](docs/connector-spec.md) | A system with a usable REST API: one tool per endpoint. |
| MCP upstream | [`docs/upstream-mcp.md`](docs/upstream-mcp.md) | An MCP server exists for the system: proxy it instead of rebuilding it. |
| Database | [`docs/db-connector-spec.md`](docs/db-connector-spec.md) | An existing system without an API but with a database: a curated view instead of free SQL access. |
| File | [`docs/file-connector-spec.md`](docs/file-connector-spec.md) | Whatever lands as a file in a directory (for example a bank statement). |

In addition: [`docs/connector-treue.md`](docs/connector-treue.md) covers auth patterns, the binding build
discipline and when an upstream is the better choice.

## How a spec is made

1. **Choose the kind of integration** (table above). A REST connector that rebuilds an existing MCP
   server in YAML is double the work for half the coverage.
2. **Documentation first.** Work from the vendor's official documentation: endpoint, parameters,
   response **and the request headers**. The documentation reference is written down, not just read; it
   is part of the contribution.
3. **Write the spec.** `version` is mandatory (SemVer). The tool descriptions are a **product feature**,
   not an afterthought: an AI decides what to call based on them alone. Writing tools are marked as such,
   one by one.
4. **Check live.** `jnpt connector check` runs in four stages, up to a real call against the real API.
5. **Provide evidence.** What was observed belongs in the contribution, without credentials and without
   real data.

### Documentation first, then live, and why both

**Documentation first** prevents invented calls. **Live afterwards** prevents the more expensive mistake:
a spec that *looks* like the documentation and still does not work. Both are lessons we paid for, not
principles: endpoints that answer 400 without the right `Accept` header, permissions that only take
effect on the resource side, error messages that report "there is nothing" as "the call is broken". None
of these cases was in any documentation.

**Live evidence is the definition of done, for outside contributions too.** No tool counts as finished
without a real success against the real system (200 when reading, a controlled success when writing),
described in the pull request. If you have no real access to the system, say so: **an untested draft is
welcome.** It is then kept as a draft and not merged as verified. This is not a barrier to contributions;
it is the promise that nothing here works only on paper.

## What reaches the product

**Only gated specs.** This repository is the workbench, not the delivery channel: a merge here does not
yet mean a spec will appear in the product. The catalogue in the JanuaPort image is a **curated
selection**; every spec in it passes the quality gate of JanuaPort GmbH (format, security invariants, live
evidence, maintenance commitment). A spec that is here but not shipped can still be used: an operator can
place any spec in their own connector directory.

## Status of the shipped specs

Status labels: **Built** · **In progress** · **Planned**. "Verified live" means: run against the real
system and documented in the backlog.

| Spec | Tools | Status |
|---|---|---|
| [`demo-erp.yaml`](connector-specs/demo-erp.yaml) | 2, read-only | **Built, demo only.** A mock for the walkthrough: it talks to an invented ERP, not a real system. Needs the example ERP from the product repository. |
| [`dokumente.yaml`](connector-specs/dokumente.yaml) | 4, read-only | **Built.** Verified live (20 September 2026): all four check stages green, search via `/mcp` with the expected hit, audit entry with redacted search term. Template: one knowledge area per integration. |
| [`lexware-office.yaml`](connector-specs/lexware-office.yaml) | 6, of which 2 write | **Built.** Reading verified live. The two writing tools (upload document, attach document image) are built; **live evidence of the write path is pending**. |
| [`microsoft-graph-mail.yaml`](connector-specs/microsoft-graph-mail.yaml) | 5, of which 1 writes | **Built.** Verified live (6/7 August 2026): reading with 200, a draft actually created, with the counter-check "nothing sent". **Single-mailbox limit verified (13 August 2026):** a second, existing mailbox answers with 403. No send tool, deliberately. |
| [`microsoft-graph-sharepoint.yaml`](connector-specs/microsoft-graph-sharepoint.yaml) | 4, read-only | **Built.** Verified live on a real tenant (25 August 2026): 403 before the site grant, 200 after it. Metadata only, never file contents. |
| [`upstream-specs/github.yaml`](upstream-specs/github.yaml) | allowlist | **Built.** Shipped since v0.2.0, read relay verified live. Example of the instance model: the same URL, different access tokens and allowlists. |

Operator guides for the two Graph connectors are included
([mailbox](docs/connector-microsoft-graph-mail.md),
[SharePoint](docs/connector-microsoft-graph-sharepoint.md)). They describe the setup on the **other
side** (app registration, permissions, limits) and are also the model for how a spec should be
documented.

## Notes for reading

- **`#` numbers** (for example `#347`) refer to the backlog of the product repository, which is closed
  today. They name where a decision came from and are not links.
- **"(Produkt-Doku, nicht öffentlich)"** (product documentation, not public) marks a reference to a file
  in the closed core. The surrounding paragraph stands on its own; only the deeper detail is missing.
- **There is no stand-alone example file for database and file specs here yet.** The complete example
  is in the format contract itself (section "Vollständiges Beispiel"). File specs are usually generated
  by the product, not written by hand.
