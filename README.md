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
| [`connector-specs/`](connector-specs/) | The shipped REST specs, see the table below. |
| [`upstream-specs/`](upstream-specs/) | Example configuration for an **MCP upstream** (a third-party MCP server under our governance): `github.yaml`. |
| [`docs/`](docs/) | The four format contracts, the build discipline and four operator guides. |
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
| [`gemini-websuche.yaml`](connector-specs/gemini-websuche.yaml) (1.0.1) | 1, read-only | Built; live verified (2026-11-03, 13 questions of the script). One free question per call to the Gemini API with Google Search grounding; answer text and source domains. The question is redacted in the audit log at the default log depth, but not at the provider. Mandatory step before the first call: switch pseudonym rehydration off for `ask` ([setup guide](docs/connector-websuche-geo.md)). Only the script token of the GEO measurement holds the right. A trend signal for visibility in AI answers, not a copy of Google AI Overviews. Paid API; the operator sets the provider cap. |
| [`google-search-console.yaml`](connector-specs/google-search-console.yaml) (2.0.0) | 5, read-only | Built; synthetic contracts verified, live acceptance pending. Private sidecar, fixed public page allowlist; periods of 1–90 days, `page_compare` for two equal periods. Query text disabled by default (operator switch); metadata audit depth required. |
| [`google-analytics.yaml`](connector-specs/google-analytics.yaml) (2.0.0) | 4, read-only | Built; synthetic contracts verified, live acceptance pending. Fixed GA4 aggregates, hostname/page filters; optional key-event measurement contract. |
| [`google-search-console-manage.yaml`](connector-specs/google-search-console-manage.yaml) (1.1.0) | 4, 1 of them writing | Built; live verified (2026-10-22). List, read and submit sitemaps, URL inspection. No delete; submitting does not trigger a crawl. Daily cap and change line in the sidecar. |
| [`google-analytics-manage.yaml`](connector-specs/google-analytics-manage.yaml) (1.1.0) | 6, 4 of them writing | Built; live verified (2026-10-22). Create and update GA4 annotations and one AI assistant channel group via the Admin API v1alpha. No delete; preview via `dry_run`. |
| [`bing-webmaster.yaml`](connector-specs/bing-webmaster.yaml) (1.0.0) | 3, read-only | Built; live evidence pending. Index record of single public pages, registered sitemaps and the URL submission quota of Bing Webmaster, through the `bing-webmaster` service from januaport-plugins. The Bing key stays in the service; no page statistics, no search terms. |
| [`bing-webmaster-manage.yaml`](connector-specs/bing-webmaster-manage.yaml) (1.0.0) | 3, all writing | Built; live evidence pending. Report single URLs or a sitemap to Bing and URLs through IndexNow. Submitting does not guarantee crawling or indexing; no removing or blocking. The service caps write attempts at 20 per route and UTC day; `dry_run` returns a preview. |
| [`demo-erp.yaml`](connector-specs/demo-erp.yaml) | 2, read-only | **Built, demo only.** A mock for the walkthrough: it talks to an invented ERP, not a real system. Needs the example ERP from the product repository. |
| [`dokumente.yaml`](connector-specs/dokumente.yaml) | 4, read-only | **Built.** Verified live (20 September 2026): all four check stages green, search via `/mcp` with the expected hit, audit entry with redacted search term. Template: one knowledge area per integration. |
| [`lexware-office.yaml`](connector-specs/lexware-office.yaml) (3.0.1) | 8, of which 4 write | **Built.** Reading verified live. Create contact and create invoice verified live (2026-10-15); invoices are always created finalized, the tool sends no mail. Upload document is proven in production use (2026-10-23). Attach document image is built; its live evidence is pending. |
| [`linkedin-seite.yaml`](connector-specs/linkedin-seite.yaml) (1.0.0) | 3, read-only | Built; live evidence pending. Page totals, follower total and gains, latest posts with lifetime totals through the `linkedin-seite` service from januaport-plugins. Sums only, no breakdown by member attributes. |
| [`linkedin-seite-manage.yaml`](connector-specs/linkedin-seite-manage.yaml) (3.0.0) | 5, 4 of them writing | Built; live evidence pending. Preview an entry of the editorial plan, then publish, edit or delete its post or create a comment. The human approval happens in the gateway: each write tool carries a `freigabe` block, a human approves the hash of a server-side preview through SSO, and the gateway passes the approval to the service in the `X-Jnpt-Freigabe` header. The service 0.3.0 accepts only this form; approval through `redaktion_freigabe` in the service is superseded. |
| [`linkedin-seite-community.yaml`](connector-specs/linkedin-seite-community.yaml) (1.0.0) | 3, 1 of them writing | Built; live evidence pending. Unanswered top-level comments under the page's own posts, a reply as the organization (fixed reason list, 8 attempts per UTC day) and a daily list of links. No names or person identifiers. Activation needs a reply token holding only this template's two tools and `linkedin-seite:posts`. |
| [`microsoft-graph-mail.yaml`](connector-specs/microsoft-graph-mail.yaml) | 10 total: 7 YAML + 3 native, of which 6 write | **Built.** Verified live (6/7 August 2026): reading with 200, a draft actually created, with the counter-check "nothing sent". **Single-mailbox limit verified (13 August 2026):** a second, existing mailbox answers with 403. Sending is opt-in and has two ways: `reply` answers one existing message (to its sender only), `send_mail` sends a new mail to a recipient of your choice (one recipient, optional one CC; no daily cap, no approval click). No reply-all, no forwarding, no attachments, no BCC. Native tools: `save_attachment`, `move_message`, `mark_read`; YAML at 4.0.0 (new tool `send_mail`; live evidence for `reply` and `send_mail` pending). |
| [`microsoft-graph-sharepoint.yaml`](connector-specs/microsoft-graph-sharepoint.yaml) (3.0.0) | 4, read-only | **Built.** Verified live on a real tenant (25 August 2026): 403 before the site grant, 200 after it. Metadata only, never file contents. All four tools run below the site of the integration; the limit that counts is the `Sites.Selected` grant of the app, so one app registration per site. The path form of 3.0.0 has no live evidence yet. |
| [`business-central.yaml`](connector-specs/business-central.yaml) (2.0.0) | 11, read-only | Built; live evidence pending. Online API v2.0, one company in one environment; tenant and company are instance values. |
| [`hubspot.yaml`](connector-specs/hubspot.yaml) (1.0.0) | 8, read-only | Built; live evidence pending. Contacts, companies and deals; read-only searches via POST. |
| [`jtl-wawi.yaml`](connector-specs/jtl-wawi.yaml) (1.0.0) | 10, read-only | Built; live evidence pending. On-premise API version 2.0; fixed request headers, no writing. |
| [`microsoft-graph-calendar.yaml`](connector-specs/microsoft-graph-calendar.yaml) (1.0.0) | 3, read-only | Built; live evidence pending. One mailbox; no attendees or event text. |
| [`odoo.yaml`](connector-specs/odoo.yaml) (4.0.1) | 17, of which 5 write | Built. Tools up to 3.0.0 verified live (30 September 2026); the 4.0.0 additions (`count_leads`, `add_lead_note`, daily cap of 50 on `set_lead_stage` and `add_lead_note`) have no live evidence yet. Search text (`q`) and names (`name`) are redacted in the audit log. Chatter, including `add_lead_note`, requires a separate integration with an internal Odoo user. The contract model is an extension, not Odoo standard. |
| [`openai-websuche.yaml`](connector-specs/openai-websuche.yaml) (1.0.1) | 1, read-only | Built; live verified (2026-11-03, 13 questions of the script). One free question per call to the OpenAI Responses API with web search; answer text and cited URLs. The question is redacted in the audit log at the default log depth, but not at the provider. Mandatory step before the first call: switch pseudonym rehydration off for `ask` ([setup guide](docs/connector-websuche-geo.md)). Only the script token of the GEO measurement holds the right. A trend signal for visibility in AI answers, not a copy of the ChatGPT app. Paid API; the operator sets the provider cap. |
| [`openproject.yaml`](connector-specs/openproject.yaml) (1.0.0) | 7, read-only | Built; verified live against 17.8.0 (30 September 2026). Projects and work packages; no time entries or user lists. |
| [`paperless.yaml`](connector-specs/paperless.yaml) (1.0.0) | 6, read-only | Built; verified live against 3.2.1 (30 September 2026). Metadata only; no OCR text, file content or download. |
| [`shopware-admin.yaml`](connector-specs/shopware-admin.yaml) (1.0.0) | 6, read-only | Built; verified live against 6.7.14.2 (29 September 2026). Read-only ACL role; JSON response format and inherited variant names. |
| [`woocommerce.yaml`](connector-specs/woocommerce.yaml) (1.0.0) | 7, read-only | Built; verified live against 11.1.2 (30 September 2026). Read key via Basic over HTTPS; fixed field lists. |
| [`zammad.yaml`](connector-specs/zammad.yaml) (1.0.0) | 7, read-only | Built; verified live against 7.2.0 (30 September 2026). Metadata only; no articles or notes. The vendor token can write customer and organisation records; JanuaPort exposes only GET tools. |
| [`upstream-specs/github.yaml`](upstream-specs/github.yaml) | allowlist | **Built.** Shipped since v0.2.0, read relay verified live. Example of the instance model: the same URL, different access tokens and allowlists. |

Template versions are the product versions. The additional vendor setup guides remain
product documentation (not public); format rules and vendor references are in the
spec comments and [build discipline](docs/connector-treue.md). The live results above
come from the product; this mirror sync was verified locally without vendor calls.

The setup guide for the two web search templates is [here](docs/connector-websuche-geo.md). Operator guides for the two Graph connectors are included
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

## Google Reporting (#1130)

[Search Console and GA4](docs/connector-google-reporting.md): two version 2.0.0 templates expose nine fixed read tools through the private Google Reporting sidecar. Stage 1: built and tested with synthetic data; live acceptance is pending. Query text stays disabled by default (operator switch); both templates use one connector credential, `google-reporting`; metadata audit depth is an operating prerequisite.

Two more version 1.1.0 templates, `google-search-console-manage` and `google-analytics-manage`, add write handles for a website team: submit a sitemap, create and update annotations and one AI assistant channel group. The read templates stay unchanged; the write tools carry tool-exact permissions. Since 1.1.0 one sidecar serves up to five sites: each site gets its own integration instance, which sends the site name as a declared instance value; permissions per site are the tool-exact permissions per instance, and the site never comes from a tool parameter. Details in the [guide](docs/connector-google-reporting.md).
