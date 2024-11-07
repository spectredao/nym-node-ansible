#!/bin/bash
set -euo pipefail

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

readonly NETWORK_DEVICE=$(ip route show default | awk '/default/ {print $5; exit}')
readonly TUNNEL_INTERFACE="nymtun0"
readonly WG_TUNNEL_INTERFACE="nymwg"
readonly IPV4_FORWARDING_SETTING="net.ipv4.ip_forward=1"
readonly IPV6_FORWARDING_SETTING="net.ipv6.conf.all.forwarding=1"

trap 'echo "Error on line $LINENO. Exit code: $?"' ERR

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log "Error: $1 is not installed"
        exit 1
    fi
}

check_required_packages() {
    local packages=("iptables-persistent" "jq" "curl")
    
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            log "Installing $pkg..."
            echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
            echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
            apt-get update && apt-get install -y "$pkg"
        fi
    done
}

iptables_rule_exists() {
    local table=$1
    local rule=$2
    iptables -t "$table" -C "$rule" 2>/dev/null
    return $?
}

ip6tables_rule_exists() {
    local table=$1
    local rule=$2
    ip6tables -t "$table" -C "$rule" 2>/dev/null
    return $?
}

fetch_ipv6_address_nym_tun() {
    local ipv6_global_address
    ipv6_global_address=$(ip -6 addr show "$TUNNEL_INTERFACE" scope global | grep inet6 | awk '{print $2}' | head -n 1)

    if [[ -z "$ipv6_global_address" ]]; then
        log "No globally routable IPv6 address found on $TUNNEL_INTERFACE"
        exit 1
    fi

    log "Using IPv6 address: $ipv6_global_address"
}

fetch_and_display_ipv6() {
    local ipv6_address
    ipv6_address=$(ip -6 addr show "${NETWORK_DEVICE}" scope global | grep inet6 | awk '{print $2}')

    if [[ -z "$ipv6_address" ]]; then
        log "No global IPv6 address found on ${NETWORK_DEVICE}"
    else
        log "IPv6 address on ${NETWORK_DEVICE}: $ipv6_address"
    fi
}

adjust_ip_forwarding() {
    if ! grep -q "^$IPV6_FORWARDING_SETTING" /etc/sysctl.conf; then
        echo "$IPV6_FORWARDING_SETTING" >> /etc/sysctl.conf
    fi
    if ! grep -q "^$IPV4_FORWARDING_SETTING" /etc/sysctl.conf; then
        echo "$IPV4_FORWARDING_SETTING" >> /etc/sysctl.conf
    fi
    sysctl -p /etc/sysctl.conf
}

apply_iptables_rules_wg() {
    log "Applying IPtables rules for WireGuard..."

    local rules=(
        "FORWARD -i $WG_TUNNEL_INTERFACE -o $NETWORK_DEVICE -j ACCEPT"
        "FORWARD -i $NETWORK_DEVICE -o $WG_TUNNEL_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT"
    )

    for rule in "${rules[@]}"; do
        if ! iptables_rule_exists "filter" "$rule"; then
            iptables -A $rule
        fi
        if ! ip6tables_rule_exists "filter" "$rule"; then
            ip6tables -A $rule
        fi
    done

    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
}

remove_iptables_rules_wg() {
    log "Removing WireGuard IPtables rules..."

    local rules=(
        "FORWARD -i $WG_TUNNEL_INTERFACE -o $NETWORK_DEVICE -j ACCEPT"
        "FORWARD -i $NETWORK_DEVICE -o $WG_TUNNEL_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT"
    )

    for rule in "${rules[@]}"; do
        if iptables_rule_exists "filter" "$rule"; then
            iptables -D $rule
        fi
        if ip6tables_rule_exists "filter" "$rule"; then
            ip6tables -D $rule
        fi
    done

    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
}

apply_iptables_rules() {
    log "Applying IPtables rules..."

    local rules=(
        "nat:POSTROUTING -o $NETWORK_DEVICE -j MASQUERADE"
        "filter:FORWARD -i $TUNNEL_INTERFACE -o $NETWORK_DEVICE -j ACCEPT"
        "filter:FORWARD -i $NETWORK_DEVICE -o $TUNNEL_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT"
    )

    for rule in "${rules[@]}"; do
        local table=${rule%%:*}
        local rule_content=${rule#*:}

        if ! iptables_rule_exists "$table" "$rule_content"; then
            iptables -t "$table" -A $rule_content
        fi
        if ! ip6tables_rule_exists "$table" "$rule_content"; then
            ip6tables -t "$table" -A $rule_content
        fi
    done

    adjust_ip_forwarding
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
}

remove_iptables_rules() {
    log "Removing IPtables rules..."

    local rules=(
        "nat:POSTROUTING -o $NETWORK_DEVICE -j MASQUERADE"
        "filter:FORWARD -i $TUNNEL_INTERFACE -o $NETWORK_DEVICE -j ACCEPT"
        "filter:FORWARD -i $NETWORK_DEVICE -o $TUNNEL_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT"
    )

    for rule in "${rules[@]}"; do
        local table=${rule%%:*}
        local rule_content=${rule#*:}

        if iptables_rule_exists "$table" "$rule_content"; then
            iptables -t "$table" -D $rule_content
        fi
        if ip6tables_rule_exists "$table" "$rule_content"; then
            ip6tables -t "$table" -D $rule_content
        fi
    done

    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
}

check_ipv6_ipv4_forwarding() {
    local result_ipv4
    local result_ipv6
    result_ipv4=$(cat /proc/sys/net/ipv4/ip_forward)
    result_ipv6=$(cat /proc/sys/net/ipv6/conf/all/forwarding)

    log "IPv4 forwarding is $([ "$result_ipv4" == "1" ] && echo "enabled" || echo "not enabled")"
    log "IPv6 forwarding is $([ "$result_ipv6" == "1" ] && echo "enabled" || echo "not enabled")"
}

check_nymtun_iptables() {
    log "Network Device: $NETWORK_DEVICE"
    log "---------------------------------------"

    log "Inspecting IPv4 firewall rules..."
    iptables -L FORWARD -v -n | awk -v dev="$NETWORK_DEVICE" '/^Chain FORWARD/ || /nymtun0/ && dev || dev && /nymtun0/ || /ufw-reject-forward/'

    log "---------------------------------------"
    log "Inspecting IPv6 firewall rules..."
    ip6tables -L FORWARD -v -n | awk -v dev="$NETWORK_DEVICE" '/^Chain FORWARD/ || /nymtun0/ && dev || dev && /nymtun0/ || /ufw6-reject-forward/'
}

check_ip6_ipv4_routing() {
    log "Examining IPv4 routing table..."
    ip route

    log "Examining IPv6 routing table..."
    ip -6 route
}

perform_ipv4_ipv6_pings() {
    local target="google.com"
    local count=4

    log "Checking IPv4 connectivity to $target..."
    if ! ping -c $count $target; then
        log "IPv4 ping failed"
    fi

    log "Checking IPv6 connectivity to $target..."
    if ! ping6 -c $count $target; then
        log "IPv6 ping failed"
    fi
}

configure_dns_and_icmp_wg() {
    log "Configuring DNS and ICMP rules..."

    local rules=(
        "INPUT -p icmp --icmp-type echo-request -j ACCEPT"
        "OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT"
        "INPUT -p udp --dport 53 -j ACCEPT"
        "INPUT -p tcp --dport 53 -j ACCEPT"
    )

    for rule in "${rules[@]}"; do
        if ! iptables_rule_exists "filter" "$rule"; then
            iptables -A $rule
        fi
    done

    iptables-save > /etc/iptables/rules.v4
    log "DNS and ICMP configuration completed"
}

test_tunnel_connectivity() {
    local interface=$1
    local ipv4_address
    local ipv6_address

    log "Checking $interface tunnel status..."

    if [[ $(ip link show "$interface" 2>/dev/null | grep -o "state [A-Z]*") != "state UNKNOWN" ]]; then
        log "$interface tunnel is down"
        return 1
    fi

    log "$interface tunnel is up"

    ipv4_address=$(ip addr show "$interface" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    if [[ -z "$ipv4_address" ]]; then
        log "No IPv4 address found on $interface"
    else
        if ! curl -s -H "Accept: application/json" --interface "$ipv4_address" https://icanhazdadjoke.com/ | jq -e .joke > /dev/null; then
            log "Failed to fetch joke via IPv4"
        fi
    fi

    ipv6_address=$(ip addr show "$interface" | grep 'inet6 ' | awk '{print $2}' | cut -d'/' -f1 | grep -v '^fe80:')
    if [[ -z "$ipv6_address" ]]; then
        log "No globally routable IPv6 address found on $interface"
    else
        if ! curl -s -H "Accept: application/json" --interface "$ipv6_address" https://icanhazdadjoke.com/ | jq -e .joke > /dev/null; then
            log "Failed to fetch joke via IPv6"
        fi
    fi
}

joke_through_the_mixnet() {
    test_tunnel_connectivity "$TUNNEL_INTERFACE"
}

joke_through_wg_tunnel() {
    test_tunnel_connectivity "$WG_TUNNEL_INTERFACE"
}

main() {
    if [[ $# -eq 0 ]]; then
        log "Error: No command provided"
        show_usage
        exit 1
    fi

    local command="$1"
    check_required_packages


    case "$command" in
        fetch_ipv6_address_nym_tun)
            fetch_ipv6_address_nym_tun
            ;;
        fetch_and_display_ipv6)
            fetch_and_display_ipv6
            ;;
        check_nymtun_iptables)
            check_nymtun_iptables
            ;;
        apply_iptables_rules)
            apply_iptables_rules
            ;;
        remove_iptables_rules)
            remove_iptables_rules
            ;;
        check_ipv6_ipv4_forwarding)
            check_ipv6_ipv4_forwarding
            ;;
        check_ip6_ipv4_routing)
            check_ip6_ipv4_routing
            ;;
        perform_ipv4_ipv6_pings)
            perform_ipv4_ipv6_pings
            ;;
        joke_through_the_mixnet)
            joke_through_the_mixnet
            ;;
        apply_iptables_rules_wg)
            apply_iptables_rules_wg
            ;;
        joke_through_wg_tunnel)
            joke_through_wg_tunnel
            ;;
        configure_dns_and_icmp_wg)
            configure_dns_and_icmp_wg
            ;;
    esac
    log "Operation $command completed successfully"
}

show_usage() {
    echo "Usage: $0 [command]"
    echo "Commands:"
    echo "  fetch_ipv6_address_nym_tun    - Fetches IPv6 address for $TUNNEL_INTERFACE"
    echo "  fetch_and_display_ipv6        - Shows IPv6 address on default network device"
    echo "  apply_iptables_rules          - Applies IPv4/IPv6 iptables rules"
    echo "  apply_iptables_rules_wg       - Applies WireGuard iptables rules"
    echo "  remove_iptables_rules         - Removes IPv4/IPv6 iptables rules"
    echo "  remove_iptables_rules_wg      - Removes WireGuard iptables rules"
    echo "  check_ipv6_ipv4_forwarding    - Checks IP forwarding status"
    echo "  check_nymtun_iptables         - Checks nymtun0 device"
    echo "  perform_ipv4_ipv6_pings       - Tests connectivity"
    echo "  check_ip6_ipv4_routing        - Shows routing tables"
    echo "  joke_through_the_mixnet       - Tests mixnet connectivity"
    echo "  joke_through_wg_tunnel        - Tests WireGuard tunnel"
    echo "  configure_dns_and_icmp_wg     - Configures DNS and ICMP rules"
}


main "$@"