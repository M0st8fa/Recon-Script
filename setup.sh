#!/usr/bin/env bash
# ============================================================
#  setup.sh — Bug Bounty Recon Toolchain Setup
#  Target OS : Ubuntu 20.04 / 22.04 / 24.04 LTS
#  Run as    : sudo bash setup.sh
#              OR: bash setup.sh (will sudo internally)
# ============================================================

set -euo pipefail

# ─────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; RESET='\033[0m'

# ─────────────────────────────────────────────
# GLOBALS
# ─────────────────────────────────────────────
GO_VERSION="1.22.4"
GO_ARCH="amd64"
GO_TARBALL="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
GO_INSTALL_DIR="/usr/local"
GOPATH_DIR="$HOME/go"
TOOLS_DIR="$HOME/tools"
WORDLISTS_DIR="/opt/wordlists"
LOG_FILE="/tmp/recon_setup_$(date +%Y%m%d_%H%M%S).log"
ERRORS=0
INSTALLED=()
FAILED=()
SKIPPED=()

# ─────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────
log()     { echo -e "${GREEN}[+]${RESET} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*" | tee -a "$LOG_FILE"; }
err()     { echo -e "${RED}[-]${RESET} $*" | tee -a "$LOG_FILE"; ((ERRORS++)); }
info()    { echo -e "${CYAN}[*]${RESET} $*" | tee -a "$LOG_FILE"; }
section() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${BLUE}  $*${RESET}" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" | tee -a "$LOG_FILE"
}
ok()      { log "$1 installed ✓"; INSTALLED+=("$1"); }
skip()    { warn "$1 already installed — skipping"; SKIPPED+=("$1"); }
fail()    { err "$1 FAILED — check $LOG_FILE"; FAILED+=("$1"); }

# ─────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────
banner() {
cat <<'EOF'

  ╔══════════════════════════════════════════════════╗
  ║    Bug Bounty Recon — Ubuntu Cloud Setup v2.0    ║
  ║    Sets up Go, all required & optional tools,    ║
  ║    DNS utils, wordlists, and shell environment   ║
  ╚══════════════════════════════════════════════════╝

EOF
    echo -e "  ${CYAN}Log file: $LOG_FILE${RESET}\n"
}

# ─────────────────────────────────────────────
# ROOT / SUDO CHECK
# ─────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        warn "Not running as root. Will use sudo for system-level commands."
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# ─────────────────────────────────────────────
# DETECT UBUNTU VERSION
# ─────────────────────────────────────────────
check_os() {
    section "System Check"

    if [[ ! -f /etc/os-release ]]; then
        err "Cannot detect OS. This script targets Ubuntu."
        exit 1
    fi

    source /etc/os-release
    info "OS: $PRETTY_NAME"
    info "Kernel: $(uname -r)"
    info "Architecture: $(uname -m)"
    info "User: $(whoami) (HOME=$HOME)"
    info "CPU cores: $(nproc)"
    info "RAM: $(free -h | awk '/^Mem:/{print $2}')"
    info "Disk free: $(df -h / | awk 'NR==2{print $4}')"

    if [[ "$ID" != "ubuntu" ]]; then
        warn "This script is designed for Ubuntu. Proceeding anyway — some steps may fail on $ID."
    fi

    case "$VERSION_ID" in
        "20.04"|"22.04"|"24.04")
            log "Ubuntu $VERSION_ID — fully supported" ;;
        *)
            warn "Ubuntu $VERSION_ID — not tested, may work" ;;
    esac

    echo ""
}

# ─────────────────────────────────────────────
# SYSTEM PACKAGES
# ─────────────────────────────────────────────
install_system_packages() {
    section "System Packages (apt)"

    info "Updating package lists..."
    $SUDO apt-get update -qq 2>>"$LOG_FILE"

    info "Upgrading existing packages..."
    $SUDO apt-get upgrade -y -qq 2>>"$LOG_FILE" || warn "Some upgrades failed — continuing"

    local packages=(
        # Essentials
        curl wget git unzip tar jq
        # DNS tools
        dnsutils bind9-dnsutils
        # Network / HTTP
        nmap masscan whois netcat-openbsd
        # Python
        python3 python3-pip python3-venv pipx
        # Build tools (needed by some Go tools + C extensions)
        build-essential gcc make cmake
        # SSL / Crypto
        openssl ca-certificates libssl-dev
        # Misc utils
        tree htop tmux screen vim nano
        # Chromium (for gowitness screenshots)
        chromium-browser chromium
        # Ruby (for some recon tools)
        ruby ruby-dev
        # File tools
        file p7zip-full rar unrar
    )

    info "Installing ${#packages[@]} packages..."
    for pkg in "${packages[@]}"; do
        if $SUDO apt-get install -y -qq "$pkg" >> "$LOG_FILE" 2>&1; then
            verbose "  apt: $pkg ✓"
        else
            warn "  apt: $pkg — skipped (may not exist on this Ubuntu version)"
        fi
    done

    log "System packages done"
}

verbose() { echo -e "${MAGENTA}[v]${RESET} $*" >> "$LOG_FILE"; }

# ─────────────────────────────────────────────
# GO LANGUAGE
# ─────────────────────────────────────────────
install_go() {
    section "Go Language ($GO_VERSION)"

    # Check if already installed and at correct version
    if command -v go &>/dev/null; then
        local current_ver
        current_ver=$(go version | awk '{print $3}' | sed 's/go//')
        if [[ "$current_ver" == "$GO_VERSION" ]]; then
            skip "Go $GO_VERSION"
            setup_go_env
            return
        else
            warn "Go $current_ver installed — upgrading to $GO_VERSION"
            $SUDO rm -rf /usr/local/go
        fi
    fi

    info "Downloading Go $GO_VERSION..."
    wget -q --show-progress "$GO_URL" -O "/tmp/$GO_TARBALL" 2>>"$LOG_FILE" || {
        fail "Go download"
        return
    }

    info "Installing Go to $GO_INSTALL_DIR..."
    $SUDO tar -C "$GO_INSTALL_DIR" -xzf "/tmp/$GO_TARBALL" >> "$LOG_FILE" 2>&1 || {
        fail "Go extraction"
        return
    }

    rm -f "/tmp/$GO_TARBALL"
    setup_go_env
    ok "Go $GO_VERSION"
}

setup_go_env() {
    export GOROOT="$GO_INSTALL_DIR/go"
    export GOPATH="$GOPATH_DIR"
    export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"

    mkdir -p "$GOPATH_DIR"/{bin,src,pkg}

    # Write to shell profiles
    local profiles=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile")
    local go_block='
# ── Go Environment ──────────────────────────
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
# ────────────────────────────────────────────'

    for profile in "${profiles[@]}"; do
        if [[ -f "$profile" ]] && ! grep -q "GOROOT=/usr/local/go" "$profile"; then
            echo "$go_block" >> "$profile"
            info "  Go env added to $profile"
        fi
    done

    info "Go $(go version 2>/dev/null | awk '{print $3}') ready at $(which go 2>/dev/null || echo 'path not yet refreshed')"
}

# ─────────────────────────────────────────────
# GO TOOL INSTALLER HELPER
# ─────────────────────────────────────────────
install_go_tool() {
    local name="$1"
    local module="$2"

    if command -v "$name" &>/dev/null; then
        skip "$name"
        return
    fi

    info "Installing $name..."
    if go install -v "$module" >> "$LOG_FILE" 2>&1; then
        # Ensure binary is accessible
        if [[ -f "$GOPATH_DIR/bin/$name" ]]; then
            ok "$name"
        else
            # Some tools install with different binary names — check anyway
            ok "$name (binary may have different name — check $GOPATH_DIR/bin/)"
        fi
    else
        fail "$name"
    fi
}

# ─────────────────────────────────────────────
# REQUIRED RECON TOOLS
# ─────────────────────────────────────────────
install_required_tools() {
    section "Required Recon Tools"

    install_go_tool "subfinder"    "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    install_go_tool "waybackurls"  "github.com/tomnomnom/waybackurls@latest"
    install_go_tool "katana"       "github.com/projectdiscovery/katana/cmd/katana@latest"
    install_go_tool "gospider"     "github.com/jaeles-project/gospider@latest"
    install_go_tool "httpx"        "github.com/projectdiscovery/httpx/cmd/httpx@latest"
    install_go_tool "anew"         "github.com/tomnomnom/anew@latest"
    install_go_tool "unfurl"       "github.com/tomnomnom/unfurl@latest"
}

# ─────────────────────────────────────────────
# OPTIONAL / ENHANCEMENT TOOLS
# ─────────────────────────────────────────────
install_optional_tools() {
    section "Optional Enhancement Tools"

    # URL & Discovery
    install_go_tool "gau"          "github.com/lc/gau/v2/cmd/gau@latest"
    install_go_tool "dnsx"         "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    install_go_tool "amass"        "github.com/owasp-amass/amass/v4/...@master"

    # Takeover
    install_go_tool "subzy"        "github.com/PentestPad/subzy@latest"

    # Vulnerability Scanning
    install_go_tool "nuclei"       "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"

    # Screenshots
    install_go_tool "gowitness"    "github.com/sensepost/gowitness@latest"

    # Secrets
    install_go_tool "gitleaks"     "github.com/gitleaks/gitleaks/v8@latest"

    # Extra PD tools
    install_go_tool "naabu"        "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
    install_go_tool "tlsx"         "github.com/projectdiscovery/tlsx/cmd/tlsx@latest"
    install_go_tool "cdncheck"     "github.com/projectdiscovery/cdncheck/cmd/cdncheck@latest"
    install_go_tool "mapcidr"      "github.com/projectdiscovery/mapcidr/cmd/mapcidr@latest"
    install_go_tool "notify"       "github.com/projectdiscovery/notify/cmd/notify@latest"

    # TomNomNom essentials
    install_go_tool "assetfinder"  "github.com/tomnomnom/assetfinder@latest"
    install_go_tool "gf"           "github.com/tomnomnom/gf@latest"
    install_go_tool "httprobe"     "github.com/tomnomnom/httprobe@latest"
    install_go_tool "meg"          "github.com/tomnomnom/meg@latest"
    install_go_tool "qsreplace"    "github.com/tomnomnom/qsreplace@latest"
    install_go_tool "fff"          "github.com/tomnomnom/fff@latest"

    # Other recon tools
    install_go_tool "hakrawler"    "github.com/hakluke/hakrawler@latest"
    install_go_tool "gauplus"      "github.com/bp0lr/gauplus@latest"
    install_go_tool "puredns"      "github.com/d3mondev/puredns/v2@latest"
    install_go_tool "alterx"       "github.com/projectdiscovery/alterx/cmd/alterx@latest"

    # Param discovery
    install_go_tool "arjun"        "github.com/s0md3v/uro@latest"        # URL dedup
    install_go_tool "cariddi"      "github.com/edoardottt/cariddi/cmd/cariddi@latest"

    # Cloud
    install_go_tool "cloudlist"    "github.com/projectdiscovery/cloudlist/cmd/cloudlist@latest"
}

# ─────────────────────────────────────────────
# PYTHON TOOLS
# ─────────────────────────────────────────────
install_python_tools() {
    section "Python Tools"

    # Ensure pip is up to date
    python3 -m pip install --upgrade pip --quiet 2>>"$LOG_FILE" || true

    local pip_tools=(
        "arjun"           # HTTP parameter discovery
        "dnsgen"          # DNS wordlist generation
        "uro"             # URL deduplication
        "paramspider"     # Parameter spider
        "waymore"         # More wayback + cc URLs
    )

    for tool in "${pip_tools[@]}"; do
        info "pip: $tool..."
        if python3 -m pip install "$tool" --quiet >> "$LOG_FILE" 2>&1; then
            ok "$tool (pip)"
        else
            # Try pipx as fallback
            if pipx install "$tool" >> "$LOG_FILE" 2>&1; then
                ok "$tool (pipx)"
            else
                fail "$tool (pip/pipx)"
            fi
        fi
    done

    # Ensure pipx path is configured
    pipx ensurepath >> "$LOG_FILE" 2>&1 || true
}

# ─────────────────────────────────────────────
# GF PATTERNS
# ─────────────────────────────────────────────
install_gf_patterns() {
    section "GF Patterns (tomnomnom/gf)"

    if ! command -v gf &>/dev/null; then
        warn "gf not installed — skipping patterns"
        return
    fi

    local gf_dir="$HOME/.gf"
    mkdir -p "$gf_dir"

    local patterns_repo="https://github.com/1ndianl33t/Gf-Patterns"
    local patterns_dir="$TOOLS_DIR/Gf-Patterns"

    if [[ ! -d "$patterns_dir" ]]; then
        info "Cloning GF patterns..."
        git clone -q "$patterns_repo" "$patterns_dir" >> "$LOG_FILE" 2>&1 || {
            fail "GF patterns clone"
            return
        }
    fi

    cp "$patterns_dir"/*.json "$gf_dir/" 2>/dev/null || true

    # Also clone tomnomnom's original patterns
    local tom_patterns="$TOOLS_DIR/tomnomnom-gf"
    if [[ ! -d "$tom_patterns" ]]; then
        git clone -q "https://github.com/tomnomnom/gf" "$tom_patterns" >> "$LOG_FILE" 2>&1 || true
    fi
    cp "$tom_patterns/examples/"*.json "$gf_dir/" 2>/dev/null || true

    log "GF patterns installed to $gf_dir ($(ls "$gf_dir"/*.json 2>/dev/null | wc -l) patterns)"
}

# ─────────────────────────────────────────────
# NUCLEI TEMPLATES
# ─────────────────────────────────────────────
install_nuclei_templates() {
    section "Nuclei Templates"

    if ! command -v nuclei &>/dev/null; then
        warn "nuclei not installed — skipping templates"
        return
    fi

    info "Updating nuclei templates..."
    nuclei -update-templates -silent >> "$LOG_FILE" 2>&1 || {
        warn "nuclei -update-templates failed, trying manual clone..."
        local templates_dir="$HOME/nuclei-templates"
        if [[ ! -d "$templates_dir" ]]; then
            git clone -q "https://github.com/projectdiscovery/nuclei-templates" \
                "$templates_dir" >> "$LOG_FILE" 2>&1 || fail "nuclei-templates clone"
        else
            git -C "$templates_dir" pull -q >> "$LOG_FILE" 2>&1 || true
        fi
    }

    local tcount
    tcount=$(find "$HOME/nuclei-templates" -name "*.yaml" 2>/dev/null | wc -l || echo 0)
    log "Nuclei templates ready: $tcount templates"
}

# ─────────────────────────────────────────────
# WORDLISTS
# ─────────────────────────────────────────────
install_wordlists() {
    section "Wordlists"

    $SUDO mkdir -p "$WORDLISTS_DIR"/{dns,web,fuzz,params}
    $SUDO chown -R "$(whoami):$(whoami)" "$WORDLISTS_DIR"

    # SecLists (the comprehensive collection)
    local seclists_dir="$WORDLISTS_DIR/SecLists"
    if [[ ! -d "$seclists_dir" ]]; then
        info "Cloning SecLists (~1GB — this may take a while)..."
        git clone -q --depth 1 \
            "https://github.com/danielmiessler/SecLists.git" \
            "$seclists_dir" >> "$LOG_FILE" 2>&1 || {
            fail "SecLists clone"
            return
        }
        ok "SecLists"
    else
        skip "SecLists (already at $seclists_dir)"
    fi

    # Symlink the most commonly used wordlists to expected locations
    local dns_top5k="$seclists_dir/Discovery/DNS/subdomains-top1million-5000.txt"
    local dns_top1m="$seclists_dir/Discovery/DNS/subdomains-top1million.txt"
    local web_common="$seclists_dir/Discovery/Web-Content/common.txt"
    local web_raft="$seclists_dir/Discovery/Web-Content/raft-large-words.txt"
    local params_list="$seclists_dir/Discovery/Web-Content/burp-parameter-names.txt"

    [[ -f "$dns_top5k" ]]  && ln -sf "$dns_top5k" "$WORDLISTS_DIR/dns/subdomains-top5000.txt"   2>/dev/null || true
    [[ -f "$dns_top1m" ]]  && ln -sf "$dns_top1m"  "$WORDLISTS_DIR/dns/subdomains-top1m.txt"    2>/dev/null || true
    [[ -f "$web_common" ]] && ln -sf "$web_common"  "$WORDLISTS_DIR/web/common.txt"             2>/dev/null || true
    [[ -f "$web_raft" ]]   && ln -sf "$web_raft"    "$WORDLISTS_DIR/web/raft-large.txt"         2>/dev/null || true
    [[ -f "$params_list" ]]&& ln -sf "$params_list" "$WORDLISTS_DIR/params/burp-params.txt"     2>/dev/null || true

    # Download high-quality DNS resolvers
    info "Downloading DNS resolvers list..."
    wget -q "https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt" \
        -O "$WORDLISTS_DIR/dns/resolvers.txt" >> "$LOG_FILE" 2>&1 \
        && log "DNS resolvers: $(wc -l < "$WORDLISTS_DIR/dns/resolvers.txt") resolvers" \
        || warn "Could not download resolvers list"

    # Download best-dns-wordlist from assetnote
    info "Downloading Assetnote DNS wordlist..."
    wget -q "https://wordlists-cdn.assetnote.io/data/manual/best-dns-wordlist.txt" \
        -O "$WORDLISTS_DIR/dns/best-dns-wordlist.txt" >> "$LOG_FILE" 2>&1 \
        && log "Assetnote DNS wordlist: $(wc -l < "$WORDLISTS_DIR/dns/best-dns-wordlist.txt") entries" \
        || warn "Could not download Assetnote wordlist (large file, may have timed out)"

    log "Wordlists directory: $WORDLISTS_DIR"
    du -sh "$WORDLISTS_DIR" 2>/dev/null | awk '{print "  Total size: "$1}'
}

# ─────────────────────────────────────────────
# SUBFINDER CONFIG (API KEYS)
# ─────────────────────────────────────────────
configure_subfinder() {
    section "Subfinder Configuration"

    local config_dir="$HOME/.config/subfinder"
    local config_file="$config_dir/provider-config.yaml"

    mkdir -p "$config_dir"

    if [[ -f "$config_file" ]]; then
        skip "subfinder config (already exists at $config_file)"
        return
    fi

    cat > "$config_file" <<'EOF'
# Subfinder Provider Configuration
# Add your API keys here to unlock more subdomain sources.
# Each free-tier account gives you significantly more results.
#
# Sign up at each provider and paste your key after the colon.
# ──────────────────────────────────────────────────────────

# https://www.virustotal.com/gui/my-apikey
virustotal:
  - ""

# https://app.censys.io/account/api
censys:
  - ""   # format: api_id:api_secret

# https://www.shodan.io/dashboard
shodan:
  - ""

# https://securitytrails.com/app/account/credentials
securitytrails:
  - ""

# https://account.chaos.projectdiscovery.io/
chaos:
  - ""

# https://binaryedge.io/
binaryedge:
  - ""

# https://github.com/settings/tokens
github:
  - ""

# https://fofa.info/userInfo
fofa:
  - ""   # format: email:key

# https://hunter.how/
hunter:
  - ""

# https://www.zoomeye.org/profile
zoomeye:
  - ""

# https://fullhunt.io/user/profile
fullhunt:
  - ""

# https://app.netlas.io/profile/
netlas:
  - ""

# https://leakix.net/settings
leakix:
  - ""

# https://app.intelx.io/account?tab=developer
intelx:
  - ""
EOF

    log "Subfinder config template created: $config_file"
    warn "Add your API keys to $config_file for maximum coverage"
}

# ─────────────────────────────────────────────
# SHELL ENVIRONMENT
# ─────────────────────────────────────────────
configure_shell() {
    section "Shell Environment"

    local bashrc="$HOME/.bashrc"
    local marker="# ── recon.sh environment ──"

    if grep -q "$marker" "$bashrc" 2>/dev/null; then
        skip "Shell environment (already configured in $bashrc)"
        return
    fi

    cat >> "$bashrc" <<EOF

$marker
# Go
export GOROOT=/usr/local/go
export GOPATH=\$HOME/go
export PATH=\$GOROOT/bin:\$GOPATH/bin:\$PATH

# Recon wordlists
export WORDLISTS="$WORDLISTS_DIR"
export SECLISTS="$WORDLISTS_DIR/SecLists"
export RESOLVERS="$WORDLISTS_DIR/dns/resolvers.txt"
export DNS_WORDLIST="$WORDLISTS_DIR/dns/subdomains-top5000.txt"

# Recon aliases
alias recon='bash \$HOME/recon.sh'
alias pdtools='ls \$GOPATH/bin/ | grep -v "^go"'
alias httpx200='cat httpx_all.txt | grep "\[200\]"'
alias httpx403='cat httpx_all.txt | grep "\[403\]"'
alias livedomains='httpx -silent -no-color'
alias subclean='sort -u | grep -v "^\*\."'

# ─────────────────────────────────────────────
EOF

    log "Shell environment configured in $bashrc"
    log "Run: source ~/.bashrc  (or open a new terminal)"
}

# ─────────────────────────────────────────────
# TMUX CONFIG (for long-running cloud scans)
# ─────────────────────────────────────────────
configure_tmux() {
    section "Tmux Configuration"

    local tmux_conf="$HOME/.tmux.conf"

    if [[ -f "$tmux_conf" ]]; then
        skip "tmux config"
        return
    fi

    cat > "$tmux_conf" <<'EOF'
# ── tmux.conf for recon sessions ──────────────────
# Reload with: tmux source-file ~/.tmux.conf

# Set prefix to Ctrl+a (easier than Ctrl+b on cloud)
unbind C-b
set-option -g prefix C-a
bind-key C-a send-prefix

# Enable mouse
set -g mouse on

# Increase scroll-back buffer
set-option -g history-limit 50000

# Status bar
set -g status-bg colour234
set -g status-fg colour137
set -g status-left '#[fg=green][#S] '
set -g status-right '#[fg=yellow]#(uptime | cut -d, -f1 | awk "{print \$NF}") #[fg=cyan]%H:%M %d-%b'
set -g status-right-length 60

# Window/pane numbering starts at 1
set -g base-index 1
setw -g pane-base-index 1

# Rename windows to current command
setw -g automatic-rename on

# Fast pane switching: Alt+Arrow
bind -n M-Left  select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up    select-pane -U
bind -n M-Down  select-pane -D

# Split panes with | and -
bind | split-window -h
bind - split-window -v

# Quick window creation
bind c new-window

# ── Recon session shortcuts ───────────────────────
# Bind F5 to start a new named recon session
bind F5 new-session -s recon
EOF

    log "Tmux config written to $tmux_conf"
    info "Tip: Use 'tmux new -s recon' to start a persistent session on your cloud server"
}

# ─────────────────────────────────────────────
# VERIFY ALL TOOLS
# ─────────────────────────────────────────────
verify_tools() {
    section "Verification"

    local required_tools=(
        "subfinder" "waybackurls" "katana" "gospider"
        "httpx" "anew" "unfurl" "dig"
    )
    local optional_tools=(
        "gau" "dnsx" "nuclei" "gowitness" "gitleaks"
        "naabu" "tlsx" "gf" "assetfinder" "httprobe"
        "subzy" "puredns" "alterx" "notify" "cdncheck"
        "hakrawler" "qsreplace" "cariddi" "cloudlist"
    )

    local all_ok=true

    echo -e "\n${BOLD}Required:${RESET}"
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            echo -e "  ${GREEN}✓${RESET} $tool  $(command -v "$tool")"
        else
            echo -e "  ${RED}✗${RESET} $tool  ${RED}NOT FOUND${RESET}"
            all_ok=false
        fi
    done

    echo -e "\n${BOLD}Optional:${RESET}"
    for tool in "${optional_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            echo -e "  ${GREEN}✓${RESET} $tool"
        else
            echo -e "  ${YELLOW}○${RESET} $tool  (not installed)"
        fi
    done

    echo ""
    if [[ "$all_ok" == true ]]; then
        log "All required tools are present ✓"
    else
        err "Some required tools are missing — check $LOG_FILE"
    fi
}

# ─────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────
print_summary() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${GREEN}  Setup Complete!${RESET}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    printf "  ${GREEN}%-20s${RESET} %s\n" "Installed:"  "${#INSTALLED[@]} tools"
    printf "  ${YELLOW}%-20s${RESET} %s\n" "Skipped:"   "${#SKIPPED[@]} (already present)"
    printf "  ${RED}%-20s${RESET} %s\n"   "Failed:"    "${#FAILED[@]} tools"
    printf "  %-20s %s\n"                 "Log:"       "$LOG_FILE"
    echo ""

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        echo -e "  ${RED}Failed tools: ${FAILED[*]}${RESET}"
        echo -e "  ${YELLOW}Check $LOG_FILE for details${RESET}"
        echo ""
    fi

    echo -e "  ${BOLD}Next steps:${RESET}"
    echo -e "  1. ${CYAN}source ~/.bashrc${RESET}                    (reload environment)"
    echo -e "  2. ${CYAN}nano ~/.config/subfinder/provider-config.yaml${RESET}  (add API keys)"
    echo -e "  3. ${CYAN}chmod +x recon.sh${RESET}                   (if not already)"
    echo -e "  4. ${CYAN}./recon.sh -d example.com${RESET}           (run your first scan)"
    echo ""
    echo -e "  ${BOLD}Wordlists:${RESET}   $WORDLISTS_DIR"
    echo -e "  ${BOLD}Go binaries:${RESET} $GOPATH_DIR/bin"
    echo -e "  ${BOLD}Tmux tip:${RESET}    tmux new -s recon  (persistent session)"
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
main() {
    # Touch log file early
    touch "$LOG_FILE"
    echo "Setup started: $(date)" > "$LOG_FILE"

    banner
    check_root
    check_os
    install_system_packages
    install_go
    install_required_tools
    install_optional_tools
    install_python_tools
    install_gf_patterns
    install_nuclei_templates
    install_wordlists
    configure_subfinder
    configure_shell
    configure_tmux
    verify_tools
    print_summary
}

# ─────────────────────────────────────────────
# TRAP — catch unexpected exits
# ─────────────────────────────────────────────
trap 'echo -e "\n${RED}[!] Script interrupted. Log: $LOG_FILE${RESET}"' INT TERM

main "$@"
