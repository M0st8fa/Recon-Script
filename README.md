# RECON.SH — Bug Bounty Recon Automation Framework

```
   ____  _____ ____ ___  _   _   ____  _   _
  |  _ \| ____/ ___/ _ \| \ | | / ___|| | | |
  | |_) |  _|| |  | | | |  \| | \___ \| |_| |
  |  _ <| |__| |__| |_| | |\  |  ___) |  _  |
  |_| \_\_____\____\___/|_| \_| |____/|_| |_|

          Bug Bounty Recon Framework v2.0
```

A modular, multi-phase recon automation script for bug hunters. It chains passive and active reconnaissance tools into a single pipeline — from subdomain discovery through URL collection, HTTP probing, smart URL classification, DNS misconfiguration checks, vulnerability scanning, and secret detection.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
  - [Required Tools](#required-tools)
  - [Optional Tools](#optional-tools)
  - [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [All Flags Reference](#all-flags-reference)
- [Modules](#modules)
  - [1. DNS Zone Transfer Check](#1-dns-zone-transfer-check)
  - [2. Subdomain Enumeration](#2-subdomain-enumeration)
  - [3. URL Collection](#3-url-collection)
  - [4. HTTP Probing](#4-http-probing)
  - [5. URL Classification](#5-url-classification)
  - [6. Cloud Storage Check](#6-cloud-storage-check)
  - [7. Nuclei Scanning (opt-in)](#7-nuclei-scanning-opt-in)
  - [8. Screenshots (opt-in)](#8-screenshots-opt-in)
  - [9. Secret / Gitleaks Scanning (opt-in)](#9-secret--gitleaks-scanning-opt-in)
- [Output Structure](#output-structure)
- [Examples](#examples)
- [Notifications](#notifications)
- [Tips for Bug Hunters](#tips-for-bug-hunters)
- [Disclaimer](#disclaimer)

---

## Features

| Feature | Description |
|---|---|
| Single or multi-domain | `-d example.com` or `-l domains.txt` |
| Subdomain enumeration | Subfinder (passive, all sources, recursive) + optional DNS brute-force |
| Zone transfer checks | AXFR via `dig` against all nameservers, with bonus DNS recon |
| URL collection | Waybackurls, gau, Katana, GoSpider — merged and deduplicated |
| HTTP probing | httpx with status codes, titles, tech detection, and redirect following |
| URL classification | 30+ category buckets: LFI, IDOR, SSRF, admin panels, secrets, APIs, and more |
| Cloud storage | S3, GCS, Azure Blob detection + public accessibility checks |
| Vulnerability scanning | Nuclei — CVEs, exposed panels, default credentials (opt-in) |
| Screenshots | gowitness / aquatone on live URLs (opt-in) |
| Secret scanning | gitleaks + regex grep over downloaded JS/config files (opt-in) |
| Subdomain takeover | subzy integration if installed |
| Notifications | Slack and Discord webhook support |
| Markdown report | Auto-generated summary with findings and recommendations |
| Resume mode | Continue an interrupted scan from its output directory |
| Verbose logging | Per-module log files in `logs/` for debugging |

---

## Requirements

### Required Tools

These must be installed and in your `$PATH` for the script to run:

| Tool | Purpose | Install |
|---|---|---|
| `subfinder` | Passive subdomain enumeration | `go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest` |
| `waybackurls` | Historical URLs from Wayback Machine | `go install github.com/tomnomnom/waybackurls@latest` |
| `katana` | Active web crawler | `go install github.com/projectdiscovery/katana/cmd/katana@latest` |
| `gospider` | Active web crawler | `go install github.com/jaeles-project/gospider@latest` |
| `httpx` | HTTP probing and fingerprinting | `go install github.com/projectdiscovery/httpx/cmd/httpx@latest` |
| `anew` | Append new unique lines to files | `go install github.com/tomnomnom/anew@latest` |
| `unfurl` | Extract components from URLs | `go install github.com/tomnomnom/unfurl@latest` |
| `dig` | DNS lookups and zone transfer testing | `apt install dnsutils` / `brew install bind` |

### Optional Tools

These extend the script's capabilities. The script will skip any module whose tool is absent and warn you:

| Tool | Module | Install |
|---|---|---|
| `dnsx` | DNS resolution + brute-force | `go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest` |
| `gau` | Additional URLs from Common Crawl + OTX | `go install github.com/lc/gau/v2/cmd/gau@latest` |
| `nuclei` | Vulnerability scanning | `go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest` |
| `gowitness` | Screenshots of live URLs | `go install github.com/sensepost/gowitness@latest` |
| `aquatone` | Screenshots (fallback to gowitness) | `go install github.com/michenriksen/aquatone@latest` |
| `gitleaks` | Secret detection in JS/config files | `go install github.com/gitleaks/gitleaks/v8@latest` |
| `subzy` | Subdomain takeover detection | `go install github.com/PentestPanic/subzy@latest` |
| `amass` | Additional subdomain enumeration | `go install github.com/owasp-amass/amass/v4/...@master` |

### Installation

**Install all Go tools at once:**

```bash
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install github.com/tomnomnom/waybackurls@latest
go install github.com/projectdiscovery/katana/cmd/katana@latest
go install github.com/jaeles-project/gospider@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
go install github.com/tomnomnom/anew@latest
go install github.com/tomnomnom/unfurl@latest
go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest
go install github.com/lc/gau/v2/cmd/gau@latest
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install github.com/sensepost/gowitness@latest
go install github.com/gitleaks/gitleaks/v8@latest
go install github.com/PentestPanic/subzy@latest
```

Make sure `$GOPATH/bin` (usually `~/go/bin`) is in your `$PATH`:

```bash
export PATH="$PATH:$HOME/go/bin"
# Add this line to your ~/.bashrc or ~/.zshrc to make it permanent
```

**Install the script:**

```bash
git clone https://github.com/yourrepo/recon.sh
cd recon.sh
chmod +x recon.sh
```

**Recommended: Install SecLists for DNS brute-forcing:**

```bash
sudo apt install seclists
# or
git clone https://github.com/danielmiessler/SecLists.git /usr/share/seclists
```

---

## Quick Start

```bash
# Single domain — full default pipeline
./recon.sh -d example.com

# Multiple domains from a file
./recon.sh -l targets.txt

# Full scan with all opt-in modules
./recon.sh -d example.com --nuclei --screenshots --gitleaks

# Fast scan — skip slow crawlers, keep essentials
./recon.sh -d example.com --skip-wayback --skip-gospider --skip-katana
```

---

## Usage

```
USAGE:
  ./recon.sh -d <domain>               Single domain
  ./recon.sh -l <domains.txt>          Multiple domains from file
  ./recon.sh -d <domain> [OPTIONS]
```

### All Flags Reference

#### Target

| Flag | Argument | Description |
|---|---|---|
| `-d` | `<domain>` | Single target domain (e.g. `example.com`) |
| `-l` | `<file>` | Path to a file with one domain per line |

#### Output & Verbosity

| Flag | Argument | Default | Description |
|---|---|---|---|
| `-o` | `<dir>` | `recon_TIMESTAMP` | Custom output directory name |
| `-v` | — | off | Enable verbose output (prints extra debug info per step) |

#### Performance Tuning

| Flag | Argument | Default | Description |
|---|---|---|---|
| `-t` | `<num>` | `50` | Thread count passed to tools (subfinder, httpx, dnsx, etc.) |
| `-r` | `<num>` | `150` | httpx rate limit in requests/second |
| `-D` | `<num>` | `3` | Katana crawl depth |
| `-T` | `<sec>` | `10` | Timeout in seconds for HTTP requests |
| `-w` | `<wordlist>` | SecLists top-5000 | Custom DNS wordlist for brute-force |
| `-R` | `<file>` | system resolvers | Custom DNS resolvers file (one IP per line) |

#### Skip Modules (default: all ON)

| Flag | Skips |
|---|---|
| `--skip-subfinder` | Subdomain enumeration with subfinder |
| `--skip-wayback` | Wayback Machine URL collection (also skips gau) |
| `--skip-katana` | Katana web crawler |
| `--skip-gospider` | GoSpider web crawler |
| `--skip-httpx` | HTTP probing and status code classification |
| `--skip-zone-transfer` | DNS zone transfer (AXFR) and DNS recon |

#### Opt-in Modules (default: all OFF)

| Flag | Enables |
|---|---|
| `--nuclei` | Nuclei vulnerability scanning on live (200) URLs |
| `--screenshots` | Visual screenshots via gowitness or aquatone |
| `--gitleaks` | Secret scanning on downloaded JS and config files |
| `--resume` | Resume a previous scan — continue into its existing output dir |

#### Notifications

| Flag | Argument | Description |
|---|---|---|
| `--slack` | `<webhook_url>` | Post summary to a Slack channel when done |
| `--discord` | `<webhook_url>` | Post summary to a Discord channel when done |

#### Help

```bash
./recon.sh -h
./recon.sh --help
```

---

## Modules

The script runs the following modules in order. Each module writes to its own subfolder inside the output directory.

### 1. DNS Zone Transfer Check

**Output:** `dns/`

Iterates every domain and queries all its nameservers for AXFR (zone transfer). A misconfigured DNS server that allows zone transfers exposes the full DNS zone — all subdomains, IPs, and records.

**What it checks:**
- AXFR zone transfer attempt against every NS record
- Extracts subdomains from successful transfers into `subdomains/zone_transfer_subs.txt`
- SPF, DMARC, DKIM TXT records
- DNSSEC (DS records) — flags domains without it
- MX records (useful for email security testing)
- IPv6 (AAAA records)
- Wildcard DNS detection (via dnsx if available)

**Output files:**

| File | Contents |
|---|---|
| `dns/zone_transfers.txt` | Full dump from vulnerable zone transfers |
| `dns/nameservers.txt` | NS records for each domain |
| `dns/txt_records.txt` | TXT records including SPF/DMARC |
| `dns/dnssec_check.txt` | DNSSEC status per domain |
| `dns/mx_records.txt` | Mail exchange records |
| `dns/ipv6.txt` | IPv6 addresses |

**Manual test:**
```bash
# Identify nameservers
dig NS target.com

# Attempt zone transfer manually
dig axfr @ns1.target.com target.com
```

---

### 2. Subdomain Enumeration

**Output:** `subdomains/`

Runs subfinder with all passive sources and recursive mode. If `dnsx` and a wordlist are available, also performs DNS brute-forcing. Checks for subdomain takeover candidates if `subzy` is installed.

**Steps:**
1. `subfinder -all --recursive` — passive enumeration from all sources
2. DNS brute-force with `dnsx` + wordlist (if both available)
3. Resolve all discovered subdomains through `dnsx`
4. Wildcard DNS detection
5. Subdomain takeover check with `subzy` (if installed)
6. Filter interesting subdomains (admin, dev, api, vpn, backup, etc.)

**Output files:**

| File | Contents |
|---|---|
| `subdomains/subfinder.txt` | Raw subfinder results |
| `subdomains/brute_force.txt` | DNS brute-force results |
| `subdomains/all_subdomains.txt` | Merged unique subdomains |
| `subdomains/dnsx_resolved.txt` | Resolved subdomains with IPs |
| `subdomains/interesting_subs.txt` | High-value subdomains filtered by keyword |
| `subdomains/zone_transfer_subs.txt` | Subdomains extracted from zone transfers |
| `dns/wildcards.txt` | Wildcard DNS records |
| `vuln/subdomain_takeover.txt` | Potential takeover candidates (if subzy ran) |

---

### 3. URL Collection

**Output:** `urls/`

Collects URLs from multiple sources: historical archives, passive crawling, and active crawling. All results are merged, deduplicated, and stripped of static assets (images, fonts, CSS).

**Sources:**

| Tool | Type | Notes |
|---|---|---|
| `waybackurls` | Passive | Wayback Machine archive |
| `gau` | Passive | Common Crawl + OTX + Wayback (if installed) |
| `katana` | Active | Crawls the live site with JS parsing, depth configurable via `-D` |
| `gospider` | Active | Crawls the live site, follows links and JS |

**Deduplication pipeline:**
```
waybackurls + gau + katana + gospider
    → sort -u
    → strip .css .jpg .jpeg .png .gif .svg .ico .woff .ttf .map
    → anew allurls.txt
```

**Output files:**

| File | Contents |
|---|---|
| `urls/waybackurls.txt` | Wayback Machine URLs |
| `urls/gau.txt` | gau output (if installed) |
| `urls/katana.txt` | Katana crawler output |
| `urls/gospider.txt` | GoSpider crawler output |
| `urls/allurls.txt` | Final merged, deduplicated URL list |

---

### 4. HTTP Probing

**Output:** `httpx/`

Probes every collected URL with httpx to identify live endpoints, collect HTTP metadata, and detect technologies.

**httpx flags used:**
- `-status-code` — HTTP response code
- `-title` — page title
- `-tech-detect` — technology fingerprinting (frameworks, servers, CMS)
- `-content-length` — response body size
- `-follow-redirects` — follow up to 10 redirects
- `-threads` / `-rate-limit` — concurrency controls
- `-no-color -silent` — clean output for parsing

**Output files:**

| File | Contents |
|---|---|
| `httpx/httpx_all.txt` | All probed URLs with status, title, tech |
| `httpx/httpx200.txt` | Live endpoints (200 OK) |
| `httpx/httpx204.txt` | No content |
| `httpx/httpx301.txt` | Permanent redirects |
| `httpx/httpx302.txt` | Temporary redirects |
| `httpx/httpx307.txt` | Temporary redirects |
| `httpx/httpx401.txt` | Unauthorized — interesting for auth bypass |
| `httpx/httpx403.txt` | Forbidden — prime target for 403 bypass |
| `httpx/httpx404.txt` | Not found |
| `httpx/httpx500.txt` | Server errors — possible injection points |
| `httpx/httpx503.txt` | Service unavailable |
| `httpx/httpx_other.txt` | All other status codes |
| `httpx/tech_summary.txt` | Technology frequency summary |
| `httpx/potential_wp_sites.txt` | WordPress installs detected |

> **Tip:** `httpx403.txt` is gold. Many 403 pages are bypassable with path tricks, headers, or method overrides.

---

### 5. URL Classification

**Output:** `urls/`

Classifies `allurls.txt` into targeted files by vulnerability type, file type, and technology. Every URL appears in the appropriate category file for focused manual testing.

**Categories:**

| File | Pattern Matched | Bug Type to Test |
|---|---|---|
| `lfi_params.txt` | `file=`, `path=`, `include=`, `page=`, `view=`, `template=` | Local File Inclusion |
| `redirect_ssrf.txt` | `url=`, `redirect=`, `next=`, `callback=`, `webhook=`, `dest=` | Open Redirect / SSRF |
| `idor_params.txt` | `id=`, `user=`, `account=`, `order=`, `token=`, `uid=` | IDOR |
| `xss_params.txt` | `q=`, `search=`, `query=`, `input=`, `msg=`, `error=` | Reflected XSS |
| `sqli_params.txt` | `id=`, `catid=`, `item=`, `sort=`, `order=`, `page=` | SQL Injection |
| `upload_params.txt` | `upload=`, `file=`, `img=`, `avatar=`, `attach=` | Unrestricted Upload |
| `ssrf_internal.txt` | `169.254.169.254`, `localhost`, `127.0.0.1` | SSRF to metadata/internal |
| `admin_panels.txt` | `/admin`, `/dashboard`, `/panel`, `/backend`, `/cpanel` | Exposed Admin |
| `debug_endpoints.txt` | `/debug`, `/trace`, `/phpinfo`, `/server-info`, `/health` | Debug Info Disclosure |
| `oauth_endpoints.txt` | `/oauth`, `/authorize`, `/token`, `/sso`, `/callback` | OAuth / Auth Flow |
| `api_docs_endpoints.txt` | `swagger`, `api-docs`, `graphql`, `/v1/`, `/v2/`, `/v3/` | API Enumeration |
| `secrets.txt` | `.env`, `.ini`, `.conf`, `.pem`, `.key`, `.crt`, `.pfx` | Exposed Secrets |
| `backups.txt` | `.bak`, `.old`, `.backup`, `.orig`, `.save`, `.swp` | Backup File Disclosure |
| `archives_dbs.txt` | `.sql`, `.zip`, `.tar.gz`, `.rar`, `.7z` | Database / Archive Dumps |
| `dev_envs.txt` | `dev.`, `test.`, `stage.`, `staging.`, `uat.`, `demo.` | Dev Environment Exposure |
| `sensitive_keywords.txt` | `internal`, `private`, `secret`, `backup`, `tmp` | Sensitive Path Keywords |
| `php.txt` | `.php` | PHP endpoints |
| `asp.txt` / `aspx.txt` | `.asp` / `.aspx` | ASP/ASP.NET endpoints |
| `jsp.txt` / `jspx.txt` | `.jsp` / `.jspx` | Java endpoints |
| `js.txt` | `.js` | JavaScript files |
| `data_configs.txt` | `.json`, `.xml`, `.yaml`, `.yml`, `.toml` | Config / Data files |
| `logs.txt` | `.log`, `.out`, `.err`, `.war` | Log files |
| `documents.txt` | `.pdf`, `.docx`, `.xlsx`, `.csv` | Exposed documents |
| `dev_scripts.txt` | `.py`, `.sh`, `.rb`, `.pl`, `.go` | Exposed source scripts |
| `aws_s3.txt` | `s3.amazonaws.com`, `s3-` | S3 bucket references |
| `apis_all.txt` | `api` (keyword) | API endpoints |
| `jwt_endpoints.txt` | `token`, `jwt`, `bearer` | JWT / token handling |
| `injection.txt` | `=` (any parameter) | All parameterized URLs |

---

### 6. Cloud Storage Check

**Output:** `dns/`

Detects cloud storage bucket references in DNS records and URLs, then actively checks if any S3, GCS, or Azure Blob containers are publicly accessible.

**Checked providers:**
- AWS S3 (`s3.amazonaws.com`, `.s3.amazonaws.com`, `.s3-*`)
- Google Cloud Storage (`storage.googleapis.com`)
- Azure Blob Storage (`.blob.core.windows.net`)

A `200 OK` on a bucket URL means it is **publicly readable** — a critical finding.

**Output files:**

| File | Contents |
|---|---|
| `dns/s3_amazon.txt` | S3 references from DNS |
| `dns/cloud_storage_urls.txt` | All cloud storage URLs found |
| `dns/cloud_storage_results.txt` | Accessibility results with status codes |

---

### 7. Nuclei Scanning (opt-in)

**Flag:** `--nuclei`  
**Output:** `vuln/`

Runs Nuclei against all live (200 OK) URLs. Automatically updates templates before running. Executes three focused template sets in addition to the main scan:

- **Main scan** — critical, high, and medium severity across all templates
- **CVEs** — known CVE-mapped vulnerabilities
- **Exposed panels** — login pages, admin panels, dashboards
- **Default logins** — default credentials on common services

**Output files:**

| File | Contents |
|---|---|
| `vuln/nuclei_results.txt` | All Nuclei findings |
| `vuln/nuclei_critical.txt` | Critical and high severity only |
| `vuln/nuclei_cves.txt` | CVE-matched findings |
| `vuln/exposed_panels.txt` | Exposed control panels |
| `vuln/default_logins.txt` | Default credential findings |

> **Important:** Always manually verify Nuclei findings before reporting. False positives exist.

---

### 8. Screenshots (opt-in)

**Flag:** `--screenshots`  
**Output:** `screenshots/`

Takes screenshots of all live (200 OK) URLs for visual triage. Uses `gowitness` if installed, falls back to `aquatone`. Screenshots make it much faster to spot admin panels, login pages, and interesting UIs without visiting every URL in a browser.

```bash
./recon.sh -d example.com --screenshots
```

---

### 9. Secret / Gitleaks Scanning (opt-in)

**Flag:** `--gitleaks`  
**Output:** `leaks/`

Downloads JavaScript and configuration files from `urls/js.txt` and scans them for hardcoded secrets.

**Two detection methods run in parallel:**
1. `gitleaks detect` — uses its built-in rule set with regex patterns for 100+ secret types
2. Manual `grep` — looks for common patterns: `api_key`, `secret`, `password`, `token`, `access_key`, `private_key`, `bearer`, `auth_token` followed by a value of 20+ characters

**Output files:**

| File | Contents |
|---|---|
| `leaks/downloaded/` | All downloaded JS and config files |
| `leaks/gitleaks_report.json` | Full gitleaks JSON report |
| `leaks/grep_secrets.txt` | Direct regex grep matches |

---

## Output Structure

Every run creates a timestamped directory (e.g. `recon_20240601_143022/`) with this layout:

```
recon_TIMESTAMP/
├── alldomains.txt              # Sanitized, deduplicated domain list
│
├── subdomains/
│   ├── subfinder.txt           # Raw subfinder output
│   ├── brute_force.txt         # DNS brute-force results
│   ├── all_subdomains.txt      # Merged unique list
│   ├── dnsx_resolved.txt       # Resolved with IPs
│   ├── interesting_subs.txt    # Keyword-filtered high-value subs
│   └── zone_transfer_subs.txt  # From zone transfers
│
├── urls/
│   ├── allurls.txt             # Master deduplicated URL list
│   ├── waybackurls.txt
│   ├── katana.txt
│   ├── gospider.txt
│   ├── gau.txt
│   ├── lfi_params.txt
│   ├── redirect_ssrf.txt
│   ├── idor_params.txt
│   ├── admin_panels.txt
│   ├── secrets.txt
│   ├── backups.txt
│   ├── js.txt
│   ├── php.txt
│   ├── apis_all.txt
│   └── ...                     # 30+ category files
│
├── httpx/
│   ├── httpx_all.txt           # All probed with status, title, tech
│   ├── httpx200.txt
│   ├── httpx403.txt
│   ├── httpx401.txt
│   ├── tech_summary.txt
│   └── potential_wp_sites.txt
│
├── dns/
│   ├── zone_transfers.txt      # Vulnerable zone transfer dumps
│   ├── nameservers.txt
│   ├── txt_records.txt
│   ├── dnssec_check.txt
│   ├── mx_records.txt
│   ├── wildcards.txt
│   ├── cloud_storage_urls.txt
│   └── cloud_storage_results.txt
│
├── vuln/
│   ├── nuclei_results.txt
│   ├── nuclei_critical.txt
│   ├── nuclei_cves.txt
│   ├── exposed_panels.txt
│   ├── default_logins.txt
│   └── subdomain_takeover.txt
│
├── screenshots/                # gowitness / aquatone output
│
├── leaks/
│   ├── downloaded/             # Downloaded JS/config files
│   ├── gitleaks_report.json
│   └── grep_secrets.txt
│
├── logs/
│   ├── run_config.txt          # Parameters used for this run
│   ├── subfinder.log
│   ├── katana.log
│   ├── httpx.log
│   ├── nuclei.log
│   └── ...
│
└── reports/
    └── summary.md              # Auto-generated Markdown report
```

---

## Examples

**Minimal — single domain, default modules:**
```bash
./recon.sh -d example.com
```

**Full power — all modules enabled:**
```bash
./recon.sh -d example.com \
    --nuclei \
    --screenshots \
    --gitleaks \
    -t 100 \
    -r 200 \
    -D 5 \
    -v
```

**Multiple domains from a file:**
```bash
./recon.sh -l targets.txt -o bugbounty_program -t 80
```

**Speed run — skip slow crawlers, passive only:**
```bash
./recon.sh -d example.com \
    --skip-gospider \
    --skip-katana \
    -t 100 \
    -r 300
```

**Skip everything except DNS and subdomain enum:**
```bash
./recon.sh -d example.com \
    --skip-wayback \
    --skip-katana \
    --skip-gospider \
    --skip-httpx
```

**Custom wordlist and resolvers:**
```bash
./recon.sh -d example.com \
    -w /opt/wordlists/dns/best-dns-wordlist.txt \
    -R /opt/resolvers/valid-resolvers.txt
```

**With Slack notification:**
```bash
./recon.sh -l targets.txt \
    --nuclei \
    --slack "https://hooks.slack.com/services/XXX/YYY/ZZZ"
```

**Resume an interrupted scan:**
```bash
./recon.sh -d example.com \
    --resume \
    -o recon_20240601_143022
```

**Minimal DNS-only recon (zone transfers + NS records):**
```bash
./recon.sh -d example.com \
    --skip-subfinder \
    --skip-wayback \
    --skip-katana \
    --skip-gospider \
    --skip-httpx
```

---

## Notifications

The script sends a summary message to Slack or Discord (or both) when the scan finishes.

**Message format:**
```
🔍 Recon Complete
Target: example.com
Subdomains: 342
URLs: 18,421
Live (200): 2,104
Nuclei findings: 7
Output: recon_20240601_143022
```

**Setup Slack:**
1. Create an incoming webhook in your Slack workspace
2. Pass it with `--slack https://hooks.slack.com/services/...`

**Setup Discord:**
1. Create a webhook in any Discord channel (Channel Settings → Integrations → Webhooks)
2. Pass it with `--discord https://discord.com/api/webhooks/...`

---

## Tips for Bug Hunters

**Priority order after a run:**

1. Check `dns/zone_transfers.txt` first — zone transfer is an instant critical
2. Review `subdomains/interesting_subs.txt` — dev/staging environments often have weaker security
3. Open `vuln/nuclei_critical.txt` — triage immediately
4. Work through `urls/lfi_params.txt`, `redirect_ssrf.txt`, and `idor_params.txt` — highest signal-to-noise param files
5. Check `httpx/httpx403.txt` — try 403 bypass techniques:
   ```
   X-Original-URL: /admin
   X-Rewrite-URL: /admin
   X-Forwarded-For: 127.0.0.1
   /admin/ → /ADMIN/ → //admin// → /admin;/
   ```
6. Check `httpx/httpx401.txt` — try authentication bypass
7. Download and diff `urls/js.txt` files — look for hardcoded secrets, internal endpoints, hidden parameters
8. Review `leaks/grep_secrets.txt` — any API keys or tokens are easy wins
9. Check `dns/cloud_storage_results.txt` for `[200]` lines — public buckets
10. Scan `urls/dev_envs.txt` — dev/staging hosts often share prod credentials or have debug features enabled

**Performance tuning by target size:**

| Program scope | Recommended flags |
|---|---|
| Single small domain | Default settings |
| Large domain with many subdomains | `-t 100 -r 300 -D 4` |
| Multi-domain scope (50+ domains) | `-t 150 -r 500 --skip-gospider` |
| VDP / gentle rate limits | `-t 20 -r 30 -T 20` |

**Custom resolvers improve accuracy:**

```bash
# Get a good resolver list
wget https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt
./recon.sh -d example.com -R resolvers.txt
```

---

## Disclaimer

This tool is intended for authorized security testing only. Only use it against targets you have explicit permission to test — either through a bug bounty program scope or a signed authorization agreement. Unauthorized scanning is illegal in most jurisdictions. The authors are not responsible for misuse.

Always read and respect the program's scope, rate limits, and testing rules before running any automated tooling.
