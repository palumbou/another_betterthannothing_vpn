#!/usr/bin/env bash
set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/template.yaml"
DEFAULT_OUTPUT_DIR="${HOME}/.another-vpn"
DEFAULT_REGION="us-east-1"

# Check for required dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for aws CLI
    if ! command -v aws &> /dev/null; then
        missing_deps+=("aws")
    fi
    
    # Check for jq
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    # Check for session-manager-plugin
    if ! command -v session-manager-plugin &> /dev/null; then
        missing_deps+=("session-manager-plugin")
    fi
    
    # If on NixOS and dependencies are missing, try to bootstrap
    if [ ${#missing_deps[@]} -gt 0 ] && [ -f /etc/NIXOS ]; then
        nixos_bootstrap "$@"
        # If we reach here, nixos_bootstrap failed to re-exec
        return 1
    fi
    
    # If dependencies are missing and not on NixOS, display error
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "" >&2
        echo "Please install the following:" >&2
        
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                aws)
                    echo "" >&2
                    echo "  AWS CLI:" >&2
                    echo "    - Linux: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
                    echo "    - macOS: brew install awscli" >&2
                    echo "    - Or: pip install awscli" >&2
                    ;;
                jq)
                    echo "" >&2
                    echo "  jq:" >&2
                    echo "    - Linux: sudo apt-get install jq  (Debian/Ubuntu)" >&2
                    echo "              sudo yum install jq      (RHEL/CentOS)" >&2
                    echo "    - macOS: brew install jq" >&2
                    ;;
                session-manager-plugin)
                    echo "" >&2
                    echo "  AWS Session Manager Plugin:" >&2
                    echo "    - Linux: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html#install-plugin-linux" >&2
                    echo "    - macOS: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html#install-plugin-macos" >&2
                    echo "    - Windows: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html#install-plugin-windows" >&2
                    ;;
            esac
        done
        
        echo "" >&2
        return 1
    fi
    
    return 0
}

# Bootstrap environment on NixOS
nixos_bootstrap() {
    # Detect NixOS
    if [ ! -f /etc/NIXOS ]; then
        return 1
    fi
    
    echo "Detected NixOS. Bootstrapping environment with required dependencies..." >&2
    
    # Check if nix-shell is available
    if ! command -v nix-shell &> /dev/null; then
        echo "Error: nix-shell not found. Cannot bootstrap on NixOS." >&2
        return 1
    fi
    
    # Get the full path to this script
    local script_path
    script_path="$(readlink -f "${BASH_SOURCE[0]}")"
    
    # Re-execute script in nix-shell with required packages
    # Note: NixOS package name is ssm-session-manager-plugin
    exec nix-shell -p awscli2 ssm-session-manager-plugin jq --run "bash '$script_path' $*"
}

# Validate CIDR format (general validation)
validate_cidr_format() {
    local cidr="$1"
    
    # Check basic CIDR format: x.x.x.x/y or xxxx:xxxx::/y
    if [[ ! "$cidr" =~ ^[0-9a-fA-F:.]+/[0-9]+$ ]]; then
        return 1
    fi
    
    # Extract IP and prefix
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"
    
    # Validate IPv4
    if [[ "$ip" =~ ^[0-9.]+$ ]]; then
        # Check IPv4 format: four octets
        local IFS='.'
        local -a octets=($ip)
        
        if [ ${#octets[@]} -ne 4 ]; then
            return 1
        fi
        
        # Validate each octet (0-255)
        for octet in "${octets[@]}"; do
            if ! [[ "$octet" =~ ^[0-9]+$ ]] || [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        
        # Validate prefix length (0-32 for IPv4)
        if [ "$prefix" -lt 0 ] || [ "$prefix" -gt 32 ]; then
            return 1
        fi
        
        return 0
    fi
    
    # Validate IPv6 (basic check)
    if [[ "$ip" =~ : ]]; then
        # Validate prefix length (0-128 for IPv6)
        if [ "$prefix" -lt 0 ] || [ "$prefix" -gt 128 ]; then
            return 1
        fi
        
        return 0
    fi
    
    return 1
}

# Validate VPC CIDR (RFC 1918 private ranges with appropriate prefix length)
validate_vpc_cidr() {
    local cidr="$1"
    
    # First validate basic CIDR format
    if ! validate_cidr_format "$cidr"; then
        echo "Error: Invalid CIDR format: '$cidr'" >&2
        echo "Expected format: x.x.x.x/y" >&2
        echo "" >&2
        echo "Valid examples:" >&2
        echo "  10.10.0.0/16" >&2
        echo "  172.16.0.0/16" >&2
        echo "  192.168.1.0/24" >&2
        exit 1
    fi
    
    # Extract IP and prefix
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"
    
    # Only support IPv4 for VPC CIDR
    if [[ ! "$ip" =~ ^[0-9.]+$ ]]; then
        echo "Error: VPC CIDR must be IPv4 address. Got: '$cidr'" >&2
        exit 1
    fi
    
    # Validate prefix length (/16 to /28)
    if [ "$prefix" -lt 16 ] || [ "$prefix" -gt 28 ]; then
        echo "Error: VPC CIDR prefix must be between /16 and /28. Got: /$prefix" >&2
        echo "" >&2
        echo "Valid examples:" >&2
        echo "  10.10.0.0/16  (65,536 addresses)" >&2
        echo "  172.16.0.0/20 (4,096 addresses)" >&2
        echo "  192.168.1.0/24 (256 addresses)" >&2
        exit 1
    fi
    
    # Extract first octet for RFC 1918 validation
    local IFS='.'
    local -a octets=($ip)
    local first_octet="${octets[0]}"
    local second_octet="${octets[1]}"
    
    # Check if CIDR is in RFC 1918 private address space
    local is_rfc1918=false
    
    # 10.0.0.0/8 (10.0.0.0 - 10.255.255.255)
    if [ "$first_octet" -eq 10 ]; then
        is_rfc1918=true
    fi
    
    # 172.16.0.0/12 (172.16.0.0 - 172.31.255.255)
    if [ "$first_octet" -eq 172 ] && [ "$second_octet" -ge 16 ] && [ "$second_octet" -le 31 ]; then
        is_rfc1918=true
    fi
    
    # 192.168.0.0/16 (192.168.0.0 - 192.168.255.255)
    if [ "$first_octet" -eq 192 ] && [ "$second_octet" -eq 168 ]; then
        is_rfc1918=true
    fi
    
    if [ "$is_rfc1918" = false ]; then
        echo "Error: VPC CIDR must be a private address range (RFC 1918)." >&2
        echo "Got: '$cidr'" >&2
        echo "" >&2
        echo "Valid RFC 1918 ranges:" >&2
        echo "  10.0.0.0/8      (10.0.0.0 - 10.255.255.255)" >&2
        echo "  172.16.0.0/12   (172.16.0.0 - 172.31.255.255)" >&2
        echo "  192.168.0.0/16  (192.168.0.0 - 192.168.255.255)" >&2
        echo "" >&2
        echo "Valid examples:" >&2
        echo "  10.10.0.0/16" >&2
        echo "  172.16.0.0/16" >&2
        echo "  192.168.1.0/24" >&2
        exit 1
    fi
    
    # Return validated CIDR
    echo "$cidr"
}

# Detect operator's public IP address
detect_my_ip() {
    local detected_ip=""
    
    # Primary method: ipify.org
    if command -v curl &> /dev/null; then
        detected_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || true)
    fi
    
    # Fallback method: OpenDNS resolver
    if [ -z "$detected_ip" ] && command -v dig &> /dev/null; then
        detected_ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | grep -v ';' | head -n1 || true)
    fi
    
    # Check if we got an IP
    if [ -z "$detected_ip" ]; then
        echo "Error: Unable to detect public IP address." >&2
        echo "" >&2
        echo "Tried:" >&2
        echo "  - https://api.ipify.org (requires curl)" >&2
        echo "  - OpenDNS resolver (requires dig)" >&2
        echo "" >&2
        echo "Please check your internet connectivity or use --allowed-cidr instead:" >&2
        echo "  ./another_betterthannothing_vpn.sh create --allowed-cidr <your-ip>/32" >&2
        exit 1
    fi
    
    # Determine if IPv4 or IPv6 and add appropriate suffix
    if [[ "$detected_ip" =~ ^[0-9.]+$ ]]; then
        # IPv4 - add /32
        echo "${detected_ip}/32"
    elif [[ "$detected_ip" =~ : ]]; then
        # IPv6 - add /128
        echo "${detected_ip}/128"
    else
        echo "Error: Detected IP address has invalid format: '$detected_ip'" >&2
        exit 1
    fi
}

# Generate unique stack name in format: another-YYYYMMDD-xxxx
generate_stack_name() {
    # Get current date in YYYYMMDD format
    local date_part
    date_part=$(date +%Y%m%d)
    
    # Generate 4-character random alphanumeric suffix (lowercase)
    local random_suffix
    random_suffix=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 4)
    
    # Combine to create stack name
    echo "another-${date_part}-${random_suffix}"
}

# Validate if a CloudFormation stack exists
# Returns 0 (true) if stack exists, 1 (false) if not
# Does not exit on error - handles "stack not found" gracefully
validate_stack_exists() {
    local stack_name="$1"
    local region="${2:-${REGION}}"
    
    # Try to describe the stack
    # Redirect stderr to suppress "does not exist" error messages
    if aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --output json \
        > /dev/null 2>&1; then
        # Stack exists
        return 0
    else
        # Stack does not exist (or other error, but we treat as not found)
        return 1
    fi
}

# Get stack outputs as JSON
# Returns JSON object with output keys and values
# Exits with error if stack doesn't exist or outputs can't be retrieved
get_stack_outputs() {
    local stack_name="$1"
    local region="${2:-${REGION}}"
    
    # Retrieve stack information
    local stack_info
    if ! stack_info=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --output json 2>&1); then
        echo "Error: Failed to retrieve stack information for '$stack_name' in region '$region'" >&2
        echo "$stack_info" >&2
        exit 1
    fi
    
    # Extract outputs using jq
    # Convert from array of {OutputKey, OutputValue} to object {key: value}
    local outputs
    if ! outputs=$(echo "$stack_info" | jq -r '.Stacks[0].Outputs // [] | map({(.OutputKey): .OutputValue}) | add // {}' 2>&1); then
        echo "Error: Failed to parse stack outputs for '$stack_name'" >&2
        echo "$outputs" >&2
        exit 1
    fi
    
    # Return the outputs JSON
    echo "$outputs"
}

# Wait for SSM agent to be ready on the instance
# Polls every 10 seconds for up to 5 minutes (30 attempts)
# Returns 0 if SSM is ready, 1 if timeout
wait_for_ssm_ready() {
    local instance_id="$1"
    local region="${2:-${REGION}}"
    local max_attempts=30  # 30 attempts * 10 seconds = 5 minutes
    local attempt=0
    local sleep_interval=10
    
    echo "Checking SSM agent status (timeout: 5 minutes)..."
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        # Query SSM for instance information
        local ssm_status
        ssm_status=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$instance_id" \
            --region "$region" \
            --output json 2>/dev/null || echo '{"InstanceInformationList":[]}')
        
        # Check if instance is registered with SSM
        local instance_count
        instance_count=$(echo "$ssm_status" | jq -r '.InstanceInformationList | length')
        
        if [ "$instance_count" -gt 0 ]; then
            # Instance is registered - check ping status
            local ping_status
            ping_status=$(echo "$ssm_status" | jq -r '.InstanceInformationList[0].PingStatus // "Unknown"')
            
            if [ "$ping_status" = "Online" ]; then
                echo "✓ SSM agent is online and ready"
                return 0
            else
                echo "  Attempt $attempt/$max_attempts: SSM agent status: $ping_status (waiting...)"
            fi
        else
            echo "  Attempt $attempt/$max_attempts: SSM agent not yet registered (waiting...)"
        fi
        
        # Sleep before next attempt (unless this was the last attempt)
        if [ $attempt -lt $max_attempts ]; then
            sleep $sleep_interval
        fi
    done
    
    # Timeout reached
    echo "" >&2
    echo "Timeout: SSM agent did not become ready within 5 minutes" >&2
    echo "" >&2
    echo "Troubleshooting steps:" >&2
    echo "  1. Check instance system logs:" >&2
    echo "     aws ec2 get-console-output --instance-id $instance_id --region $region" >&2
    echo "" >&2
    echo "  2. Verify IAM role is attached to the instance:" >&2
    echo "     aws ec2 describe-instances --instance-ids $instance_id --region $region \\" >&2
    echo "       --query 'Reservations[0].Instances[0].IamInstanceProfile'" >&2
    echo "" >&2
    echo "  3. Verify instance has internet connectivity (required for SSM):" >&2
    echo "     - Check Security Group allows outbound HTTPS (443)" >&2
    echo "     - Check route table has route to Internet Gateway" >&2
    echo "" >&2
    echo "  4. Wait a few more minutes and try connecting via SSM:" >&2
    echo "     ./another_betterthannothing_vpn.sh ssm --name $STACK_NAME --region $region" >&2
    echo "" >&2
    echo "  5. Check SSM agent logs on the instance (if you can access it):" >&2
    echo "     sudo journalctl -u amazon-ssm-agent" >&2
    echo "" >&2
    
    return 1
}

# Execute remote command on EC2 instance via SSM
# Returns command output
# Exits with error if command fails
execute_remote_command() {
    local instance_id="$1"
    local region="$2"
    local command="$3"
    local timeout="${4:-60}"  # Default 60 second timeout
    
    # Use SSM Send-Command API for non-interactive commands
    local command_id
    if ! command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"$command\"]" \
        --timeout-seconds "$timeout" \
        --region "$region" \
        --output json 2>&1 | jq -r '.Command.CommandId // empty'); then
        echo "Error: Failed to send command to instance $instance_id" >&2
        return 1
    fi
    
    if [ -z "$command_id" ]; then
        echo "Error: Failed to get command ID from SSM send-command" >&2
        return 1
    fi
    
    # Wait for command to complete (poll every 2 seconds)
    local max_wait=30  # 30 attempts * 2 seconds = 60 seconds
    local attempt=0
    local status=""
    
    while [ $attempt -lt $max_wait ]; do
        attempt=$((attempt + 1))
        
        # Get command invocation status
        local invocation
        invocation=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --region "$region" \
            --output json 2>/dev/null || echo '{}')
        
        status=$(echo "$invocation" | jq -r '.Status // "Pending"')
        
        if [ "$status" = "Success" ]; then
            # Return command output
            echo "$invocation" | jq -r '.StandardOutputContent // ""'
            return 0
        elif [ "$status" = "Failed" ] || [ "$status" = "Cancelled" ] || [ "$status" = "TimedOut" ]; then
            # Command failed
            local error_output
            error_output=$(echo "$invocation" | jq -r '.StandardErrorContent // "No error output"')
            echo "Error: Command failed with status: $status" >&2
            echo "Error output: $error_output" >&2
            return 1
        fi
        
        # Still pending/in-progress, wait and retry
        sleep 2
    done
    
    # Timeout waiting for command
    echo "Error: Timeout waiting for command to complete (command ID: $command_id)" >&2
    return 1
}

# Bootstrap VPN server with WireGuard configuration
# Installs WireGuard, generates keys, configures service
bootstrap_vpn_server() {
    local instance_id="$1"
    local region="$2"
    local mode="$3"
    local vpn_port="$4"
    local vpc_cidr="$5"
    
    echo ""
    echo "=== Bootstrapping VPN Server ==="
    echo ""
    
    # Step 1: Install wireguard-tools
    echo "Installing WireGuard tools..."
    if ! execute_remote_command "$instance_id" "$region" \
        "sudo dnf install -y wireguard-tools" 300; then
        echo "Error: Failed to install wireguard-tools" >&2
        return 1
    fi
    echo "✓ WireGuard tools installed"
    echo ""
    
    # Step 2: Generate server WireGuard keys
    echo "Generating server WireGuard keys..."
    local server_private_key
    if ! server_private_key=$(execute_remote_command "$instance_id" "$region" \
        "wg genkey | sudo tee /etc/wireguard/server_private.key" 60); then
        echo "Error: Failed to generate server private key" >&2
        return 1
    fi
    
    # Remove any trailing whitespace/newlines
    server_private_key=$(echo "$server_private_key" | tr -d '\n\r' | xargs)
    
    # Generate and retrieve server public key
    local server_public_key
    if ! server_public_key=$(execute_remote_command "$instance_id" "$region" \
        "sudo cat /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key" 60); then
        echo "Error: Failed to generate server public key" >&2
        return 1
    fi
    
    # Remove any trailing whitespace/newlines
    server_public_key=$(echo "$server_public_key" | tr -d '\n\r' | xargs)
    
    echo "✓ Server keys generated"
    echo "  Public key: $server_public_key"
    echo ""
    
    # Step 3: Set proper permissions on key files
    echo "Setting key file permissions..."
    if ! execute_remote_command "$instance_id" "$region" \
        "sudo chmod 600 /etc/wireguard/server_private.key /etc/wireguard/server_public.key" 60; then
        echo "Error: Failed to set key file permissions" >&2
        return 1
    fi
    echo "✓ Key file permissions set"
    echo ""
    
    # Step 4: Create WireGuard configuration file
    echo "Creating WireGuard configuration..."
    
    # Build the configuration file content
    local wg_config="[Interface]
Address = 10.99.0.1/24
ListenPort = $vpn_port
PrivateKey = $server_private_key"
    
    # Add PostUp/PostDown iptables rules if mode is full-tunnel
    if [ "$mode" = "full" ]; then
        wg_config="$wg_config
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
    fi
    
    # Write configuration file
    # Use heredoc to handle multi-line content safely
    local create_config_cmd="sudo tee /etc/wireguard/wg0.conf > /dev/null << 'WGEOF'
$wg_config

# Peers will be added dynamically
WGEOF"
    
    if ! execute_remote_command "$instance_id" "$region" "$create_config_cmd" 60; then
        echo "Error: Failed to create WireGuard configuration file" >&2
        return 1
    fi
    
    # Set proper permissions on config file
    if ! execute_remote_command "$instance_id" "$region" \
        "sudo chmod 600 /etc/wireguard/wg0.conf" 60; then
        echo "Error: Failed to set config file permissions" >&2
        return 1
    fi
    
    echo "✓ WireGuard configuration created"
    echo ""
    
    # Step 5: Enable IP forwarding
    echo "Enabling IP forwarding..."
    
    # Enable IP forwarding immediately
    if ! execute_remote_command "$instance_id" "$region" \
        "sudo sysctl -w net.ipv4.ip_forward=1" 60; then
        echo "Error: Failed to enable IP forwarding" >&2
        return 1
    fi
    
    # Persist IP forwarding setting
    if ! execute_remote_command "$instance_id" "$region" \
        "echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-wireguard.conf > /dev/null" 60; then
        echo "Error: Failed to persist IP forwarding setting" >&2
        return 1
    fi
    
    echo "✓ IP forwarding enabled and persisted"
    echo ""
    
    # Step 6: Start and enable WireGuard service
    echo "Starting WireGuard service..."
    
    if ! execute_remote_command "$instance_id" "$region" \
        "sudo systemctl enable --now wg-quick@wg0" 120; then
        echo "Error: Failed to start WireGuard service" >&2
        return 1
    fi
    
    echo "✓ WireGuard service started and enabled"
    echo ""
    
    # Step 7: Verify service is running
    echo "Verifying WireGuard service status..."
    
    local service_status
    if ! service_status=$(execute_remote_command "$instance_id" "$region" \
        "sudo systemctl is-active wg-quick@wg0" 60); then
        echo "Error: WireGuard service is not active" >&2
        echo "Service status: $service_status" >&2
        return 1
    fi
    
    # Check if service is active
    if [ "$(echo "$service_status" | tr -d '\n\r' | xargs)" != "active" ]; then
        echo "Error: WireGuard service is not active (status: $service_status)" >&2
        return 1
    fi
    
    echo "✓ WireGuard service is active and running"
    echo ""
    
    echo "=== VPN Server Bootstrap Complete ==="
    echo ""
    
    # Store server public key for later use (return it)
    echo "$server_public_key"
    return 0
}

# Generate client configuration
# Parameters: stack_name, client_name, client_id, mode, vpc_cidr, endpoint, port, server_public_key, instance_id, region, output_dir
generate_client_config() {
    local stack_name="$1"
    local client_name="$2"
    local client_id="$3"
    local mode="$4"
    local vpc_cidr="$5"
    local endpoint="$6"
    local port="$7"
    local server_public_key="$8"
    local instance_id="$9"
    local region="${10}"
    local output_dir="${11}"
    
    echo "Generating client configuration: $client_name (10.99.0.$client_id/32)..."
    
    # Step 1: Generate client private/public key pair on server via SSM
    local client_private_key
    if ! client_private_key=$(execute_remote_command "$instance_id" "$region" \
        "wg genkey" 60); then
        echo "Error: Failed to generate client private key for $client_name" >&2
        return 1
    fi
    
    # Remove any trailing whitespace/newlines
    client_private_key=$(echo "$client_private_key" | tr -d '\n\r' | xargs)
    
    # Generate client public key from private key
    local client_public_key
    if ! client_public_key=$(execute_remote_command "$instance_id" "$region" \
        "echo '$client_private_key' | wg pubkey" 60); then
        echo "Error: Failed to generate client public key for $client_name" >&2
        return 1
    fi
    
    # Remove any trailing whitespace/newlines
    client_public_key=$(echo "$client_public_key" | tr -d '\n\r' | xargs)
    
    # Step 2: Add peer to server config
    echo "  Adding peer to server configuration..."
    if ! execute_remote_command "$instance_id" "$region" \
        "sudo wg set wg0 peer $client_public_key allowed-ips 10.99.0.$client_id/32" 60; then
        echo "Error: Failed to add peer to server config for $client_name" >&2
        return 1
    fi
    
    # Step 3: Save server config
    if ! execute_remote_command "$instance_id" "$region" \
        "sudo wg-quick save wg0" 60; then
        echo "Error: Failed to save server config for $client_name" >&2
        return 1
    fi
    
    # Step 4: Create client config file with [Interface] and [Peer] sections
    # Set AllowedIPs based on mode
    local allowed_ips
    if [ "$mode" = "full" ]; then
        allowed_ips="0.0.0.0/0, ::/0"
    else
        # split-tunnel mode - only route VPC CIDR
        allowed_ips="$vpc_cidr"
    fi
    
    # Build client configuration
    local client_config="[Interface]
PrivateKey = $client_private_key
Address = 10.99.0.$client_id/24
DNS = 1.1.1.1

[Peer]
PublicKey = $server_public_key
Endpoint = $endpoint:$port
AllowedIPs = $allowed_ips
PersistentKeepalive = 25"
    
    # Step 5: Create output directory
    local client_dir="$output_dir/$stack_name/clients"
    if ! mkdir -p "$client_dir" 2>/dev/null; then
        echo "Error: Failed to create output directory: $client_dir" >&2
        return 1
    fi
    
    # Step 6: Write config to file
    local config_file="$client_dir/$client_name.conf"
    if ! echo "$client_config" > "$config_file" 2>/dev/null; then
        echo "Error: Failed to write client config file: $config_file" >&2
        return 1
    fi
    
    # Step 7: Set file permissions to 600
    if ! chmod 600 "$config_file" 2>/dev/null; then
        echo "Error: Failed to set permissions on config file: $config_file" >&2
        return 1
    fi
    
    echo "✓ Client configuration saved: $config_file"
    
    return 0
}

# Display help message
display_help() {
    cat << EOF
another.sh - Disposable VPN infrastructure on AWS

USAGE:
    another.sh <command> [options]

COMMANDS:
    create       Create VPN stack and configure server
    delete       Delete VPN stack
    start        Start the VPN instance
    stop         Stop the VPN instance
    status       Show stack and instance status
    list         List all VPN stacks in region
    add-client   Add new VPN client configuration
    ssm          Open SSM session to VPN server
    help         Show this help message

OPTIONS:
    --region <region>           AWS region (default: us-east-1)
    --name <stack-name>         Stack name (default: auto-generated)
    --mode <full|split>         Tunnel mode (default: split)
                                  full: Route all traffic through VPN
                                  split: Route only VPC traffic through VPN
    --allowed-cidr <cidr>       Source CIDR allowed to connect to VPN port
                                (repeatable, default: 0.0.0.0/0)
                                This controls WHO can reach your VPN server
    --my-ip                     Auto-detect and use your public IP/32
                                (mutually exclusive with --allowed-cidr)
    --vpc-cidr <cidr>           VPC CIDR block (default: 10.10.0.0/16)
                                Must be RFC 1918 private range
                                This defines the internal VPC network
    --instance-type <type>      EC2 instance type (default: t4g.nano)
    --spot                      Use EC2 Spot instances for cost savings
                                (lower cost but can be interrupted)
    --clients <n>               Number of initial clients (default: 1)
    --output-dir <path>         Output directory (default: ~/.another-vpn)
    --yes, --non-interactive    Skip confirmations
    --help                      Show this help message

UNDERSTANDING CIDR PARAMETERS:

    --vpc-cidr (Internal Network):
        Defines the private IP address space for your VPC infrastructure.
        Default: 10.10.0.0/16
        Must be RFC 1918 private range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
        Use case: Change if default conflicts with your existing networks
        Example: --vpc-cidr 172.16.0.0/16

    --allowed-cidr (Access Control):
        Controls which source IP addresses can connect to your VPN server.
        Default: 0.0.0.0/0 (anyone on internet - least secure)
        Applied to: Security Group inbound rule for VPN port
        Use case: Restrict VPN access to specific networks or IPs
        Best practice: Use --my-ip to restrict to your current IP
        Example: --allowed-cidr 203.0.113.0/24

SPOT INSTANCES:

    The --spot flag uses EC2 Spot instances instead of on-demand instances.
    
    Benefits:
        - Significant cost savings (up to 90% off on-demand price)
        - Same performance as on-demand instances
    
    Considerations:
        - Can be interrupted with 2-minute warning
        - Best for temporary/disposable workloads
        - Not recommended for production or long-term use
    
    Example: ./another_betterthannothing_vpn.sh create --spot --my-ip

EXAMPLES:

    # Create VPN with auto-detected IP restriction (recommended)
    ./another_betterthannothing_vpn.sh create --my-ip

    # Create full-tunnel VPN with custom name
    ./another_betterthannothing_vpn.sh create --name my-vpn --mode full --my-ip

    # Create split-tunnel VPN with custom VPC CIDR
    ./another_betterthannothing_vpn.sh create --mode split --vpc-cidr 172.16.0.0/16 --my-ip

    # Create VPN with specific allowed network
    ./another_betterthannothing_vpn.sh create --allowed-cidr 203.0.113.0/24

    # Create VPN using Spot instances for cost savings
    ./another_betterthannothing_vpn.sh create --spot --my-ip

    # Stop VPN instance to save costs (keeps infrastructure)
    ./another_betterthannothing_vpn.sh stop --name my-vpn

    # Start VPN instance when needed again
    ./another_betterthannothing_vpn.sh start --name my-vpn

    # List all VPN stacks
    ./another_betterthannothing_vpn.sh list --region us-east-1

    # Check stack status
    ./another_betterthannothing_vpn.sh status --name my-vpn

    # Add another client to existing stack
    ./another_betterthannothing_vpn.sh add-client --name my-vpn

    # Open SSM session to VPN server
    ./another_betterthannothing_vpn.sh ssm --name my-vpn

    # Delete VPN stack
    ./another_betterthannothing_vpn.sh delete --name my-vpn --yes

For more information, see README.md

EOF
}

# Parse command-line arguments
parse_args() {
    # Initialize variables
    COMMAND=""
    REGION="${DEFAULT_REGION}"
    STACK_NAME=""
    MODE="split"
    ALLOWED_CIDRS=()
    USE_MY_IP=false
    VPC_CIDR="10.10.0.0/16"
    INSTANCE_TYPE="t4g.nano"
    USE_SPOT=false
    NUM_CLIENTS=1
    OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
    NON_INTERACTIVE=false

    # Check if no arguments provided
    if [ $# -eq 0 ]; then
        display_help
        exit 0
    fi

    # First argument is the command
    COMMAND="$1"
    shift

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --region)
                REGION="$2"
                shift 2
                ;;
            --name)
                STACK_NAME="$2"
                shift 2
                ;;
            --mode)
                MODE="$2"
                shift 2
                ;;
            --allowed-cidr)
                ALLOWED_CIDRS+=("$2")
                shift 2
                ;;
            --my-ip)
                USE_MY_IP=true
                shift
                ;;
            --vpc-cidr)
                VPC_CIDR="$2"
                shift 2
                ;;
            --instance-type)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            --spot)
                USE_SPOT=true
                shift
                ;;
            --clients)
                NUM_CLIENTS="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --yes|--non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --help)
                display_help
                exit 0
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                echo "Run 'another_betterthannothing_vpn.sh --help' for usage information" >&2
                exit 1
                ;;
        esac
    done

    # Export variables for use in command functions
    export COMMAND REGION STACK_NAME MODE USE_MY_IP VPC_CIDR INSTANCE_TYPE USE_SPOT NUM_CLIENTS OUTPUT_DIR NON_INTERACTIVE
    export ALLOWED_CIDRS
}

# Command: create
cmd_create() {
    # ============================================================
    # PREPARATION PHASE
    # ============================================================
    
    # Parse and store command-line options (already done in parse_args)
    # Variables available: REGION, STACK_NAME, MODE, ALLOWED_CIDRS, USE_MY_IP,
    # VPC_CIDR, INSTANCE_TYPE, USE_SPOT, NUM_CLIENTS, OUTPUT_DIR, NON_INTERACTIVE
    
    # Validate mutually exclusive flags: --my-ip and --allowed-cidr
    if [ "$USE_MY_IP" = true ] && [ ${#ALLOWED_CIDRS[@]} -gt 0 ]; then
        echo "Error: --my-ip and --allowed-cidr are mutually exclusive." >&2
        echo "Use either --my-ip to auto-detect your IP, or --allowed-cidr to specify manually." >&2
        exit 1
    fi
    
    # Validate and process VPC CIDR if provided (non-default)
    local validated_vpc_cidr="$VPC_CIDR"
    if [ "$VPC_CIDR" != "10.10.0.0/16" ]; then
        echo "Validating custom VPC CIDR: $VPC_CIDR"
        validated_vpc_cidr=$(validate_vpc_cidr "$VPC_CIDR")
    fi
    
    # Detect public IP if --my-ip flag is set
    local allowed_ingress_cidr=""
    if [ "$USE_MY_IP" = true ]; then
        echo "Detecting your public IP address..."
        allowed_ingress_cidr=$(detect_my_ip)
        echo "Detected IP: $allowed_ingress_cidr"
    elif [ ${#ALLOWED_CIDRS[@]} -gt 0 ]; then
        # Use first allowed CIDR (for now, CloudFormation template supports single value)
        # TODO: If template supports multiple CIDRs, handle array properly
        allowed_ingress_cidr="${ALLOWED_CIDRS[0]}"
        
        # Validate the CIDR format
        if ! validate_cidr_format "$allowed_ingress_cidr"; then
            echo "Error: Invalid CIDR format for --allowed-cidr: '$allowed_ingress_cidr'" >&2
            echo "Expected format: x.x.x.x/y" >&2
            exit 1
        fi
    else
        # Default to 0.0.0.0/0 (open to internet)
        allowed_ingress_cidr="0.0.0.0/0"
    fi
    
    # Generate stack name if not provided
    if [ -z "$STACK_NAME" ]; then
        STACK_NAME=$(generate_stack_name)
        echo "Generated stack name: $STACK_NAME"
    fi
    
    # Check if stack already exists
    if validate_stack_exists "$STACK_NAME" "$REGION"; then
        echo "Error: Stack '$STACK_NAME' already exists in region '$REGION'." >&2
        echo "Use a different name with --name, or delete the existing stack first:" >&2
        echo "  ./another_betterthannothing_vpn.sh delete --name $STACK_NAME --region $REGION" >&2
        exit 1
    fi
    
    # Display security warning if AllowedIngressCidr is 0.0.0.0/0
    if [ "$allowed_ingress_cidr" = "0.0.0.0/0" ]; then
        echo "" >&2
        echo "⚠️  SECURITY WARNING ⚠️" >&2
        echo "Your VPN server will be accessible from ANY IP address on the internet (0.0.0.0/0)." >&2
        echo "" >&2
        echo "This is NOT recommended for security reasons." >&2
        echo "Consider using --my-ip to restrict access to your current IP:" >&2
        echo "  ./another_betterthannothing_vpn.sh create --my-ip" >&2
        echo "" >&2
        echo "Or specify a specific network with --allowed-cidr:" >&2
        echo "  ./another_betterthannothing_vpn.sh create --allowed-cidr <your-ip>/32" >&2
        echo "" >&2
        
        # If interactive mode, prompt for confirmation
        if [ "$NON_INTERACTIVE" = false ]; then
            read -p "Continue with 0.0.0.0/0 access? (y/N): " -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Aborted."
                exit 0
            fi
        fi
    fi
    
    # Display cost savings note if --spot flag is used
    if [ "$USE_SPOT" = true ]; then
        echo "" >&2
        echo "💰 Cost Savings: Using EC2 Spot instances" >&2
        echo "Spot instances can provide up to 90% cost savings compared to on-demand." >&2
        echo "Note: Spot instances can be interrupted with 2-minute warning." >&2
        echo "Best for temporary/disposable workloads." >&2
        echo "" >&2
    fi
    
    # Display summary of configuration
    echo ""
    echo "=== VPN Configuration Summary ==="
    echo "Stack Name:        $STACK_NAME"
    echo "Region:            $REGION"
    echo "Mode:              $MODE"
    echo "VPC CIDR:          $validated_vpc_cidr"
    echo "Allowed Ingress:   $allowed_ingress_cidr"
    echo "Instance Type:     $INSTANCE_TYPE"
    echo "Spot Instance:     $USE_SPOT"
    echo "Initial Clients:   $NUM_CLIENTS"
    echo "Output Directory:  $OUTPUT_DIR"
    echo "================================="
    echo ""
    
    # ============================================================
    # CLOUDFORMATION STACK CREATION PHASE
    # ============================================================
    
    # Prepare CloudFormation parameters array
    local cf_parameters=(
        "ParameterKey=VpcCidr,ParameterValue=$validated_vpc_cidr"
        "ParameterKey=InstanceType,ParameterValue=$INSTANCE_TYPE"
        "ParameterKey=VpnPort,ParameterValue=51820"
        "ParameterKey=VpnProtocol,ParameterValue=udp"
        "ParameterKey=AllowedIngressCidr,ParameterValue=$allowed_ingress_cidr"
        "ParameterKey=UseSpotInstance,ParameterValue=$USE_SPOT"
    )
    
    # Build CloudFormation create-stack command
    echo "Creating stack '$STACK_NAME' in region '$REGION'..."
    
    # Execute create-stack command with parameters and tags
    local create_output
    if ! create_output=$(aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body "file://${TEMPLATE_FILE}" \
        --parameters "${cf_parameters[@]}" \
        --capabilities CAPABILITY_IAM \
        --tags "Key=costcenter,Value=$STACK_NAME" \
        --region "$REGION" \
        --output json 2>&1); then
        echo "Error: Failed to create CloudFormation stack" >&2
        echo "$create_output" >&2
        exit 1
    fi
    
    # Extract stack ID from output
    local stack_id
    stack_id=$(echo "$create_output" | jq -r '.StackId // empty')
    
    if [ -n "$stack_id" ]; then
        echo "Stack creation initiated. Stack ID: $stack_id"
    fi
    
    echo "Waiting for stack creation to complete (this may take 3-5 minutes)..."
    
    # Wait for stack creation to complete with timeout
    # The wait command has a built-in timeout of 120 attempts * 30 seconds = 1 hour
    if ! aws cloudformation wait stack-create-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION" 2>&1; then
        
        # Stack creation failed - retrieve and display failed events
        echo "" >&2
        echo "Error: Stack creation failed" >&2
        echo "" >&2
        echo "Failed events:" >&2
        
        # Get stack events and filter for failed resources
        local failed_events
        failed_events=$(aws cloudformation describe-stack-events \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --output json 2>/dev/null | \
            jq -r '.StackEvents[] | select(.ResourceStatus | contains("FAILED")) | 
                "\(.Timestamp) - \(.ResourceType) (\(.LogicalResourceId)): \(.ResourceStatusReason // "No reason provided")"' 2>/dev/null || echo "Unable to retrieve stack events")
        
        echo "$failed_events" >&2
        echo "" >&2
        echo "To clean up the failed stack, run:" >&2
        echo "  ./another_betterthannothing_vpn.sh delete --name $STACK_NAME --region $REGION --yes" >&2
        exit 1
    fi
    
    echo "✓ Stack creation complete!"
    echo ""
    
    # ============================================================
    # SSM READINESS AND BOOTSTRAP PHASE
    # ============================================================
    
    # Retrieve stack outputs
    echo "Retrieving stack outputs..."
    local stack_outputs
    stack_outputs=$(get_stack_outputs "$STACK_NAME" "$REGION")
    
    # Extract instance ID from outputs
    local instance_id
    instance_id=$(echo "$stack_outputs" | jq -r '.InstanceId // empty')
    
    if [ -z "$instance_id" ]; then
        echo "Error: Failed to retrieve InstanceId from stack outputs" >&2
        exit 1
    fi
    
    echo "Instance ID: $instance_id"
    echo ""
    
    # Wait for SSM agent to be ready
    echo "Waiting for SSM agent to be ready..."
    if ! wait_for_ssm_ready "$instance_id" "$REGION"; then
        echo "" >&2
        echo "Error: SSM agent did not become ready within the timeout period" >&2
        exit 1
    fi
    
    echo "Instance ready, bootstrapping VPN server..."
    echo ""
    
    # Extract necessary outputs for bootstrap
    local public_ip
    public_ip=$(echo "$stack_outputs" | jq -r '.PublicIp // empty')
    
    local vpn_port
    vpn_port=$(echo "$stack_outputs" | jq -r '.VpnPort // "51820"')
    
    if [ -z "$public_ip" ]; then
        echo "Error: Failed to retrieve PublicIp from stack outputs" >&2
        exit 1
    fi
    
    # Bootstrap VPN server and capture server public key
    local server_public_key
    if ! server_public_key=$(bootstrap_vpn_server "$instance_id" "$REGION" "$MODE" "$vpn_port" "$validated_vpc_cidr"); then
        echo "" >&2
        echo "Error: VPN server bootstrap failed" >&2
        echo "" >&2
        echo "You can try to manually debug by connecting via SSM:" >&2
        echo "  ./another_betterthannothing_vpn.sh ssm --name $STACK_NAME --region $REGION" >&2
        exit 1
    fi
    
    # Remove any trailing whitespace from server public key
    server_public_key=$(echo "$server_public_key" | tr -d '\n\r' | xargs)
    
    echo "✓ VPN server is ready!"
    echo ""
    echo "Server endpoint: $public_ip:$vpn_port"
    echo "Server public key: $server_public_key"
    echo ""
    
    # ============================================================
    # CLIENT GENERATION AND COMPLETION PHASE
    # ============================================================
    
    echo "=== Generating Client Configurations ==="
    echo ""
    
    # Generate N client configs (from --clients parameter)
    local client_count=0
    local failed_clients=0
    
    for ((i=1; i<=NUM_CLIENTS; i++)); do
        local client_name="client-$i"
        local client_id=$((i + 1))  # Start from 10.99.0.2 (server is .1)
        
        if generate_client_config \
            "$STACK_NAME" \
            "$client_name" \
            "$client_id" \
            "$MODE" \
            "$validated_vpc_cidr" \
            "$public_ip" \
            "$vpn_port" \
            "$server_public_key" \
            "$instance_id" \
            "$REGION" \
            "$OUTPUT_DIR"; then
            client_count=$((client_count + 1))
        else
            echo "Warning: Failed to generate client config for $client_name" >&2
            failed_clients=$((failed_clients + 1))
        fi
        echo ""
    done
    
    # Create metadata.json file in output directory
    local metadata_file="$OUTPUT_DIR/$STACK_NAME/metadata.json"
    local metadata_json="{
  \"stack_name\": \"$STACK_NAME\",
  \"region\": \"$REGION\",
  \"mode\": \"$MODE\",
  \"server_endpoint\": \"$public_ip:$vpn_port\",
  \"vpc_cidr\": \"$validated_vpc_cidr\",
  \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
  \"clients\": ["
    
    # Add client entries
    for ((i=1; i<=client_count; i++)); do
        local client_name="client-$i"
        local client_id=$((i + 1))
        
        if [ $i -gt 1 ]; then
            metadata_json="$metadata_json,"
        fi
        
        metadata_json="$metadata_json
    {
      \"name\": \"$client_name\",
      \"address\": \"10.99.0.$client_id/32\",
      \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"config_file\": \"$client_name.conf\"
    }"
    done
    
    metadata_json="$metadata_json
  ]
}"
    
    # Write metadata file
    if ! echo "$metadata_json" > "$metadata_file" 2>/dev/null; then
        echo "Warning: Failed to write metadata file: $metadata_file" >&2
    else
        echo "✓ Metadata saved: $metadata_file"
    fi
    
    echo ""
    echo "=== VPN Setup Complete ==="
    echo ""
    echo "✓ Successfully generated $client_count client configuration(s)"
    
    if [ $failed_clients -gt 0 ]; then
        echo "⚠️  Warning: $failed_clients client(s) failed to generate" >&2
    fi
    
    echo ""
    echo "Connection Information:"
    echo "  Endpoint:    $public_ip:$vpn_port"
    echo "  Mode:        $MODE"
    if [ "$MODE" = "full" ]; then
        echo "  Routing:     All traffic through VPN (0.0.0.0/0)"
    else
        echo "  Routing:     Only VPC traffic through VPN ($validated_vpc_cidr)"
    fi
    echo ""
    echo "Client Configuration Files:"
    for ((i=1; i<=client_count; i++)); do
        local client_name="client-$i"
        echo "  $OUTPUT_DIR/$STACK_NAME/clients/$client_name.conf"
    done
    echo ""
    echo "Next Steps:"
    echo "  1. Import a client config file to your WireGuard client:"
    echo "     - Mobile: Scan QR code or import file"
    echo "     - Desktop: Import .conf file"
    echo ""
    echo "  2. To add more clients later:"
    echo "     ./another_betterthannothing_vpn.sh add-client --name $STACK_NAME"
    echo ""
    echo "  3. To connect via SSM for troubleshooting:"
    echo "     ./another_betterthannothing_vpn.sh ssm --name $STACK_NAME"
    echo ""
    echo "  4. To delete the VPN when done:"
    echo "     ./another_betterthannothing_vpn.sh delete --name $STACK_NAME"
    echo ""
}

# Command: delete
cmd_delete() {
    # Parse stack name from arguments (already in STACK_NAME from parse_args)
    
    # Validate that stack name was provided
    if [ -z "$STACK_NAME" ]; then
        echo "Error: Stack name is required for delete command" >&2
        echo "Usage: ./another_betterthannothing_vpn.sh delete --name <stack-name> [--region <region>]" >&2
        exit 1
    fi
    
    # Validate stack exists
    if ! validate_stack_exists "$STACK_NAME" "$REGION"; then
        echo "Error: Stack '$STACK_NAME' does not exist in region '$REGION'" >&2
        echo "" >&2
        echo "To list all stacks in this region, run:" >&2
        echo "  ./another_betterthannothing_vpn.sh list --region $REGION" >&2
        exit 1
    fi
    
    # If --yes flag not set, prompt for confirmation
    if [ "$NON_INTERACTIVE" = false ]; then
        echo "This will delete the following CloudFormation stack and all its resources:"
        echo "  Stack Name: $STACK_NAME"
        echo "  Region:     $REGION"
        echo ""
        echo "Resources to be deleted:"
        echo "  - VPC and networking components"
        echo "  - EC2 instance (VPN server)"
        echo "  - Security Group"
        echo "  - IAM Role and Instance Profile"
        echo ""
        echo "Note: Local client configuration files will NOT be deleted."
        echo ""
        read -p "Delete stack '$STACK_NAME'? (y/N): " -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Deletion cancelled."
            exit 0
        fi
    fi
    
    # Execute delete-stack command
    echo "Deleting stack '$STACK_NAME'..."
    
    if ! aws cloudformation delete-stack \
        --stack-name "$STACK_NAME" \
        --region "$REGION" 2>&1; then
        echo "Error: Failed to initiate stack deletion" >&2
        exit 1
    fi
    
    echo "Stack deletion initiated. Waiting for completion (this may take a few minutes)..."
    
    # Wait for stack deletion to complete with timeout
    # The wait command has a built-in timeout
    if ! aws cloudformation wait stack-delete-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION" 2>&1; then
        
        # Check if the error is because stack doesn't exist (which means deletion succeeded)
        if ! validate_stack_exists "$STACK_NAME" "$REGION"; then
            echo "✓ Stack deleted successfully!"
        else
            # Stack still exists - deletion failed
            echo "" >&2
            echo "Error: Stack deletion failed or timed out" >&2
            echo "" >&2
            echo "Check stack status:" >&2
            echo "  ./another_betterthannothing_vpn.sh status --name $STACK_NAME --region $REGION" >&2
            echo "" >&2
            echo "Or check in AWS Console:" >&2
            echo "  https://console.aws.amazon.com/cloudformation/home?region=$REGION" >&2
            echo "" >&2
            echo "Common issues:" >&2
            echo "  - Resources may have dependencies preventing deletion" >&2
            echo "  - Manual intervention may be required in AWS Console" >&2
            exit 1
        fi
    else
        echo "✓ Stack deleted successfully!"
    fi
    
    echo ""
    echo "Stack '$STACK_NAME' has been deleted from region '$REGION'."
    echo ""
    echo "Note: Local client configuration files remain at:"
    echo "  $OUTPUT_DIR/$STACK_NAME/"
    echo ""
    echo "To remove local files, run:"
    echo "  rm -rf $OUTPUT_DIR/$STACK_NAME/"
    echo ""
}

# Command: start
cmd_start() {
    # Parse stack name from arguments (already in STACK_NAME from parse_args)
    
    # Validate that stack name was provided
    if [ -z "$STACK_NAME" ]; then
        echo "Error: Stack name is required for start command" >&2
        echo "Usage: ./another_betterthannothing_vpn.sh start --name <stack-name> [--region <region>]" >&2
        exit 1
    fi
    
    # Validate stack exists
    if ! validate_stack_exists "$STACK_NAME" "$REGION"; then
        echo "Error: Stack '$STACK_NAME' does not exist in region '$REGION'" >&2
        echo "" >&2
        echo "To list all stacks in this region, run:" >&2
        echo "  ./another_betterthannothing_vpn.sh list --region $REGION" >&2
        exit 1
    fi
    
    # Retrieve stack outputs to get InstanceId
    echo "Retrieving stack information..."
    local stack_outputs
    stack_outputs=$(get_stack_outputs "$STACK_NAME" "$REGION")
    
    # Extract instance ID from outputs
    local instance_id
    instance_id=$(echo "$stack_outputs" | jq -r '.InstanceId // empty')
    
    if [ -z "$instance_id" ]; then
        echo "Error: Failed to retrieve InstanceId from stack outputs" >&2
        exit 1
    fi
    
    echo "Instance ID: $instance_id"
    echo ""
    
    # Check current instance state
    echo "Checking instance state..."
    local instance_info
    if ! instance_info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --output json 2>&1); then
        echo "Error: Failed to describe instance $instance_id" >&2
        echo "$instance_info" >&2
        exit 1
    fi
    
    # Extract current state
    local current_state
    current_state=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].State.Name // "unknown"')
    
    echo "Current state: $current_state"
    
    # If already running, display message and exit
    if [ "$current_state" = "running" ]; then
        echo ""
        echo "Instance is already running."
        echo ""
        
        # Get current public IP
        local current_public_ip
        current_public_ip=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].PublicIpAddress // "N/A"')
        
        if [ "$current_public_ip" != "N/A" ]; then
            local vpn_port
            vpn_port=$(echo "$stack_outputs" | jq -r '.VpnPort // "51820"')
            
            echo "VPN endpoint: $current_public_ip:$vpn_port"
            echo ""
            echo "Your VPN is ready to use."
        fi
        
        exit 0
    fi
    
    # Start the instance
    echo ""
    echo "Starting instance '$instance_id'..."
    
    if ! aws ec2 start-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --output json > /dev/null 2>&1; then
        echo "Error: Failed to start instance $instance_id" >&2
        exit 1
    fi
    
    echo "Instance start initiated. Waiting for instance to be running..."
    
    # Wait for instance to be running
    if ! aws ec2 wait instance-running \
        --instance-ids "$instance_id" \
        --region "$REGION" 2>&1; then
        echo "" >&2
        echo "Error: Instance failed to reach running state or wait timed out" >&2
        echo "" >&2
        echo "Check instance status:" >&2
        echo "  ./another_betterthannothing_vpn.sh status --name $STACK_NAME --region $REGION" >&2
        exit 1
    fi
    
    echo "✓ Instance is now running!"
    echo ""
    
    # Get new public IP (may have changed)
    echo "Retrieving new public IP address..."
    local new_instance_info
    if ! new_instance_info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --output json 2>&1); then
        echo "Warning: Failed to retrieve new instance information" >&2
    else
        local new_public_ip
        new_public_ip=$(echo "$new_instance_info" | jq -r '.Reservations[0].Instances[0].PublicIpAddress // "N/A"')
        
        local vpn_port
        vpn_port=$(echo "$stack_outputs" | jq -r '.VpnPort // "51820"')
        
        echo ""
        echo "=== VPN Instance Started ==="
        echo ""
        echo "New VPN endpoint: $new_public_ip:$vpn_port"
        echo ""
        
        # Get old public IP from stack outputs for comparison
        local old_public_ip
        old_public_ip=$(echo "$stack_outputs" | jq -r '.PublicIp // "N/A"')
        
        # Display reminder to update client configs if IP changed
        if [ "$new_public_ip" != "$old_public_ip" ] && [ "$old_public_ip" != "N/A" ]; then
            echo "⚠️  IMPORTANT: Public IP has changed!" >&2
            echo "" >&2
            echo "Old IP: $old_public_ip" >&2
            echo "New IP: $new_public_ip" >&2
            echo "" >&2
            echo "You MUST update your client configurations with the new endpoint:" >&2
            echo "  1. Edit each .conf file in: $OUTPUT_DIR/$STACK_NAME/clients/" >&2
            echo "  2. Update the Endpoint line to: $new_public_ip:$vpn_port" >&2
            echo "" >&2
            echo "Or regenerate client configs:" >&2
            echo "  ./another_betterthannothing_vpn.sh add-client --name $STACK_NAME" >&2
            echo "" >&2
        else
            echo "Public IP unchanged. Your existing client configurations will continue to work."
            echo ""
        fi
        
        echo "Your VPN is ready to use!"
        echo ""
    fi
}

# Command: stop
cmd_stop() {
    # Parse stack name from arguments (already in STACK_NAME from parse_args)
    
    # Validate that stack name was provided
    if [ -z "$STACK_NAME" ]; then
        echo "Error: Stack name is required for stop command" >&2
        echo "Usage: ./another_betterthannothing_vpn.sh stop --name <stack-name> [--region <region>]" >&2
        exit 1
    fi
    
    # Validate stack exists
    if ! validate_stack_exists "$STACK_NAME" "$REGION"; then
        echo "Error: Stack '$STACK_NAME' does not exist in region '$REGION'" >&2
        echo "" >&2
        echo "To list all stacks in this region, run:" >&2
        echo "  ./another_betterthannothing_vpn.sh list --region $REGION" >&2
        exit 1
    fi
    
    # Retrieve stack outputs to get InstanceId
    echo "Retrieving stack information..."
    local stack_outputs
    stack_outputs=$(get_stack_outputs "$STACK_NAME" "$REGION")
    
    # Extract instance ID from outputs
    local instance_id
    instance_id=$(echo "$stack_outputs" | jq -r '.InstanceId // empty')
    
    if [ -z "$instance_id" ]; then
        echo "Error: Failed to retrieve InstanceId from stack outputs" >&2
        exit 1
    fi
    
    echo "Instance ID: $instance_id"
    echo ""
    
    # Check current instance state
    echo "Checking instance state..."
    local instance_info
    if ! instance_info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --output json 2>&1); then
        echo "Error: Failed to describe instance $instance_id" >&2
        echo "$instance_info" >&2
        exit 1
    fi
    
    # Extract current state
    local current_state
    current_state=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].State.Name // "unknown"')
    
    echo "Current state: $current_state"
    
    # If already stopped, display message and exit
    if [ "$current_state" = "stopped" ]; then
        echo ""
        echo "Instance is already stopped."
        echo ""
        echo "To start the instance again, run:"
        echo "  ./another_betterthannothing_vpn.sh start --name $STACK_NAME --region $REGION"
        echo ""
        exit 0
    fi
    
    # If --yes flag not set, prompt for confirmation
    if [ "$NON_INTERACTIVE" = false ]; then
        echo ""
        echo "This will stop the VPN instance. The VPN will be unavailable until started again."
        echo ""
        echo "Instance: $instance_id"
        echo "Stack:    $STACK_NAME"
        echo "Region:   $REGION"
        echo ""
        echo "Note: The infrastructure will remain (no charges for stopped instances,"
        echo "      but EBS volumes will continue to incur storage charges)."
        echo ""
        read -p "Stop instance '$instance_id'? (y/N): " -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Stop cancelled."
            exit 0
        fi
    fi
    
    # Stop the instance
    echo "Stopping instance '$instance_id'..."
    
    if ! aws ec2 stop-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --output json > /dev/null 2>&1; then
        echo "Error: Failed to stop instance $instance_id" >&2
        exit 1
    fi
    
    echo "Instance stop initiated. Waiting for instance to be stopped..."
    
    # Wait for instance to be stopped
    if ! aws ec2 wait instance-stopped \
        --instance-ids "$instance_id" \
        --region "$REGION" 2>&1; then
        echo "" >&2
        echo "Error: Instance failed to reach stopped state or wait timed out" >&2
        echo "" >&2
        echo "Check instance status:" >&2
        echo "  ./another_betterthannothing_vpn.sh status --name $STACK_NAME --region $REGION" >&2
        exit 1
    fi
    
    echo "✓ Instance is now stopped!"
    echo ""
    echo "=== VPN Instance Stopped ==="
    echo ""
    echo "The VPN server has been stopped and is no longer accessible."
    echo ""
    echo "⚠️  Important Notes:" >&2
    echo "  - VPN connections will not work until the instance is started again" >&2
    echo "  - No compute charges while stopped (only EBS storage charges apply)" >&2
    echo "  - Public IP may change when instance is restarted" >&2
    echo "" >&2
    echo "To start the instance again, run:"
    echo "  ./another_betterthannothing_vpn.sh start --name $STACK_NAME --region $REGION"
    echo ""
    echo "To permanently delete all resources, run:"
    echo "  ./another_betterthannothing_vpn.sh delete --name $STACK_NAME --region $REGION"
    echo ""
}

# Command: status
cmd_status() {
    # Parse stack name from arguments (already in STACK_NAME from parse_args)
    
    # Validate that stack name was provided
    if [ -z "$STACK_NAME" ]; then
        echo "Error: Stack name is required for status command" >&2
        echo "Usage: ./another_betterthannothing_vpn.sh status --name <stack-name> [--region <region>]" >&2
        exit 1
    fi
    
    # Retrieve stack information
    echo "Retrieving stack information..."
    local stack_info
    if ! stack_info=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --output json 2>&1); then
        echo "Error: Stack '$STACK_NAME' does not exist in region '$REGION'" >&2
        echo "" >&2
        echo "To list all stacks in this region, run:" >&2
        echo "  ./another_betterthannothing_vpn.sh list --region $REGION" >&2
        exit 1
    fi
    
    # Extract stack status
    local stack_status
    stack_status=$(echo "$stack_info" | jq -r '.Stacks[0].StackStatus // "UNKNOWN"')
    
    # Extract stack creation time
    local creation_time
    creation_time=$(echo "$stack_info" | jq -r '.Stacks[0].CreationTime // "N/A"')
    
    echo ""
    echo "=== Stack Information ==="
    echo "Stack Name:      $STACK_NAME"
    echo "Region:          $REGION"
    echo "Status:          $stack_status"
    echo "Created:         $creation_time"
    echo ""
    
    # Retrieve and display stack outputs
    echo "=== Stack Outputs ==="
    local stack_outputs
    stack_outputs=$(get_stack_outputs "$STACK_NAME" "$REGION")
    
    # Extract key outputs
    local instance_id
    instance_id=$(echo "$stack_outputs" | jq -r '.InstanceId // "N/A"')
    
    local public_ip
    public_ip=$(echo "$stack_outputs" | jq -r '.PublicIp // "N/A"')
    
    local vpc_id
    vpc_id=$(echo "$stack_outputs" | jq -r '.VpcId // "N/A"')
    
    local vpc_cidr
    vpc_cidr=$(echo "$stack_outputs" | jq -r '.VpcCidr // "N/A"')
    
    local vpn_port
    vpn_port=$(echo "$stack_outputs" | jq -r '.VpnPort // "N/A"')
    
    local vpn_protocol
    vpn_protocol=$(echo "$stack_outputs" | jq -r '.VpnProtocol // "N/A"')
    
    echo "Instance ID:     $instance_id"
    echo "Public IP:       $public_ip"
    echo "VPC ID:          $vpc_id"
    echo "VPC CIDR:        $vpc_cidr"
    echo "VPN Port:        $vpn_port"
    echo "VPN Protocol:    $vpn_protocol"
    echo ""
    
    # Query instance status if we have an instance ID
    if [ "$instance_id" != "N/A" ]; then
        echo "=== Instance Status ==="
        
        local instance_info
        if instance_info=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --region "$REGION" \
            --output json 2>&1); then
            
            # Extract instance state
            local instance_state
            instance_state=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].State.Name // "unknown"')
            
            # Extract instance type
            local instance_type
            instance_type=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].InstanceType // "N/A"')
            
            # Extract launch time
            local launch_time
            launch_time=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].LaunchTime // "N/A"')
            
            # Extract spot instance info
            local instance_lifecycle
            instance_lifecycle=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].InstanceLifecycle // "on-demand"')
            
            echo "State:           $instance_state"
            echo "Instance Type:   $instance_type"
            echo "Lifecycle:       $instance_lifecycle"
            echo "Launch Time:     $launch_time"
            echo ""
            
            # Check SSM agent status if instance is running
            if [ "$instance_state" = "running" ]; then
                echo "=== SSM Agent Status ==="
                
                local ssm_status
                ssm_status=$(aws ssm describe-instance-information \
                    --filters "Key=InstanceIds,Values=$instance_id" \
                    --region "$REGION" \
                    --output json 2>/dev/null || echo '{"InstanceInformationList":[]}')
                
                local instance_count
                instance_count=$(echo "$ssm_status" | jq -r '.InstanceInformationList | length')
                
                if [ "$instance_count" -gt 0 ]; then
                    local ping_status
                    ping_status=$(echo "$ssm_status" | jq -r '.InstanceInformationList[0].PingStatus // "Unknown"')
                    
                    local last_ping_time
                    last_ping_time=$(echo "$ssm_status" | jq -r '.InstanceInformationList[0].LastPingDateTime // "N/A"')
                    
                    local agent_version
                    agent_version=$(echo "$ssm_status" | jq -r '.InstanceInformationList[0].AgentVersion // "N/A"')
                    
                    echo "Ping Status:     $ping_status"
                    echo "Last Ping:       $last_ping_time"
                    echo "Agent Version:   $agent_version"
                else
                    echo "SSM Agent:       Not registered"
                fi
                echo ""
            fi
        else
            echo "Warning: Failed to retrieve instance information" >&2
            echo ""
        fi
    fi
    
    # Display VPN endpoint
    if [ "$public_ip" != "N/A" ] && [ "$vpn_port" != "N/A" ]; then
        echo "=== VPN Endpoint ==="
        echo "Endpoint:        $public_ip:$vpn_port"
        echo ""
    fi
    
    # Display number of client configs in output directory
    echo "=== Client Configurations ==="
    local client_dir="$OUTPUT_DIR/$STACK_NAME/clients"
    
    if [ -d "$client_dir" ]; then
        # Count .conf files in the directory
        local client_count
        client_count=$(find "$client_dir" -maxdepth 1 -name "*.conf" -type f 2>/dev/null | wc -l)
        
        echo "Config Directory: $client_dir"
        echo "Client Configs:   $client_count"
        
        # List client config files if any exist
        if [ "$client_count" -gt 0 ]; then
            echo ""
            echo "Available configs:"
            find "$client_dir" -maxdepth 1 -name "*.conf" -type f 2>/dev/null | sort | while read -r config_file; do
                local filename
                filename=$(basename "$config_file")
                echo "  - $filename"
            done
        fi
    else
        echo "Config Directory: Not found"
        echo "Client Configs:   0"
    fi
    echo ""
    
    # Display helpful next steps based on instance state
    if [ "$instance_id" != "N/A" ]; then
        local instance_state
        instance_state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --region "$REGION" \
            --output json 2>/dev/null | jq -r '.Reservations[0].Instances[0].State.Name // "unknown"')
        
        echo "=== Available Actions ==="
        
        if [ "$instance_state" = "running" ]; then
            echo "  - Connect via SSM:"
            echo "    ./another_betterthannothing_vpn.sh ssm --name $STACK_NAME --region $REGION"
            echo ""
            echo "  - Add new client:"
            echo "    ./another_betterthannothing_vpn.sh add-client --name $STACK_NAME --region $REGION"
            echo ""
            echo "  - Stop instance (save costs):"
            echo "    ./another_betterthannothing_vpn.sh stop --name $STACK_NAME --region $REGION"
        elif [ "$instance_state" = "stopped" ]; then
            echo "  - Start instance:"
            echo "    ./another_betterthannothing_vpn.sh start --name $STACK_NAME --region $REGION"
        fi
        
        echo ""
        echo "  - Delete stack:"
        echo "    ./another_betterthannothing_vpn.sh delete --name $STACK_NAME --region $REGION"
        echo ""
    fi
}

# Command: list
cmd_list() {
    # Query all stacks in region
    echo "Querying CloudFormation stacks in region '$REGION'..."
    echo ""
    
    local stacks_info
    if ! stacks_info=$(aws cloudformation list-stacks \
        --region "$REGION" \
        --output json 2>&1); then
        echo "Error: Failed to list stacks in region '$REGION'" >&2
        echo "$stacks_info" >&2
        exit 1
    fi
    
    # Filter stacks with names matching pattern 'another-*'
    # Filter out deleted stacks (status DELETE_COMPLETE)
    local filtered_stacks
    filtered_stacks=$(echo "$stacks_info" | jq -r '
        .StackSummaries[] | 
        select(.StackName | startswith("another-")) | 
        select(.StackStatus != "DELETE_COMPLETE") |
        {
            StackName: .StackName,
            StackStatus: .StackStatus,
            CreationTime: .CreationTime
        }
    ' | jq -s '.')
    
    # Check if any stacks found
    local stack_count
    stack_count=$(echo "$filtered_stacks" | jq 'length')
    
    if [ "$stack_count" -eq 0 ]; then
        echo "No VPN stacks found in region '$REGION'"
        echo ""
        echo "To create a new VPN stack, run:"
        echo "  ./another_betterthannothing_vpn.sh create --my-ip"
        echo ""
        exit 0
    fi
    
    # Display table header
    echo "=== VPN Stacks in $REGION ==="
    echo ""
    printf "%-30s %-25s %-15s %-30s\n" "Stack Name" "Status" "Region" "VPN Endpoint"
    printf "%-30s %-25s %-15s %-30s\n" "----------" "------" "------" "------------"
    
    # Iterate through each stack and display information
    echo "$filtered_stacks" | jq -c '.[]' | while read -r stack; do
        local stack_name
        stack_name=$(echo "$stack" | jq -r '.StackName')
        
        local stack_status
        stack_status=$(echo "$stack" | jq -r '.StackStatus')
        
        # Retrieve VPN endpoint from stack outputs
        local vpn_endpoint="N/A"
        
        # Only try to get outputs if stack is in a complete state
        if [[ "$stack_status" == *"COMPLETE"* ]] && [[ "$stack_status" != "DELETE_COMPLETE" ]]; then
            # Get stack outputs
            local stack_outputs
            if stack_outputs=$(aws cloudformation describe-stacks \
                --stack-name "$stack_name" \
                --region "$REGION" \
                --output json 2>/dev/null); then
                
                # Extract PublicIp and VpnPort from outputs
                local public_ip
                public_ip=$(echo "$stack_outputs" | jq -r '.Stacks[0].Outputs[]? | select(.OutputKey=="PublicIp") | .OutputValue // "N/A"')
                
                local vpn_port
                vpn_port=$(echo "$stack_outputs" | jq -r '.Stacks[0].Outputs[]? | select(.OutputKey=="VpnPort") | .OutputValue // "N/A"')
                
                # Construct endpoint if both values are available
                if [ "$public_ip" != "N/A" ] && [ "$vpn_port" != "N/A" ]; then
                    vpn_endpoint="$public_ip:$vpn_port"
                fi
            fi
        fi
        
        # Display row
        printf "%-30s %-25s %-15s %-30s\n" "$stack_name" "$stack_status" "$REGION" "$vpn_endpoint"
    done
    
    echo ""
    echo "Found $stack_count VPN stack(s)"
    echo ""
    echo "To view detailed status of a stack, run:"
    echo "  ./another_betterthannothing_vpn.sh status --name <stack-name> --region $REGION"
    echo ""
}

# Command: add-client
cmd_add_client() {
    # Parse stack name from arguments (already in STACK_NAME from parse_args)
    
    # Validate that stack name was provided
    if [ -z "$STACK_NAME" ]; then
        echo "Error: Stack name is required for add-client command" >&2
        echo "Usage: ./another_betterthannothing_vpn.sh add-client --name <stack-name> [--region <region>]" >&2
        exit 1
    fi
    
    # Validate stack exists
    if ! validate_stack_exists "$STACK_NAME" "$REGION"; then
        echo "Error: Stack '$STACK_NAME' does not exist in region '$REGION'" >&2
        echo "" >&2
        echo "To list all stacks in this region, run:" >&2
        echo "  ./another_betterthannothing_vpn.sh list --region $REGION" >&2
        exit 1
    fi
    
    # Retrieve stack information to check status
    echo "Retrieving stack information..."
    local stack_info
    if ! stack_info=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --output json 2>&1); then
        echo "Error: Failed to retrieve stack information for '$STACK_NAME'" >&2
        echo "$stack_info" >&2
        exit 1
    fi
    
    # Extract and validate stack status
    local stack_status
    stack_status=$(echo "$stack_info" | jq -r '.Stacks[0].StackStatus // "UNKNOWN"')
    
    if [ "$stack_status" != "CREATE_COMPLETE" ]; then
        echo "Error: Stack '$STACK_NAME' is not in CREATE_COMPLETE status" >&2
        echo "Current status: $stack_status" >&2
        echo "" >&2
        echo "The stack must be in CREATE_COMPLETE status to add clients." >&2
        echo "" >&2
        echo "Check stack status:" >&2
        echo "  ./another_betterthannothing_vpn.sh status --name $STACK_NAME --region $REGION" >&2
        exit 1
    fi
    
    echo "✓ Stack is in CREATE_COMPLETE status"
    echo ""
    
    # Retrieve stack outputs to get endpoint, port, VPC CIDR, mode
    echo "Retrieving stack outputs..."
    local stack_outputs
    stack_outputs=$(get_stack_outputs "$STACK_NAME" "$REGION")
    
    # Extract necessary outputs
    local instance_id
    instance_id=$(echo "$stack_outputs" | jq -r '.InstanceId // empty')
    
    local public_ip
    public_ip=$(echo "$stack_outputs" | jq -r '.PublicIp // empty')
    
    local vpn_port
    vpn_port=$(echo "$stack_outputs" | jq -r '.VpnPort // "51820"')
    
    local vpc_cidr
    vpc_cidr=$(echo "$stack_outputs" | jq -r '.VpcCidr // "10.10.0.0/16"')
    
    if [ -z "$instance_id" ] || [ -z "$public_ip" ]; then
        echo "Error: Failed to retrieve required stack outputs (InstanceId, PublicIp)" >&2
        exit 1
    fi
    
    echo "Instance ID: $instance_id"
    echo "VPN Endpoint: $public_ip:$vpn_port"
    echo "VPC CIDR: $vpc_cidr"
    echo ""
    
    # Load metadata.json to determine next client ID
    local metadata_file="$OUTPUT_DIR/$STACK_NAME/metadata.json"
    
    if [ ! -f "$metadata_file" ]; then
        echo "Error: Metadata file not found: $metadata_file" >&2
        echo "" >&2
        echo "This may indicate the stack was created without client configurations," >&2
        echo "or the output directory has been moved/deleted." >&2
        echo "" >&2
        echo "Expected location: $metadata_file" >&2
        exit 1
    fi
    
    echo "Loading metadata from: $metadata_file"
    
    # Read and parse metadata.json
    local metadata
    if ! metadata=$(cat "$metadata_file" 2>/dev/null); then
        echo "Error: Failed to read metadata file: $metadata_file" >&2
        exit 1
    fi
    
    # Extract mode from metadata
    local mode
    mode=$(echo "$metadata" | jq -r '.mode // "split"')
    
    # Extract existing clients count to determine next client ID
    local existing_client_count
    existing_client_count=$(echo "$metadata" | jq -r '.clients | length')
    
    # Calculate next client ID and name
    # Client IDs start at 2 (server is 1), so next_id = existing_count + 2
    local next_client_id=$((existing_client_count + 2))
    local next_client_name="client-$((existing_client_count + 1))"
    
    echo "Existing clients: $existing_client_count"
    echo "New client name: $next_client_name"
    echo "New client IP: 10.99.0.$next_client_id/32"
    echo ""
    
    # Check if we've exhausted the available IP space (10.99.0.2 - 10.99.0.254)
    # Maximum 253 clients (254 - 1 for server)
    if [ "$next_client_id" -gt 254 ]; then
        echo "Error: Maximum number of clients (253) reached for stack '$STACK_NAME'" >&2
        echo "" >&2
        echo "The WireGuard subnet (10.99.0.0/24) can only support 253 clients." >&2
        echo "" >&2
        echo "Consider creating a new VPN stack:" >&2
        echo "  ./another_betterthannothing_vpn.sh create --my-ip" >&2
        exit 1
    fi
    
    # Retrieve server public key from the server
    echo "Retrieving server public key..."
    local server_public_key
    if ! server_public_key=$(execute_remote_command "$instance_id" "$REGION" \
        "sudo cat /etc/wireguard/server_public.key" 60); then
        echo "Error: Failed to retrieve server public key" >&2
        echo "" >&2
        echo "The server may not be properly configured or SSM may not be accessible." >&2
        echo "" >&2
        echo "Try connecting via SSM to troubleshoot:" >&2
        echo "  ./another_betterthannothing_vpn.sh ssm --name $STACK_NAME --region $REGION" >&2
        exit 1
    fi
    
    # Remove any trailing whitespace/newlines
    server_public_key=$(echo "$server_public_key" | tr -d '\n\r' | xargs)
    
    echo "✓ Server public key retrieved"
    echo ""
    
    # Generate new client configuration
    echo "=== Generating Client Configuration ==="
    echo ""
    
    if ! generate_client_config \
        "$STACK_NAME" \
        "$next_client_name" \
        "$next_client_id" \
        "$mode" \
        "$vpc_cidr" \
        "$public_ip" \
        "$vpn_port" \
        "$server_public_key" \
        "$instance_id" \
        "$REGION" \
        "$OUTPUT_DIR"; then
        echo "" >&2
        echo "Error: Failed to generate client configuration" >&2
        exit 1
    fi
    
    echo ""
    
    # Update metadata.json with new client entry
    echo "Updating metadata file..."
    
    # Create new client entry
    local new_client_entry
    new_client_entry=$(jq -n \
        --arg name "$next_client_name" \
        --arg address "10.99.0.$next_client_id/32" \
        --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg config_file "$next_client_name.conf" \
        '{
            name: $name,
            address: $address,
            created_at: $created_at,
            config_file: $config_file
        }')
    
    # Add new client to metadata
    local updated_metadata
    if ! updated_metadata=$(echo "$metadata" | jq --argjson new_client "$new_client_entry" \
        '.clients += [$new_client]'); then
        echo "Error: Failed to update metadata" >&2
        exit 1
    fi
    
    # Write updated metadata back to file
    if ! echo "$updated_metadata" > "$metadata_file" 2>/dev/null; then
        echo "Error: Failed to write updated metadata to file: $metadata_file" >&2
        exit 1
    fi
    
    echo "✓ Metadata updated"
    echo ""
    
    # Display new client config location and connection instructions
    echo "=== Client Configuration Complete ==="
    echo ""
    echo "✓ New client '$next_client_name' added successfully!"
    echo ""
    echo "Client Configuration:"
    echo "  Name:        $next_client_name"
    echo "  IP Address:  10.99.0.$next_client_id/32"
    echo "  Config File: $OUTPUT_DIR/$STACK_NAME/clients/$next_client_name.conf"
    echo ""
    echo "Connection Information:"
    echo "  Endpoint:    $public_ip:$vpn_port"
    echo "  Mode:        $mode"
    if [ "$mode" = "full" ]; then
        echo "  Routing:     All traffic through VPN (0.0.0.0/0)"
    else
        echo "  Routing:     Only VPC traffic through VPN ($vpc_cidr)"
    fi
    echo ""
    echo "Next Steps:"
    echo "  1. Import the client config file to your WireGuard client:"
    echo "     $OUTPUT_DIR/$STACK_NAME/clients/$next_client_name.conf"
    echo ""
    echo "  2. For mobile devices, you can generate a QR code:"
    echo "     qrencode -t ansiutf8 < $OUTPUT_DIR/$STACK_NAME/clients/$next_client_name.conf"
    echo ""
    echo "  3. To add another client:"
    echo "     ./another_betterthannothing_vpn.sh add-client --name $STACK_NAME"
    echo ""
}

# Command: ssm
cmd_ssm() {
    # Validate required parameters
    if [ -z "$STACK_NAME" ]; then
        echo "Error: Stack name is required" >&2
        echo "Usage: ./another_betterthannothing_vpn.sh ssm --name <stack-name> [--region <region>]" >&2
        exit 1
    fi
    
    echo "Opening SSM session to VPN server..."
    echo ""
    
    # Validate stack exists
    if ! validate_stack_exists "$STACK_NAME" "$REGION"; then
        echo "Error: Stack '$STACK_NAME' not found in region '$REGION'" >&2
        echo "" >&2
        echo "Available stacks:" >&2
        # List available stacks
        aws cloudformation list-stacks \
            --region "$REGION" \
            --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
            --output json 2>/dev/null | \
            jq -r '.StackSummaries[] | select(.StackName | startswith("another-")) | "  - " + .StackName' || true
        echo "" >&2
        exit 1
    fi
    
    # Retrieve stack outputs
    echo "Retrieving stack information..."
    local outputs
    outputs=$(get_stack_outputs "$STACK_NAME" "$REGION")
    
    # Extract InstanceId
    local instance_id
    instance_id=$(echo "$outputs" | jq -r '.InstanceId // empty')
    
    if [ -z "$instance_id" ]; then
        echo "Error: Failed to retrieve InstanceId from stack outputs" >&2
        exit 1
    fi
    
    echo "Instance ID: $instance_id"
    echo ""
    
    # Verify session-manager-plugin is installed
    if ! command -v session-manager-plugin &> /dev/null; then
        echo "Error: session-manager-plugin is not installed" >&2
        echo "" >&2
        echo "The AWS Session Manager Plugin is required to connect to EC2 instances via SSM." >&2
        echo "" >&2
        echo "Installation instructions:" >&2
        echo "" >&2
        echo "  Linux:" >&2
        echo "    1. Download the plugin:" >&2
        echo "       curl 'https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm' -o session-manager-plugin.rpm" >&2
        echo "    2. Install (RPM-based):" >&2
        echo "       sudo yum install -y session-manager-plugin.rpm" >&2
        echo "    3. Or install (DEB-based):" >&2
        echo "       curl 'https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb' -o session-manager-plugin.deb" >&2
        echo "       sudo dpkg -i session-manager-plugin.deb" >&2
        echo "" >&2
        echo "  macOS:" >&2
        echo "    1. Using Homebrew:" >&2
        echo "       brew install --cask session-manager-plugin" >&2
        echo "    2. Or download manually:" >&2
        echo "       curl 'https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip' -o sessionmanager-bundle.zip" >&2
        echo "       unzip sessionmanager-bundle.zip" >&2
        echo "       sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin" >&2
        echo "" >&2
        echo "  Windows:" >&2
        echo "    1. Download the installer:" >&2
        echo "       https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe" >&2
        echo "    2. Run the installer" >&2
        echo "" >&2
        echo "For more information, see:" >&2
        echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html" >&2
        echo "" >&2
        exit 1
    fi
    
    # Check if instance is running
    echo "Checking instance state..."
    local instance_state
    instance_state=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --output json 2>/dev/null | jq -r '.Reservations[0].Instances[0].State.Name // "unknown"')
    
    if [ "$instance_state" != "running" ]; then
        echo "Warning: Instance is not in 'running' state (current state: $instance_state)" >&2
        echo "" >&2
        
        if [ "$instance_state" = "stopped" ]; then
            echo "The instance is stopped. Start it first:" >&2
            echo "  ./another_betterthannothing_vpn.sh start --name $STACK_NAME --region $REGION" >&2
            echo "" >&2
            exit 1
        else
            echo "Instance state: $instance_state" >&2
            echo "SSM connection may fail if the instance is not fully running." >&2
            echo "" >&2
        fi
    fi
    
    # Check SSM agent status
    echo "Checking SSM agent status..."
    local ssm_status
    ssm_status=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$instance_id" \
        --region "$REGION" \
        --output json 2>/dev/null || echo '{"InstanceInformationList":[]}')
    
    local instance_count
    instance_count=$(echo "$ssm_status" | jq -r '.InstanceInformationList | length')
    
    if [ "$instance_count" -eq 0 ]; then
        echo "Error: SSM agent is not registered for this instance" >&2
        echo "" >&2
        echo "Troubleshooting steps:" >&2
        echo "  1. Verify the instance has the SSM IAM role attached" >&2
        echo "  2. Verify the instance has internet connectivity" >&2
        echo "  3. Wait a few minutes for the SSM agent to register" >&2
        echo "  4. Check instance system logs:" >&2
        echo "     aws ec2 get-console-output --instance-id $instance_id --region $REGION" >&2
        echo "" >&2
        exit 1
    fi
    
    local ping_status
    ping_status=$(echo "$ssm_status" | jq -r '.InstanceInformationList[0].PingStatus // "Unknown"')
    
    if [ "$ping_status" != "Online" ]; then
        echo "Warning: SSM agent ping status is '$ping_status' (expected 'Online')" >&2
        echo "Connection may fail. Attempting anyway..." >&2
        echo "" >&2
    else
        echo "✓ SSM agent is online"
        echo ""
    fi
    
    # Execute SSM start-session
    echo "Starting SSM session..."
    echo "Press Ctrl+D or type 'exit' to close the session"
    echo ""
    echo "=========================================="
    echo ""
    
    # Execute the SSM session
    # Note: This is an interactive command that will block until the user exits
    if ! aws ssm start-session \
        --target "$instance_id" \
        --region "$REGION"; then
        echo "" >&2
        echo "=========================================="
        echo "" >&2
        echo "Error: SSM session failed" >&2
        echo "" >&2
        echo "Troubleshooting steps:" >&2
        echo "  1. Verify your AWS credentials have SSM permissions:" >&2
        echo "     - ssm:StartSession" >&2
        echo "     - ssm:TerminateSession" >&2
        echo "" >&2
        echo "  2. Verify the instance has the AmazonSSMManagedInstanceCore policy" >&2
        echo "" >&2
        echo "  3. Check SSM agent logs on the instance (if accessible):" >&2
        echo "     sudo journalctl -u amazon-ssm-agent" >&2
        echo "" >&2
        echo "  4. Verify Security Group allows outbound HTTPS (443) traffic" >&2
        echo "" >&2
        echo "  5. Check AWS Systems Manager service status:" >&2
        echo "     https://status.aws.amazon.com/" >&2
        echo "" >&2
        exit 1
    fi
    
    # Session ended successfully
    echo ""
    echo "=========================================="
    echo ""
    echo "SSM session closed"
    echo ""
}

# Main function
main() {
    # Check dependencies early (before parsing args to handle NixOS bootstrap)
    if ! check_dependencies "$@"; then
        exit 1
    fi
    
    parse_args "$@"

    # Route to appropriate command
    case "${COMMAND}" in
        create)
            cmd_create
            ;;
        delete)
            cmd_delete
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        status)
            cmd_status
            ;;
        list)
            cmd_list
            ;;
        add-client)
            cmd_add_client
            ;;
        ssm)
            cmd_ssm
            ;;
        help|--help)
            display_help
            exit 0
            ;;
        *)
            echo "Error: Unknown command: ${COMMAND}" >&2
            echo "Run 'another_betterthannothing_vpn.sh --help' for usage information" >&2
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
