#!/usr/bin/env bash
# ============================================================
#  recon.sh — Bug Bounty Recon Automation Framework
#  Author  : generated for your workflow
#  Usage   : ./recon.sh [OPTIONS]
# ============================================================

set -euo pipefail

# ─────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; RESET='\033[0m'

# ─────────────────────────────────────────────
# DEFAULTS
# ─────────────────────────────────────────────
DOMAIN=""
DOMAIN_LIST=""
OUTPUT_DIR="recon_$(date +%Y%m%d_%H%M%S)"
THREADS=50
RATE_LIMIT=150          # httpx requests/sec
RESOLVERS="/etc/resolv.conf"
CUSTOM_RESOLVERS=""
DEPTH=3                 # katana crawl depth
TIMEOUT=10
SKIP_WAYBACK=false
SKIP_GOSPIDER=false
SKIP_KATANA=false
SKIP_SUBFINDER=false
SKIP_HTTPX=false
SKIP_ZONE_TRANSFER=false
SKIP_SCREENSHOTS=false
SKIP_NUCLEI=false
SKIP_GITLEAKS=false
RUN_NUCLEI=false
RUN_SCREENSHOTS=false
RUN_GITLEAKS=false
NOTIFY=false
SLACK_WEBHOOK=""
DISCORD_WEBHOOK=""
VERBOSE=false
RESUME=false
WORDLIST="/usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt"
NUCLEI_TEMPLATES="$HOME/nuclei-templates"
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"

# ─────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────
banner() {
cat <<'EOF'
   ____  _____ ____ ___  _   _   ____  _   _
  |  _ \| ____/ ___/ _ \| \ | | / ___|| | | |
  | |_) |  _|| |  | | | |  \| | \___ \| |_| |
  |  _ <| |__| |__| |_| | |\  |  ___) |  _  |
  |_| \_\_____\____\___/|_| \_| |____/|_| |_|

          Bug Bounty Recon Framework v2.0
EOF
    echo -e "${CYAN}  ─────────────────────────────────────────${RESET}"
}

# ─────────────────────────────────────────────
# HELP
# ─────────────────────────────────────────────
usage() {
    banner
    cat <<EOF

${BOLD}USAGE:${RESET}
  $0 -d <domain>               Single domain
  $0 -l <domains.txt>          Multiple domains from file
  $0 -d <domain> [OPTIONS]

${BOLD}TARGET OPTIONS:${RESET}
  -d  <domain>          Single target domain (e.g. example.com)
  -l  <file>            File with one domain per line

${BOLD}OUTPUT:${RESET}
  -o  <dir>             Output directory (default: recon_TIMESTAMP)
  -v                    Verbose output

${BOLD}TUNING:${RESET}
  -t  <num>             Threads (default: 50)
  -r  <num>             httpx rate limit req/s (default: 150)
  -D  <num>             Katana crawl depth (default: 3)
  -T  <sec>             Timeout seconds (default: 10)
  -w  <wordlist>        DNS wordlist for brute-forcing
  -R  <resolvers.txt>   Custom DNS resolvers file

${BOLD}MODULE TOGGLES (skip):${RESET}
  --skip-subfinder      Skip subdomain enumeration
  --skip-wayback        Skip Wayback Machine URLs
  --skip-katana         Skip Katana crawler
  --skip-gospider       Skip GoSpider crawler
  --skip-httpx          Skip HTTP probing
  --skip-zone-transfer  Skip DNS zone transfer checks

${BOLD}EXTRA MODULES (opt-in):${RESET}
  --screenshots         Take screenshots with gowitness/aquatone
  --nuclei              Run Nuclei vulnerability scanner
  --gitleaks            Run gitleaks on discovered JS/config files
  --resume              Resume from existing output directory

${BOLD}NOTIFICATIONS:${RESET}
  --slack   <webhook>   Send summary to Slack
  --discord <webhook>   Send summary to Discord

${BOLD}EXAMPLES:${RESET}
  $0 -d example.com
  $0 -l targets.txt -o my_recon -t 100 --nuclei --screenshots
  $0 -d example.com --skip-wayback --skip-gospider --nuclei
  $0 -d example.com --resume -o recon_20240601_120000

EOF
    exit 0
}

# ─────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────
log()     { echo -e "${GREEN}[+]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
err()     { echo -e "${RED}[-]${RESET} $*" >&2; }
info()    { echo -e "${CYAN}[*]${RESET} $*"; }
section() { echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; \
            echo -e "${BOLD}${BLUE}  $*${RESET}"; \
            echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
verbose() { [[ "$VERBOSE" == true ]] && echo -e "${MAGENTA}[v]${RESET} $*" || true; }

# ─────────────────────────────────────────────
# TOOL CHECK
# ─────────────────────────────────────────────
check_tools() {
    section "Checking Required Tools"
    local required=(subfinder waybackurls katana gospider httpx anew unfurl dig)
    local optional=(nuclei gowitness aquatone gitleaks dnsx amass)
    local missing_required=() missing_optional=()

    for tool in "${required[@]}"; do
        if command -v "$tool" &>/dev/null; then
            log "$tool ✓"
        else
            err "$tool ✗ (REQUIRED)"
            missing_required+=("$tool")
        fi
    done

    for tool in "${optional[@]}"; do
        if command -v "$tool" &>/dev/null; then
            log "$tool ✓ (optional)"
        else
            warn "$tool ✗ (optional — some features disabled)"
            missing_optional+=("$tool")
        fi
    done

    if [[ ${#missing_required[@]} -gt 0 ]]; then
        err "Missing required tools: ${missing_required[*]}"
        echo -e "\n${YELLOW}Install hints:${RESET}"
        echo "  go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
        echo "  go install github.com/tomnomnom/waybackurls@latest"
        echo "  go install github.com/projectdiscovery/katana/cmd/katana@latest"
        echo "  go install github.com/jaeles-project/gospider@latest"
        echo "  go install github.com/projectdiscovery/httpx/cmd/httpx@latest"
        echo "  go install github.com/tomnomnom/anew@latest"
        echo "  go install github.com/tomnomnom/unfurl@latest"
        exit 1
    fi
}

# ─────────────────────────────────────────────
# SETUP OUTPUT DIRS
# ─────────────────────────────────────────────
setup_dirs() {
    local base="$OUTPUT_DIR"
    mkdir -p "$base"/{subdomains,urls,httpx,dns,vuln,screenshots,leaks,wordlists,logs,reports}
    log "Output directory: ${BOLD}$base${RESET}"
    # Save run config
    {
        echo "Run started : $(date)"
        echo "Domain(s)   : ${DOMAIN:-$DOMAIN_LIST}"
        echo "Threads     : $THREADS"
        echo "Rate limit  : $RATE_LIMIT"
        echo "Depth       : $DEPTH"
    } > "$base/logs/run_config.txt"
}

# ─────────────────────────────────────────────
# PREPARE DOMAIN LIST
# ─────────────────────────────────────────────
prepare_domains() {
    local alldomains="$OUTPUT_DIR/alldomains.txt"

    if [[ -n "$DOMAIN" ]]; then
        echo "$DOMAIN" > "$alldomains"
        log "Target: $DOMAIN"
    elif [[ -n "$DOMAIN_LIST" ]]; then
        cp "$DOMAIN_LIST" "$alldomains"
        log "Loaded $(wc -l < "$alldomains") domains from $DOMAIN_LIST"
    fi

    # Sanitize: strip whitespace, remove blank lines, lowercase
    sed -i 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d' "$alldomains"
    tr '[:upper:]' '[:lower:]' < "$alldomains" | sort -u > "${alldomains}.tmp"
    mv "${alldomains}.tmp" "$alldomains"
}

# ─────────────────────────────────────────────
# DNS ZONE TRANSFER CHECK
# ─────────────────────────────────────────────
zone_transfer_check() {
    [[ "$SKIP_ZONE_TRANSFER" == true ]] && return
    section "DNS Zone Transfer Check"

    local alldomains="$OUTPUT_DIR/alldomains.txt"
    local zt_out="$OUTPUT_DIR/dns/zone_transfers.txt"
    local ns_out="$OUTPUT_DIR/dns/nameservers.txt"
    local found=0

    > "$zt_out"; > "$ns_out"

    while IFS= read -r domain; do
        [[ -z "$domain" ]] && continue
        info "Checking NS for: $domain"

        # Get nameservers
        local nameservers
        nameservers=$(dig NS "$domain" +short 2>/dev/null | sed 's/\.$//')

        if [[ -z "$nameservers" ]]; then
            warn "No NS records found for $domain"
            continue
        fi

        echo "=== $domain ===" >> "$ns_out"
        echo "$nameservers" >> "$ns_out"
        verbose "NS: $nameservers"

        while IFS= read -r ns; do
            [[ -z "$ns" ]] && continue
            info "  Attempting AXFR: $ns -> $domain"
            local result
            result=$(dig axfr "@$ns" "$domain" 2>/dev/null)

            if echo "$result" | grep -qiE "^$domain\." ; then
                warn "  ${RED}${BOLD}ZONE TRANSFER VULNERABLE!${RESET} $domain via $ns"
                {
                    echo "=== VULNERABLE: $domain via $ns ==="
                    echo "$result"
                    echo ""
                } >> "$zt_out"
                ((found++))
                # Extract subdomains from zone transfer
                echo "$result" | grep -oP "[\w.-]+\.$domain" | sort -u \
                    >> "$OUTPUT_DIR/subdomains/zone_transfer_subs.txt" 2>/dev/null || true
            else
                log "  Not vulnerable: $ns"
            fi
        done <<< "$nameservers"

        # Also check for SPF, DMARC, DKIM misconfigs
        echo "=== TXT Records: $domain ===" >> "$OUTPUT_DIR/dns/txt_records.txt"
        dig TXT "$domain" +short >> "$OUTPUT_DIR/dns/txt_records.txt" 2>/dev/null || true
        dig TXT "_dmarc.$domain" +short >> "$OUTPUT_DIR/dns/txt_records.txt" 2>/dev/null || true

        # DNSSEC check
        local dnssec
        dnssec=$(dig DS "$domain" +short 2>/dev/null)
        if [[ -z "$dnssec" ]]; then
            echo "$domain: NO DNSSEC" >> "$OUTPUT_DIR/dns/dnssec_check.txt"
        else
            echo "$domain: DNSSEC enabled" >> "$OUTPUT_DIR/dns/dnssec_check.txt"
        fi

        # IPv6 (AAAA)
        dig AAAA "$domain" +short >> "$OUTPUT_DIR/dns/ipv6.txt" 2>/dev/null || true

        # MX records (useful for email security testing)
        echo "=== MX: $domain ===" >> "$OUTPUT_DIR/dns/mx_records.txt"
        dig MX "$domain" +short >> "$OUTPUT_DIR/dns/mx_records.txt" 2>/dev/null || true

    done < "$alldomains"

    if [[ $found -gt 0 ]]; then
        warn "${BOLD}$found zone transfer(s) found! Check: $zt_out${RESET}"
    else
        log "No zone transfers possible (good)"
    fi
}

# ─────────────────────────────────────────────
# SUBDOMAIN ENUMERATION
# ─────────────────────────────────────────────
subdomain_enum() {
    [[ "$SKIP_SUBFINDER" == true ]] && return
    section "Subdomain Enumeration"

    local alldomains="$OUTPUT_DIR/alldomains.txt"
    local subfinder_out="$OUTPUT_DIR/subdomains/subfinder.txt"
    local dnsx_out="$OUTPUT_DIR/subdomains/dnsx_resolved.txt"

    # Subfinder
    info "Running subfinder (passive + all sources)..."
    subfinder -dL "$alldomains" -all --recursive \
        -o "$subfinder_out" \
        -silent 2>>"$OUTPUT_DIR/logs/subfinder.log" || true
    log "Subfinder: $(wc -l < "$subfinder_out" 2>/dev/null || echo 0) subdomains"

    # Optional DNS brute force if wordlist exists
    if [[ -f "$WORDLIST" ]] && command -v dnsx &>/dev/null; then
        info "DNS brute-force with dnsx..."
        local brute_out="$OUTPUT_DIR/subdomains/brute_force.txt"
        # Generate permutations per domain
        while IFS= read -r domain; do
            awk -v d="$domain" '{print $1"."d}' "$WORDLIST" \
            | dnsx -silent -a -resp -threads "$THREADS" \
            >> "$brute_out" 2>/dev/null || true
        done < "$alldomains"
        log "Brute force: $(wc -l < "$brute_out" 2>/dev/null || echo 0) results"
    fi

    # Merge all subdomains
    local merged="$OUTPUT_DIR/subdomains/all_subdomains.txt"
    cat "$OUTPUT_DIR/subdomains/"*.txt 2>/dev/null | sort -u > "$merged"

    # Resolve with dnsx if available
    if command -v dnsx &>/dev/null; then
        info "Resolving subdomains with dnsx..."
        dnsx -silent -l "$merged" -a -resp -threads "$THREADS" \
            -o "$dnsx_out" 2>>"$OUTPUT_DIR/logs/dnsx.log" || true

        # Wildcard detection
        dnsx -silent -l "$merged" -wc 2>/dev/null \
            | tee "$OUTPUT_DIR/dns/wildcards.txt" || true
    fi

    # Add resolved subdomains to alldomains for further scanning
    if [[ -f "$dnsx_out" ]]; then
        awk '{print $1}' "$dnsx_out" | anew "$alldomains" > /dev/null
    else
        cat "$merged" | anew "$alldomains" > /dev/null
    fi

    log "Total domains after enumeration: $(wc -l < "$alldomains")"

    # Check for interesting subdomains
    grep -iE "(admin|dev|test|stage|internal|api|vpn|mail|ftp|ssh|backup|db|database|prod|cdn)" \
        "$merged" > "$OUTPUT_DIR/subdomains/interesting_subs.txt" 2>/dev/null || true

    # Subdomain takeover check (if subjack/subzy available)
    if command -v subzy &>/dev/null; then
        info "Checking subdomain takeover with subzy..."
        subzy run --targets "$merged" --timeout "$TIMEOUT" \
            --output "$OUTPUT_DIR/vuln/subdomain_takeover.txt" 2>/dev/null || true
    fi
}

# ─────────────────────────────────────────────
# URL COLLECTION
# ─────────────────────────────────────────────
collect_urls() {
    section "URL Collection"

    local alldomains="$OUTPUT_DIR/alldomains.txt"
    local allurls="$OUTPUT_DIR/urls/allurls.txt"
    local tmp_urls="$OUTPUT_DIR/urls/tmp_combined.txt"

    > "$tmp_urls"

    # Waybackurls
    if [[ "$SKIP_WAYBACK" == false ]]; then
        info "Fetching Wayback Machine URLs..."
        cat "$alldomains" | waybackurls 2>>"$OUTPUT_DIR/logs/wayback.log" \
            > "$OUTPUT_DIR/urls/waybackurls.txt" || true
        log "Wayback: $(wc -l < "$OUTPUT_DIR/urls/waybackurls.txt" 2>/dev/null || echo 0) URLs"
        cat "$OUTPUT_DIR/urls/waybackurls.txt" >> "$tmp_urls"

        # Also try Common Crawl via gau if available
        if command -v gau &>/dev/null; then
            info "Running gau (Common Crawl + OTX)..."
            cat "$alldomains" | gau --threads "$THREADS" \
                >> "$OUTPUT_DIR/urls/gau.txt" 2>/dev/null || true
            cat "$OUTPUT_DIR/urls/gau.txt" >> "$tmp_urls" 2>/dev/null || true
            log "gau: $(wc -l < "$OUTPUT_DIR/urls/gau.txt" 2>/dev/null || echo 0) URLs"
        fi
    fi

    # Katana
    if [[ "$SKIP_KATANA" == false ]]; then
        info "Running Katana crawler (depth=$DEPTH)..."
        katana -list "$alldomains" \
            -d "$DEPTH" \
            -jc \
            -kf all \
            -silent \
            -c "$THREADS" \
            -o "$OUTPUT_DIR/urls/katana.txt" \
            2>>"$OUTPUT_DIR/logs/katana.log" || true
        log "Katana: $(wc -l < "$OUTPUT_DIR/urls/katana.txt" 2>/dev/null || echo 0) URLs"
        cat "$OUTPUT_DIR/urls/katana.txt" >> "$tmp_urls" 2>/dev/null || true
    fi

    # GoSpider
    if [[ "$SKIP_GOSPIDER" == false ]]; then
        info "Running GoSpider..."
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s|^|https://|' "$alldomains" \
        | gospider -S - -t "$THREADS" --depth "$DEPTH" \
            --user-agent "$USER_AGENT" \
            2>>"$OUTPUT_DIR/logs/gospider.log" \
        | sed -n 's/.*\(https:\/\/[^ ]*\).*/\1/p' \
        >> "$OUTPUT_DIR/urls/gospider.txt" 2>/dev/null || true
        log "GoSpider: $(wc -l < "$OUTPUT_DIR/urls/gospider.txt" 2>/dev/null || echo 0) URLs"
        cat "$OUTPUT_DIR/urls/gospider.txt" >> "$tmp_urls" 2>/dev/null || true
    fi

    # Merge & deduplicate — filter static assets
    info "Merging and deduplicating URLs..."
    sort -u "$tmp_urls" \
        | grep -vE '\.(css|jpg|jpeg|png|gif|svg|ico|woff|woff2|ttf|eot|otf|map)($|\?)' \
        | grep -vE '^$' \
        | anew "$allurls" > /dev/null

    log "Total unique URLs: ${BOLD}$(wc -l < "$allurls")${RESET}"

    # Extract unique subdomains from URLs
    cat "$allurls" | unfurl -u domains 2>/dev/null \
        | anew "$OUTPUT_DIR/subdomains/all_subdomains.txt" > /dev/null || true
}

# ─────────────────────────────────────────────
# HTTP PROBING
# ─────────────────────────────────────────────
http_probe() {
    [[ "$SKIP_HTTPX" == true ]] && return
    section "HTTP Probing"

    local allurls="$OUTPUT_DIR/urls/allurls.txt"
    local httpx_all="$OUTPUT_DIR/httpx/httpx_all.txt"

    info "Running httpx on $(wc -l < "$allurls") URLs..."
    cat "$allurls" | httpx \
        -status-code \
        -title \
        -tech-detect \
        -content-length \
        -follow-redirects \
        -threads "$THREADS" \
        -rate-limit "$RATE_LIMIT" \
        -timeout "$TIMEOUT" \
        -no-color \
        -silent \
        -o "$httpx_all" \
        2>>"$OUTPUT_DIR/logs/httpx.log" || true

    log "httpx probed: $(wc -l < "$httpx_all" 2>/dev/null || echo 0) responses"

    # Split by status code
    local codes=(200 204 301 302 307 401 403 404 500 503)
    for code in "${codes[@]}"; do
        grep "\[$code\]" "$httpx_all" | cut -d' ' -f1 \
            > "$OUTPUT_DIR/httpx/httpx${code}.txt" 2>/dev/null || true
        local cnt; cnt=$(wc -l < "$OUTPUT_DIR/httpx/httpx${code}.txt" 2>/dev/null || echo 0)
        [[ $cnt -gt 0 ]] && log "  [$code]: $cnt URLs"
    done

    # Everything else
    grep -Ev '\[(200|204|301|302|307|401|403|404|500|503)\]' "$httpx_all" \
        | cut -d' ' -f1 > "$OUTPUT_DIR/httpx/httpx_other.txt" 2>/dev/null || true

    # Tech detection summary
    grep -oP '\[([^\]]+)\]' "$httpx_all" | sort | uniq -c | sort -rn \
        > "$OUTPUT_DIR/httpx/tech_summary.txt" 2>/dev/null || true

    # WordPress detection
    grep -Eoi 'https?://[^/]+/(wp-content|wp-includes|wp-admin)/?.*' \
        "$OUTPUT_DIR/httpx/httpx200.txt" \
        > "$OUTPUT_DIR/httpx/potential_wp_sites.txt" 2>/dev/null || true
}

# ─────────────────────────────────────────────
# URL CLASSIFICATION
# ─────────────────────────────────────────────
classify_urls() {
    section "URL Classification"

    local allurls="$OUTPUT_DIR/urls/allurls.txt"
    local u="$OUTPUT_DIR/urls"

    declare -A patterns=(
        ["config_js"]="config\.js"
        ["asp"]="\.asp(\?|$)"
        ["aspx"]="\.aspx(\?|$)"
        ["php"]="\.php(\?|$)"
        ["jsp"]="\.jsp(\?|$)"
        ["jspx"]="\.jspx(\?|$)"
        ["js"]="\.js(\?|$)"
        ["injection"]="="
        ["apis_all"]="api"
        ["api_docs_endpoints"]="swagger|api-docs|graphql|graphiql|/v[0-9]+/"
        ["backups"]"\.(bak|old|backup|orig|save|swp)(\?|$)"
        ["archives_dbs"]"\.(sql|zip|tar|tar\.gz|tgz|gz|rar|7z)$"
        ["secrets"]"\.(env|ini|conf|cnf|pem|key|crt|pfx|p12)$"
        ["data_configs"]"\.(json|xml|yaml|yml|toml)$"
        ["logs"]"\.(log|out|err|war)$"
        ["documents"]"\.(doc|docx|xls|xlsx|ppt|pptx|pdf|csv|odp|ods)$"
        ["dev_scripts"]"\.(py|sh|bash|rb|pl|go)$"
        ["lfi_params"]"(\?|&)(file|path|include|page|view|folder|inc|document|template)="
        ["redirect_ssrf"]"(\?|&)(url|uri|link|dest|redirect|next|return|site|callback|webhook|host|domain|port|to|out)="
        ["idor_params"]"(\?|&)(id|user|account|number|order|profile|key|token|uid|pid)="
        ["admin_panels"]"/(admin|dashboard|panel|manage|cpanel|backend|control|superuser)"
        ["dev_envs"]"(dev|test|stage|staging|uat|demo|sandbox|qa)"
        ["sensitive_keywords"]"(internal|private|secret|backup|old|tmp|temp|hidden)"
        ["ssrf_internal"]"(169\.254\.169\.254|localhost|127\.0\.0\.1|0\.0\.0\.0|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)"
        ["xss_params"]"(\?|&)(q|s|search|query|keyword|lang|input|name|value|msg|message|error|debug|output)="
        ["sqli_params"]"(\?|&)(id|cat|catid|item|product|num|page|year|month|day|sort|order)="
        ["upload_params"]"(\?|&)(upload|file|attach|attachment|img|image|photo|avatar|thumb)="
        ["debug_endpoints"]"/(debug|trace|info|status|health|ping|test|version|server-info|phpinfo)"
        ["oauth_endpoints"]"/(oauth|callback|authorize|token|auth|login|logout|sso)"
        ["aws_s3"]"(s3\.amazonaws\.com|\.s3\.amazonaws\.com|\.s3-)"
        ["jwt_endpoints"]"(token|jwt|bearer|auth)"
    )

    for name in "${!patterns[@]}"; do
        grep -iEo "https?://[^ ]+" "$allurls" 2>/dev/null \
            | grep -iE "${patterns[$name]}" \
            > "$u/${name}.txt" 2>/dev/null || true
        local cnt; cnt=$(wc -l < "$u/${name}.txt" 2>/dev/null || echo 0)
        [[ $cnt -gt 0 ]] && log "  $name: $cnt"
    done

    # Catch-all "others"
    grep -viE 'config\.js|\.asp|\.txt|\.php|\.jspx?|\.aspx|\.js|=|api|\.bak$|\.old$|\.backup$|\.orig$|\.save$|\.swp$|\.sql$|\.zip$|\.tar(\.gz)?$|\.tgz$|\.gz$|\.rar$|\.7z$|\.env$|\.ini$|\.conf$|\.cnf$|\.pem$|\.key$|\.crt$|\.pfx$|\.p12$' \
        "$allurls" > "$u/others.txt" 2>/dev/null || true
}

# ─────────────────────────────────────────────
# NUCLEI SCANNING
# ─────────────────────────────────────────────
run_nuclei() {
    [[ "$RUN_NUCLEI" == false ]] && return
    ! command -v nuclei &>/dev/null && { warn "nuclei not installed, skipping"; return; }
    section "Nuclei Vulnerability Scanning"

    local httpx200="$OUTPUT_DIR/httpx/httpx200.txt"
    local nuclei_out="$OUTPUT_DIR/vuln/nuclei_results.txt"
    local nuclei_critical="$OUTPUT_DIR/vuln/nuclei_critical.txt"

    info "Updating nuclei templates..."
    nuclei -update-templates -silent 2>/dev/null || true

    info "Running nuclei on $(wc -l < "$httpx200" 2>/dev/null || echo 0) live URLs..."
    nuclei -l "$httpx200" \
        -t "$NUCLEI_TEMPLATES" \
        -severity critical,high,medium \
        -rate-limit "$RATE_LIMIT" \
        -c "$THREADS" \
        -timeout "$TIMEOUT" \
        -silent \
        -o "$nuclei_out" \
        2>>"$OUTPUT_DIR/logs/nuclei.log" || true

    # Separate critical/high
    grep -iE "critical|high" "$nuclei_out" > "$nuclei_critical" 2>/dev/null || true

    log "Nuclei findings: $(wc -l < "$nuclei_out" 2>/dev/null || echo 0)"
    log "Critical/High: $(wc -l < "$nuclei_critical" 2>/dev/null || echo 0)"

    # Run specific checks
    # CVE checks only
    nuclei -l "$httpx200" -t "$NUCLEI_TEMPLATES/cves/" \
        -silent -o "$OUTPUT_DIR/vuln/nuclei_cves.txt" 2>/dev/null || true

    # Exposed panels
    nuclei -l "$httpx200" -t "$NUCLEI_TEMPLATES/exposed-panels/" \
        -silent -o "$OUTPUT_DIR/vuln/exposed_panels.txt" 2>/dev/null || true

    # Default credentials
    nuclei -l "$httpx200" -t "$NUCLEI_TEMPLATES/default-logins/" \
        -silent -o "$OUTPUT_DIR/vuln/default_logins.txt" 2>/dev/null || true
}

# ─────────────────────────────────────────────
# SCREENSHOTS
# ─────────────────────────────────────────────
run_screenshots() {
    [[ "$RUN_SCREENSHOTS" == false ]] && return
    section "Screenshots"

    local httpx200="$OUTPUT_DIR/httpx/httpx200.txt"

    if command -v gowitness &>/dev/null; then
        info "Taking screenshots with gowitness..."
        gowitness file -f "$httpx200" \
            --screenshot-path "$OUTPUT_DIR/screenshots/" \
            --threads "$THREADS" \
            2>>"$OUTPUT_DIR/logs/gowitness.log" || true
        log "Screenshots saved to $OUTPUT_DIR/screenshots/"
    elif command -v aquatone &>/dev/null; then
        info "Taking screenshots with aquatone..."
        cat "$httpx200" | aquatone \
            -out "$OUTPUT_DIR/screenshots/" \
            -threads "$THREADS" \
            2>>"$OUTPUT_DIR/logs/aquatone.log" || true
    else
        warn "Neither gowitness nor aquatone installed"
    fi
}

# ─────────────────────────────────────────────
# SECRETS / GITLEAKS
# ─────────────────────────────────────────────
run_gitleaks() {
    [[ "$RUN_GITLEAKS" == false ]] && return
    ! command -v gitleaks &>/dev/null && { warn "gitleaks not installed, skipping"; return; }
    section "Secret Scanning (JS/Config files)"

    local js_urls="$OUTPUT_DIR/urls/js.txt"
    local secrets_dir="$OUTPUT_DIR/leaks"
    local download_dir="$secrets_dir/downloaded"
    mkdir -p "$download_dir"

    info "Downloading JS files for secret scanning..."
    while IFS= read -r url; do
        local filename
        filename=$(echo "$url" | md5sum | cut -d' ' -f1).js
        curl -sk --max-time 10 -A "$USER_AGENT" "$url" \
            -o "$download_dir/$filename" 2>/dev/null || true
    done < "$js_urls"

    info "Running gitleaks on downloaded files..."
    gitleaks detect --source "$download_dir" \
        --report-format json \
        --report-path "$secrets_dir/gitleaks_report.json" \
        --no-git 2>>"$OUTPUT_DIR/logs/gitleaks.log" || true

    # Also grep for common secrets inline
    grep -rEio "(api_key|apikey|api-key|secret|password|passwd|token|access_key|private_key|bearer|auth_token)\s*[=:]\s*['\"]?[A-Za-z0-9_/+=-]{20,}" \
        "$download_dir/" > "$secrets_dir/grep_secrets.txt" 2>/dev/null || true

    log "Secrets scan done. Check: $secrets_dir/"
}

# ─────────────────────────────────────────────
# S3 / CLOUD STORAGE CHECK
# ─────────────────────────────────────────────
cloud_storage_check() {
    section "Cloud Storage Buckets"

    local alldomains="$OUTPUT_DIR/alldomains.txt"
    local allurls="$OUTPUT_DIR/urls/allurls.txt"

    # S3 buckets from DNS
    if command -v dig &>/dev/null; then
        while IFS= read -r domain; do
            dig "$domain" +short 2>/dev/null | grep -i "s3.amazon" >> "$OUTPUT_DIR/dns/s3_amazon.txt" 2>/dev/null || true
        done < "$alldomains"
    fi

    # S3 from URLs
    grep -iE "(s3\.amazonaws\.com|\.s3\.amazonaws\.com|\.s3-|storage\.googleapis\.com|\.blob\.core\.windows\.net)" \
        "$allurls" > "$OUTPUT_DIR/dns/cloud_storage_urls.txt" 2>/dev/null || true

    # Check if S3 buckets are accessible
    if [[ -s "$OUTPUT_DIR/dns/cloud_storage_urls.txt" ]]; then
        info "Checking cloud storage accessibility..."
        while IFS= read -r url; do
            local code
            code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "000")
            if [[ "$code" == "200" || "$code" == "403" ]]; then
                echo "[$code] $url" >> "$OUTPUT_DIR/dns/cloud_storage_results.txt"
                [[ "$code" == "200" ]] && warn "PUBLIC bucket: $url"
            fi
        done < "$OUTPUT_DIR/dns/cloud_storage_urls.txt"
    fi

    log "Cloud storage check done"
}

# ─────────────────────────────────────────────
# NOTIFICATIONS
# ─────────────────────────────────────────────
send_notification() {
    [[ "$NOTIFY" == false ]] && return

    local total_subs total_urls total_httpx200 total_vulns
    total_subs=$(wc -l < "$OUTPUT_DIR/subdomains/all_subdomains.txt" 2>/dev/null || echo 0)
    total_urls=$(wc -l < "$OUTPUT_DIR/urls/allurls.txt" 2>/dev/null || echo 0)
    total_httpx200=$(wc -l < "$OUTPUT_DIR/httpx/httpx200.txt" 2>/dev/null || echo 0)
    total_vulns=$(wc -l < "$OUTPUT_DIR/vuln/nuclei_results.txt" 2>/dev/null || echo 0)

    local msg="🔍 *Recon Complete*
Target: ${DOMAIN:-$DOMAIN_LIST}
Subdomains: $total_subs
URLs: $total_urls
Live (200): $total_httpx200
Nuclei findings: $total_vulns
Output: $OUTPUT_DIR"

    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$msg\"}" "$SLACK_WEBHOOK" > /dev/null 2>&1 || true
        log "Slack notification sent"
    fi

    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"content\":\"$msg\"}" "$DISCORD_WEBHOOK" > /dev/null 2>&1 || true
        log "Discord notification sent"
    fi
}

# ─────────────────────────────────────────────
# SUMMARY REPORT
# ─────────────────────────────────────────────
generate_report() {
    section "Generating Summary Report"

    local report="$OUTPUT_DIR/reports/summary.md"
    local total_subs total_urls live200 live403

    total_subs=$(wc -l < "$OUTPUT_DIR/subdomains/all_subdomains.txt" 2>/dev/null || echo 0)
    total_urls=$(wc -l < "$OUTPUT_DIR/urls/allurls.txt" 2>/dev/null || echo 0)
    live200=$(wc -l < "$OUTPUT_DIR/httpx/httpx200.txt" 2>/dev/null || echo 0)
    live403=$(wc -l < "$OUTPUT_DIR/httpx/httpx403.txt" 2>/dev/null || echo 0)

    cat > "$report" <<EOF
# Recon Report — $(date)

## Target
- Domain(s): **${DOMAIN:-$DOMAIN_LIST}**
- Output dir: \`$OUTPUT_DIR\`

## Summary
| Metric | Count |
|---|---|
| Subdomains found | $total_subs |
| Total unique URLs | $total_urls |
| Live URLs (200) | $live200 |
| Forbidden (403) | $live403 |
| Zone transfers | $(wc -l < "$OUTPUT_DIR/dns/zone_transfers.txt" 2>/dev/null || echo 0) |
| Nuclei findings | $(wc -l < "$OUTPUT_DIR/vuln/nuclei_results.txt" 2>/dev/null || echo 0) |

## URL Classification
| Category | Count |
|---|---|
EOF

    local url_dir="$OUTPUT_DIR/urls"
    for f in "$url_dir"/*.txt; do
        [[ "$f" == *allurls* ]] && continue
        local name count
        name=$(basename "$f" .txt)
        count=$(wc -l < "$f" 2>/dev/null || echo 0)
        [[ $count -gt 0 ]] && echo "| $name | $count |" >> "$report"
    done

    cat >> "$report" <<EOF

## High-Value Findings
### Admin Panels
\`\`\`
$(cat "$OUTPUT_DIR/urls/admin_panels.txt" 2>/dev/null | head -20 || echo "None found")
\`\`\`

### Potential LFI Parameters
\`\`\`
$(cat "$OUTPUT_DIR/urls/lfi_params.txt" 2>/dev/null | head -20 || echo "None found")
\`\`\`

### SSRF/Redirect Parameters
\`\`\`
$(cat "$OUTPUT_DIR/urls/redirect_ssrf.txt" 2>/dev/null | head -20 || echo "None found")
\`\`\`

### Interesting Subdomains
\`\`\`
$(cat "$OUTPUT_DIR/subdomains/interesting_subs.txt" 2>/dev/null | head -20 || echo "None found")
\`\`\`

## Recommendations
- Review all 403 URLs for bypass techniques
- Test LFI parameter files manually
- Check SSRF/redirect parameters
- Manually verify nuclei findings
- Review exposed admin panels

EOF

    log "Report saved to: $report"
    echo -e "\n${BOLD}${GREEN}════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${GREEN}  Recon Complete!${RESET}"
    echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
    printf "  %-22s %s\n" "Output dir:"     "$OUTPUT_DIR"
    printf "  %-22s %s\n" "Subdomains:"     "$total_subs"
    printf "  %-22s %s\n" "Total URLs:"     "$total_urls"
    printf "  %-22s %s\n" "Live (200):"     "$live200"
    printf "  %-22s %s\n" "Forbidden (403):" "$live403"
    echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}\n"
}

# ─────────────────────────────────────────────
# ARG PARSING
# ─────────────────────────────────────────────
parse_args() {
    [[ $# -eq 0 ]] && usage

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d)   DOMAIN="$2"; shift 2 ;;
            -l)   DOMAIN_LIST="$2"; shift 2 ;;
            -o)   OUTPUT_DIR="$2"; shift 2 ;;
            -t)   THREADS="$2"; shift 2 ;;
            -r)   RATE_LIMIT="$2"; shift 2 ;;
            -D)   DEPTH="$2"; shift 2 ;;
            -T)   TIMEOUT="$2"; shift 2 ;;
            -w)   WORDLIST="$2"; shift 2 ;;
            -R)   CUSTOM_RESOLVERS="$2"; shift 2 ;;
            -v)   VERBOSE=true; shift ;;
            --skip-subfinder)     SKIP_SUBFINDER=true; shift ;;
            --skip-wayback)       SKIP_WAYBACK=true; shift ;;
            --skip-katana)        SKIP_KATANA=true; shift ;;
            --skip-gospider)      SKIP_GOSPIDER=true; shift ;;
            --skip-httpx)         SKIP_HTTPX=true; shift ;;
            --skip-zone-transfer) SKIP_ZONE_TRANSFER=true; shift ;;
            --screenshots)        RUN_SCREENSHOTS=true; shift ;;
            --nuclei)             RUN_NUCLEI=true; shift ;;
            --gitleaks)           RUN_GITLEAKS=true; shift ;;
            --resume)             RESUME=true; shift ;;
            --slack)              NOTIFY=true; SLACK_WEBHOOK="$2"; shift 2 ;;
            --discord)            NOTIFY=true; DISCORD_WEBHOOK="$2"; shift 2 ;;
            -h|--help)            usage ;;
            *) err "Unknown option: $1"; usage ;;
        esac
    done

    # Validation
    if [[ -z "$DOMAIN" && -z "$DOMAIN_LIST" ]]; then
        err "Provide -d <domain> or -l <file>"
        exit 1
    fi
    if [[ -n "$DOMAIN_LIST" && ! -f "$DOMAIN_LIST" ]]; then
        err "Domain list file not found: $DOMAIN_LIST"
        exit 1
    fi
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
main() {
    parse_args "$@"
    banner
    check_tools
    setup_dirs
    prepare_domains

    zone_transfer_check
    subdomain_enum
    collect_urls
    http_probe
    classify_urls
    cloud_storage_check
    run_nuclei
    run_screenshots
    run_gitleaks
    generate_report
    send_notification
}

main "$@"
