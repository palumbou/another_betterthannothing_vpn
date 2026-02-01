# Design Document

## Overview

The "another_betterthannothing_vpn" system provides disposable VPN infrastructure on AWS with minimal attack surface and complete lifecycle automation. The architecture consists of three main components:

1. **CloudFormation Template** - Declarative infrastructure definition
2. **Orchestration Script** - Bash-based lifecycle management and VPN configuration
3. **WireGuard VPN Server** - Lightweight, modern VPN running on EC2

The design prioritizes security (SSM-only access, minimal inbound exposure), cost transparency (comprehensive tagging), and operational simplicity (single-command deployment and teardown).

### Key Design Decisions

**Understanding CIDR Parameters:**

The system uses two distinct CIDR parameters with different purposes:

1. **VPC CIDR (`--vpc-cidr`)**: Defines the internal private network for the VPC
   - Default: 10.10.0.0/16
   - Must be RFC 1918 private range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
   - Used for: VPC subnet, EC2 instance private IP, routing
   - Choose different CIDR if default conflicts with existing networks (e.g., corporate VPN)
   - Example: If your company uses 10.0.0.0/8, use `--vpc-cidr 172.16.0.0/16`

2. **Allowed Ingress CIDR (`--allowed-cidr` or `--my-ip`)**: Controls WHO can connect to the VPN
   - Default: 0.0.0.0/0 (anyone on internet - least secure)
   - Applied to: Security Group inbound rule for VPN port
   - Used for: Access control, security hardening
   - Best practice: Use `--my-ip` to restrict to your current public IP
   - Example: `--allowed-cidr 203.0.113.0/24` allows only that network to reach VPN port

**VPN Protocol: WireGuard**
- Modern, audited codebase (~4,000 lines vs OpenVPN's ~100,000)
- Superior performance and lower latency
- Built into Linux kernel (5.6+), minimal dependencies
- Simpler configuration than OpenVPN
- Strong cryptography (Curve25519, ChaCha20, Poly1305)

**OS Choice: Amazon Linux 2023**
- Native SSM agent support (pre-installed)
- Optimized for AWS infrastructure
- Long-term support and security updates
- WireGuard available in standard repositories
- x86_64 and ARM64 support
- Minimal attack surface (hardened by default)

**Instance Type: t4g.nano (default)**
- ARM-based Graviton2 processor (cost-effective)
- 2 vCPUs, 0.5 GB RAM (sufficient for WireGuard + SSM)
- ~$3/month (us-east-1 pricing)
- Fallback to t3.nano for x86_64 if specified
- User can override via --instance-type

**Networking: Public Subnet with IGW**
- Simpler than VPC endpoints (no additional costs)
- VPN requires public IP for client connectivity
- SSM traffic uses public AWS endpoints over TLS
- Security enforced via Security Group (not network isolation)
- Trade-off: Slightly larger attack surface, but mitigated by SG rules and IMDSv2


## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Region                          │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │              VPC (10.10.0.0/16)                       │ │
│  │                                                       │ │
│  │  ┌─────────────────────────────────────────────────┐ │ │
│  │  │   Public Subnet (10.10.1.0/24)                  │ │ │
│  │  │                                                 │ │ │
│  │  │   ┌──────────────────────────────────────┐     │ │ │
│  │  │   │  EC2 Instance (WireGuard Server)     │     │ │ │
│  │  │   │  - Amazon Linux 2023                 │     │ │ │
│  │  │   │  - WireGuard (UDP/51820)             │     │ │ │
│  │  │   │  - SSM Agent                         │     │ │ │
│  │  │   │  - IMDSv2 enforced                   │     │ │ │
│  │  │   │  - EBS encrypted                     │     │ │ │
│  │  │   └──────────────────────────────────────┘     │ │ │
│  │  │            │                    │               │ │ │
│  │  │            │ VPN Traffic        │ SSM (443)     │ │ │
│  │  │            │ (UDP/51820)        │               │ │ │
│  │  └────────────┼────────────────────┼───────────────┘ │ │
│  │               │                    │                 │ │
│  │         ┌─────▼────────┐     ┌─────▼──────┐         │ │
│  │         │ Internet     │     │  Internet  │         │ │
│  │         │ Gateway      │     │  Gateway   │         │ │
│  │         └──────────────┘     └────────────┘         │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                    │                        │
                    │                        │
         ┌──────────▼──────────┐  ┌──────────▼──────────┐
         │  VPN Clients        │  │  Operator (CLI)     │
         │  (WireGuard)        │  │  - AWS CLI          │
         │  - Full-tunnel or   │  │  - another.sh       │
         │  - Split-tunnel     │  │  - SSM plugin       │
         └─────────────────────┘  └─────────────────────┘
```

### Traffic Flows

**VPN Client → Server (Data Plane)**
1. Client initiates WireGuard handshake to `<PublicIP>:51820`
2. Security Group allows UDP/51820 from allowed CIDR
3. WireGuard authenticates using pre-shared keys
4. Encrypted tunnel established

**Full-Tunnel Mode**
- Client routes all traffic (0.0.0.0/0) through VPN
- Server performs NAT/masquerade via iptables
- Server forwards traffic to internet via IGW

**Split-Tunnel Mode**
- Client routes only VPC CIDR (10.10.0.0/16) through VPN
- Internet traffic bypasses VPN
- No NAT required on server

**Operator → Server (Control Plane)**
1. Operator runs `another.sh ssm --name <stack>`
2. Script invokes `aws ssm start-session --target <instance-id>`
3. SSM agent on instance establishes secure WebSocket to SSM service (443)
4. Interactive shell session over encrypted channel
5. No inbound connection to instance required


## Components and Interfaces

### 1. CloudFormation Template (`template.yaml`)

**Purpose:** Declarative infrastructure definition for complete VPN stack.

**Parameters:**
- `StackName` (String): Unique identifier for the stack
- `VpcCidr` (String, default: "10.10.0.0/16"): VPC CIDR block (must be RFC 1918 private range)
- `InstanceType` (String, default: "t4g.nano"): EC2 instance type
- `VpnPort` (Number, default: 51820): WireGuard listening port
- `VpnProtocol` (String, default: "udp"): Protocol for VPN traffic
- `AllowedIngressCidr` (String, default: "0.0.0.0/0"): Source CIDR allowed to connect to VPN port (Security Group ingress rule)
- `UseSpotInstance` (String, default: "false"): Use EC2 Spot instances for lower cost (can be interrupted)

**Resources:**
- `VPC`: AWS::EC2::VPC with EnableDnsHostnames and EnableDnsSupport
- `PublicSubnet`: AWS::EC2::Subnet in first AZ
- `InternetGateway`: AWS::EC2::InternetGateway
- `VPCGatewayAttachment`: Attaches IGW to VPC
- `PublicRouteTable`: AWS::EC2::RouteTable with default route to IGW
- `SubnetRouteTableAssociation`: Associates subnet with route table
- `VpnSecurityGroup`: AWS::EC2::SecurityGroup
  - Ingress: VpnProtocol/VpnPort from AllowedIngressCidr
  - Egress: All traffic (required for SSM, package installation, VPN)
- `VpnInstanceRole`: AWS::IAM::Role with AmazonSSMManagedInstanceCore
- `VpnInstanceProfile`: AWS::IAM::InstanceProfile
- `VpnInstance`: AWS::EC2::Instance
  - ImageId: Latest Amazon Linux 2023 AMI (via SSM parameter lookup)
  - IamInstanceProfile: VpnInstanceProfile
  - SecurityGroupIds: VpnSecurityGroup
  - UserData: Minimal bootstrap (install SSM agent if needed, set hostname)
  - MetadataOptions: HttpTokens=required (IMDSv2), HttpPutResponseHopLimit=1
  - BlockDeviceMappings: Encrypted EBS volume

**Outputs:**
- `InstanceId`: EC2 instance ID
- `PublicIp`: Public IP address of instance
- `VpcId`: VPC ID
- `VpcCidr`: VPC CIDR block
- `Region`: AWS region
- `VpnPort`: VPN listening port
- `VpnProtocol`: VPN protocol

**Tagging Strategy:**
All resources include:
```yaml
Tags:
  - Key: costcenter
    Value: !Ref AWS::StackName
  - Key: Name
    Value: !Sub "${AWS::StackName}-<resource-type>"
```

Stack-level tags applied via CLI during creation.


### 2. Orchestration Script (`another.sh`)

**Purpose:** Single entrypoint for all VPN lifecycle operations.

**Script Structure:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/template.yaml"
DEFAULT_OUTPUT_DIR="${HOME}/.another-vpn"
DEFAULT_REGION="us-east-1"

# Functions:
# - main()
# - parse_args()
# - check_dependencies()
# - nixos_bootstrap()
# - cmd_create()
# - cmd_delete()
# - cmd_status()
# - cmd_list()
# - cmd_add_client()
# - cmd_ssm()
# - bootstrap_vpn_server()
# - generate_client_config()
# - wait_for_ssm_ready()
# - execute_remote_command()
# - generate_stack_name()
# - validate_stack_exists()
# - get_stack_outputs()
# - display_help()
```

**Command Interface:**

```
another.sh <command> [options]

Commands:
  create       Create VPN stack and configure server
  delete       Delete VPN stack
  status       Show stack and instance status
  list         List all VPN stacks in region
  add-client   Add new VPN client configuration
  ssm          Open SSM session to VPN server

Options:
  --region <region>           AWS region (default: us-east-1)
  --name <stack-name>         Stack name (default: auto-generated)
  --mode <full|split>         Tunnel mode (default: split)
  --allowed-cidr <cidr>       Source CIDR allowed to connect to VPN (repeatable, default: 0.0.0.0/0)
  --my-ip                     Auto-detect and use operator's public IP/32 (mutually exclusive with --allowed-cidr)
  --vpc-cidr <cidr>           VPC CIDR block (default: 10.10.0.0/16, must be RFC 1918 private range)
  --instance-type <type>      EC2 instance type (default: t4g.nano)
  --spot                      Use EC2 Spot instances (lower cost, can be interrupted)
  --clients <n>               Number of initial clients (default: 1)
  --output-dir <path>         Output directory (default: ~/.another-vpn)
  --yes, --non-interactive    Skip confirmations
  --help                      Show this help message
```

**Key Functions:**

**`validate_vpc_cidr()`**
- Validates VPC CIDR is a valid CIDR notation (e.g., 10.10.0.0/16)
- Validates CIDR is within RFC 1918 private address space:
  - 10.0.0.0/8 (10.0.0.0 - 10.255.255.255)
  - 172.16.0.0/12 (172.16.0.0 - 172.31.255.255)
  - 192.168.0.0/16 (192.168.0.0 - 192.168.255.255)
- Validates prefix length is between /16 and /28 (reasonable VPC sizes)
- On invalid CIDR, displays error with examples of valid CIDRs
- Returns validated CIDR or exits with code 1

**`detect_my_ip()`**
- Detects the operator's public IP address
- Primary method: `curl -s https://api.ipify.org`
- Fallback method: `dig +short myip.opendns.com @resolver1.opendns.com`
- Validates IP format (IPv4 or IPv6)
- Returns IP with /32 (IPv4) or /128 (IPv6) suffix
- On failure, displays error and suggests manual --allowed-cidr

**`check_dependencies()`**
- Verifies `aws`, `jq`, `session-manager-plugin` are available
- On NixOS (detected via `/etc/NIXOS`), invokes `nixos_bootstrap()` if missing

**`nixos_bootstrap()`**
- Creates temporary shell with required packages
- Re-executes script within that environment
```bash
exec nix-shell -p awscli2 session-manager-plugin jq --run "$0 $*"
```

**`cmd_create()`**
1. Parse and validate arguments
2. Validate mutually exclusive flags (--my-ip and --allowed-cidr)
3. If --vpc-cidr is provided, validate it using `validate_vpc_cidr()`
4. If --my-ip is set, detect public IP via `curl -s https://api.ipify.org` or `dig +short myip.opendns.com @resolver1.opendns.com`
5. Generate stack name if not provided
6. Check if stack already exists (fail if yes)
7. Prepare CloudFormation parameters (including VpcCidr if custom)
8. Create stack with tags: `aws cloudformation create-stack --tags Key=costcenter,Value=<stack-name>`
9. Wait for completion: `aws cloudformation wait stack-create-complete`
10. Retrieve outputs: `aws cloudformation describe-stacks`
11. Wait for SSM agent ready: poll `aws ssm describe-instance-information`
12. Bootstrap VPN server: `bootstrap_vpn_server()`
13. Generate client configs: `generate_client_config()` × N
14. Display connection instructions

**`bootstrap_vpn_server()`**
1. Generate server private/public key pair
2. Create `/etc/wireguard/wg0.conf` via SSM:
```ini
[Interface]
Address = 10.99.0.1/24
ListenPort = 51820
PrivateKey = <server-private-key>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE  # full-tunnel only
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE  # full-tunnel only

[Peer]
# Peers added dynamically
```
3. Enable IP forwarding: `sysctl -w net.ipv4.ip_forward=1` and persist to `/etc/sysctl.d/99-wireguard.conf`
4. Start WireGuard: `systemctl enable --now wg-quick@wg0`

**`generate_client_config()`**
1. Generate client private/public key pair on server via SSM
2. Add peer to server config via SSM:
```bash
wg set wg0 peer <client-public-key> allowed-ips 10.99.0.<client-id>/32
wg-quick save wg0
```
3. Retrieve server public key and endpoint from stack outputs
4. Create client config file:
```ini
[Interface]
PrivateKey = <client-private-key>
Address = 10.99.0.<client-id>/24
DNS = 1.1.1.1  # optional

[Peer]
PublicKey = <server-public-key>
Endpoint = <server-public-ip>:51820
AllowedIPs = 0.0.0.0/0, ::/0  # full-tunnel
# OR
AllowedIPs = 10.10.0.0/16  # split-tunnel (VPC CIDR)
PersistentKeepalive = 25
```
5. Save to `<output-dir>/<stack-name>/clients/<client-name>.conf`
6. Set file permissions: `chmod 600`

**`execute_remote_command()`**
- Uses SSM Send-Command API for non-interactive commands
- Alternative: `aws ssm start-session` with `--document-name AWS-StartInteractiveCommand`
- Returns command output for parsing

**`cmd_ssm()`**
- Validates session-manager-plugin is installed
- Invokes: `aws ssm start-session --target <instance-id> --region <region>`


### 3. WireGuard VPN Server

**Purpose:** Lightweight VPN service providing encrypted tunnel for client traffic.

**Configuration:**
- Interface: `wg0`
- Server subnet: `10.99.0.0/24` (separate from VPC CIDR to avoid conflicts)
- Server address: `10.99.0.1/24`
- Client addresses: `10.99.0.2/32`, `10.99.0.3/32`, etc.
- Listen port: Configurable (default 51820)

**Key Management:**
- Server keys generated during bootstrap
- Client keys generated per-client (on-demand)
- Private keys never leave their respective hosts (except client config download)
- Keys generated using `wg genkey` and `wg pubkey`

**Full-Tunnel Configuration:**
- Server enables IP forwarding
- Server configures NAT via iptables:
  ```bash
  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
  iptables -A FORWARD -i wg0 -j ACCEPT
  iptables -A FORWARD -o wg0 -j ACCEPT
  ```
- Client AllowedIPs: `0.0.0.0/0, ::/0`
- All client traffic routed through VPN

**Split-Tunnel Configuration:**
- Server does NOT enable NAT
- Server only routes traffic destined for VPC CIDR
- Client AllowedIPs: `10.10.0.0/16` (VPC CIDR from stack outputs)
- Internet traffic bypasses VPN

**Security Hardening:**
- WireGuard uses state-of-the-art cryptography (no configuration needed)
- Peer authentication via public key cryptography
- Perfect forward secrecy (keys rotated automatically)
- No exposed management interface
- Configuration changes only via SSM (authenticated via IAM)


## Data Models

### Stack Metadata

Stored in CloudFormation stack and outputs:

```yaml
StackName: string          # Unique identifier (e.g., "another-20260201-a3f9")
Region: string             # AWS region (e.g., "us-east-1")
Status: string             # CloudFormation status (e.g., "CREATE_COMPLETE")
Tags:
  - Key: costcenter
    Value: <StackName>
Outputs:
  InstanceId: string       # EC2 instance ID (e.g., "i-0123456789abcdef0")
  PublicIp: string         # Public IP address (e.g., "54.123.45.67")
  VpcId: string            # VPC ID (e.g., "vpc-0123456789abcdef0")
  VpcCidr: string          # VPC CIDR (e.g., "10.10.0.0/16")
  VpnPort: number          # VPN port (e.g., 51820)
  VpnProtocol: string      # VPN protocol (e.g., "udp")
```

### Client Configuration

Stored locally in `<output-dir>/<stack-name>/clients/<client-name>.conf`:

```ini
[Interface]
PrivateKey = <base64-encoded-private-key>
Address = 10.99.0.<client-id>/24
DNS = 1.1.1.1

[Peer]
PublicKey = <base64-encoded-server-public-key>
Endpoint = <server-public-ip>:<vpn-port>
AllowedIPs = <cidr-list>  # Mode-dependent
PersistentKeepalive = 25
```

### Server Configuration

Stored on EC2 instance at `/etc/wireguard/wg0.conf`:

```ini
[Interface]
Address = 10.99.0.1/24
ListenPort = <vpn-port>
PrivateKey = <base64-encoded-private-key>
PostUp = <iptables-rules>    # Full-tunnel only
PostDown = <iptables-rules>  # Full-tunnel only

[Peer]
PublicKey = <client1-public-key>
AllowedIPs = 10.99.0.2/32

[Peer]
PublicKey = <client2-public-key>
AllowedIPs = 10.99.0.3/32
```

### Client Metadata

Stored locally in `<output-dir>/<stack-name>/clients/metadata.json`:

```json
{
  "stack_name": "another-20260201-a3f9",
  "region": "us-east-1",
  "mode": "split",
  "server_endpoint": "54.123.45.67:51820",
  "vpc_cidr": "10.10.0.0/16",
  "clients": [
    {
      "name": "client-1",
      "address": "10.99.0.2/32",
      "created_at": "2026-02-01T12:34:56Z",
      "config_file": "client-1.conf"
    },
    {
      "name": "client-2",
      "address": "10.99.0.3/32",
      "created_at": "2026-02-01T13:45:12Z",
      "config_file": "client-2.conf"
    }
  ]
}
```


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

This section defines the correctness properties that must hold for the another_betterthannothing_vpn system. These properties will be validated through a combination of unit tests (for specific examples and edge cases) and property-based tests (for universal properties across all inputs).

### Property 1: Cost Center Tag Completeness

*For any* CloudFormation template resource that supports AWS tags, the resource definition SHALL include a tag with Key="costcenter" and Value referencing the stack name parameter.

**Validates: Requirements 2.1**

**Rationale:** Cost tracking requires consistent tagging across all resources. This property ensures no taggable resource is missed during template development.

**Test Strategy:** Parse the CloudFormation YAML template, enumerate all resource types that support tags (EC2::Instance, EC2::VPC, EC2::Subnet, EC2::SecurityGroup, EC2::InternetGateway, EC2::RouteTable, IAM::Role), and verify each has the costcenter tag in its Tags array.

### Property 2: Client Configuration Completeness

*For any* generated WireGuard client configuration file, the file SHALL contain all required fields: [Interface] section with PrivateKey and Address, and [Peer] section with PublicKey, Endpoint, AllowedIPs, and PersistentKeepalive.

**Validates: Requirements 6.6**

**Rationale:** Incomplete client configurations will fail to establish VPN connections. This property ensures all generated configs are valid and complete.

**Test Strategy:** Generate client configurations with various modes (full-tunnel, split-tunnel) and parameters, parse each resulting .conf file, and verify all required INI sections and keys are present with non-empty values.

### Property 3: Stack Name Uniqueness Format

*For any* auto-generated stack name, the name SHALL match the pattern `another-YYYYMMDD-[a-z0-9]{4}` where YYYYMMDD is a valid date and the suffix is a 4-character alphanumeric string.

**Validates: Requirements 8.3**

**Rationale:** Auto-generated names must be unique and follow a consistent, recognizable pattern for easy identification and filtering.

**Test Strategy:** Invoke the name generation function multiple times and verify each result matches the expected regex pattern and that consecutive calls produce different names (probabilistic uniqueness).

### Property 4: Security Group Inbound Restriction

*For any* CloudFormation template with AllowedIngressCidr parameter, the VPN Security Group SHALL have exactly one ingress rule for the VPN port/protocol and SHALL NOT have any ingress rule for port 22 (SSH).

**Validates: Requirements 1.3, 3.1, 3.2**

**Rationale:** The core security requirement is that only VPN traffic is allowed inbound. This property ensures no accidental SSH exposure or additional ports.

**Test Strategy:** Parse the CloudFormation template, locate the SecurityGroup resource, extract all SecurityGroupIngress rules, and verify: (1) exactly one rule exists, (2) it references VpnPort parameter, (3) no rule has FromPort or ToPort equal to 22.

### Property 5: Mode-Dependent Configuration Consistency

*For any* VPN mode (full-tunnel or split-tunnel), the generated client configuration AllowedIPs field SHALL be "0.0.0.0/0, ::/0" when mode is full-tunnel, and SHALL be the VPC CIDR when mode is split-tunnel.

**Validates: Requirements 4.2, 4.3**

**Rationale:** The tunnel mode determines routing behavior. Incorrect AllowedIPs will cause traffic to route incorrectly (either leaking traffic or blocking legitimate access).

**Test Strategy:** Generate client configs with mode=full and mode=split, parse the AllowedIPs value from each, and verify it matches the expected value for that mode.

### Property 6: NAT Configuration Presence

*For any* VPN server bootstrap configuration with mode=full-tunnel, the generated server configuration SHALL include iptables NAT rules (POSTROUTING MASQUERADE), and when mode=split-tunnel, the configuration SHALL NOT include NAT rules.

**Validates: Requirements 4.1, 4.4**

**Rationale:** Full-tunnel requires NAT to forward client traffic to the internet. Split-tunnel must not NAT to avoid routing internet traffic. Incorrect NAT configuration breaks the intended traffic flow.

**Test Strategy:** Generate server bootstrap scripts/configs for both modes, parse the resulting iptables commands, and verify NAT rules are present only in full-tunnel mode.

### Property 7: Required CloudFormation Outputs

*For any* valid CloudFormation template, the Outputs section SHALL contain all required keys: InstanceId, PublicIp, VpcId, VpcCidr, Region, VpnPort, VpnProtocol.

**Validates: Requirements 1.7**

**Rationale:** The orchestration script depends on these outputs to configure the VPN and generate client configs. Missing outputs will cause runtime failures.

**Test Strategy:** Parse the CloudFormation template, extract the Outputs section, and verify all required output keys are present.

### Property 8: IMDSv2 Enforcement

*For any* EC2 instance resource in the CloudFormation template, the MetadataOptions SHALL have HttpTokens set to "required" and HttpPutResponseHopLimit set to 1.

**Validates: Requirements 1.5, 3.4**

**Rationale:** IMDSv2 prevents SSRF attacks against instance metadata. This property ensures the security hardening is applied.

**Test Strategy:** Parse the CloudFormation template, locate the EC2::Instance resource, extract MetadataOptions, and verify HttpTokens="required" and HttpPutResponseHopLimit=1.

### Property 9: EBS Encryption

*For any* EC2 instance resource in the CloudFormation template, all BlockDeviceMappings SHALL have Ebs.Encrypted set to true.

**Validates: Requirements 1.5, 3.6**

**Rationale:** Encrypted EBS volumes protect data at rest. This property ensures encryption is not accidentally disabled.

**Test Strategy:** Parse the CloudFormation template, locate the EC2::Instance resource, extract all BlockDeviceMappings, and verify each has Ebs.Encrypted=true.

### Property 10: Minimal IAM Permissions

*For any* IAM Role resource in the CloudFormation template, the ManagedPolicyArns SHALL contain exactly one policy: "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", and SHALL NOT contain any other policies.

**Validates: Requirements 1.4, 3.7**

**Rationale:** Principle of least privilege requires minimal permissions. This property ensures no excessive permissions are granted.

**Test Strategy:** Parse the CloudFormation template, locate the IAM::Role resource, extract ManagedPolicyArns, and verify it contains only the SSM policy ARN.

### Edge Cases and Error Conditions

The following edge cases will be covered by unit tests (not property-based tests):

- **Empty or invalid CIDR inputs:** Verify script rejects malformed CIDR blocks
- **Invalid VPC CIDR:** Verify script rejects non-RFC1918 CIDRs, invalid prefix lengths, and malformed notation
- **VPC CIDR conflicts:** Document that user should choose non-conflicting CIDR if connecting from corporate VPN
- **Missing AWS credentials:** Verify script fails gracefully with clear error message
- **Stack name conflicts:** Verify script detects existing stack and fails with clear message (Requirement 5.5)
- **SSM agent not ready:** Verify script waits and retries before failing
- **Invalid region:** Verify script validates region parameter
- **NixOS without nix-shell:** Verify script handles missing nix-shell gracefully
- **Client ID exhaustion:** Verify script handles running out of available IPs in 10.99.0.0/24 subnet (254 clients max)
- **0.0.0.0/0 ingress CIDR:** Verify script displays security warning (Requirement 3.5)
- **--my-ip with --allowed-cidr:** Verify script rejects mutually exclusive flags (Requirement 9.10)
- **IP detection service unavailable:** Verify script tries fallback and fails gracefully with helpful message
- **Operator behind NAT/proxy:** Verify detected IP is the public-facing IP, not internal IP
- **IPv6-only environments:** Verify script handles IPv6 addresses correctly with /128 suffix


## Error Handling

### CloudFormation Errors

**Stack Creation Failures:**
- Script monitors stack events during creation
- On failure, retrieves and displays stack events with status FAILED
- Displays resource-specific error messages
- Exits with non-zero code
- User must manually delete failed stack before retry

**Stack Already Exists:**
- Before creation, script calls `aws cloudformation describe-stacks`
- If stack exists, displays error: "Stack '<name>' already exists in region '<region>'. Use a different name or delete the existing stack."
- Exits with code 1
- Prevents accidental overwrites

**Stack Deletion Failures:**
- Script waits for deletion with timeout
- On timeout or failure, displays error and suggests manual cleanup
- Lists resources that may need manual deletion (e.g., ENIs, EIPs if retained)

### SSM Errors

**Agent Not Ready:**
- After stack creation, script polls `aws ssm describe-instance-information`
- Retries every 10 seconds for up to 5 minutes
- If agent doesn't appear, displays error with troubleshooting steps:
  - Check instance system logs
  - Verify IAM role attachment
  - Verify internet connectivity
- Exits with code 1

**Session Manager Plugin Missing:**
- Script checks for `session-manager-plugin` in PATH
- If missing, displays installation instructions for common platforms
- Provides link to AWS documentation
- Exits with code 1

**Command Execution Failures:**
- When executing remote commands via SSM, script checks command status
- On failure, displays command output and error
- For bootstrap failures, suggests manual SSM session for debugging

### VPN Configuration Errors

**Key Generation Failures:**
- If `wg genkey` fails, script captures error and exits
- Displays error message with suggestion to check WireGuard installation

**Client ID Exhaustion:**
- Script tracks used client IPs (10.99.0.2 - 10.99.0.254)
- If all IPs allocated, displays error: "Maximum clients (253) reached for stack '<name>'"
- Suggests creating a new stack or removing unused clients

**Invalid Configuration Parameters:**
- Script validates CIDR format using regex
- Script validates VPC CIDR is within RFC 1918 private ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- Script validates VPC CIDR prefix length is between /16 and /28
- Script validates AllowedIngressCidr format
- Validates instance type against known patterns
- Validates region against AWS region list
- Validates --my-ip and --allowed-cidr are not used together (mutually exclusive)
- On invalid input, displays error with expected format and examples
- Exits with code 1

**VPC CIDR Validation Errors:**
- If --vpc-cidr is not a valid CIDR notation: "Invalid CIDR format: '<input>'. Expected format: x.x.x.x/y"
- If --vpc-cidr is not RFC 1918 private: "VPC CIDR must be a private address range (10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16). Got: '<input>'"
- If --vpc-cidr prefix is too small or large: "VPC CIDR prefix must be between /16 and /28. Got: /<prefix>"
- Displays examples: "Valid examples: 10.10.0.0/16, 172.16.0.0/16, 192.168.1.0/24"
- Exits with code 1

**Public IP Detection Failures:**
- If --my-ip is used but IP detection fails (network error, service unavailable)
- Script tries primary method (ipify.org) then fallback (OpenDNS)
- If both fail, displays error: "Unable to detect public IP. Please use --allowed-cidr <your-ip>/32 instead."
- Exits with code 1
- Suggests checking internet connectivity

### AWS CLI Errors

**Missing Credentials:**
- Script relies on AWS CLI credential resolution
- If credentials missing, AWS CLI returns error
- Script captures and displays error
- Suggests running `aws configure` or setting environment variables

**Insufficient Permissions:**
- If IAM permissions insufficient, AWS CLI returns AccessDenied
- Script displays error with required permissions list:
  - cloudformation:CreateStack, DeleteStack, DescribeStacks
  - ec2:DescribeInstances, DescribeImages
  - ssm:DescribeInstanceInformation, StartSession, SendCommand
  - iam:PassRole (for instance profile)

**Rate Limiting:**
- AWS API rate limits may cause throttling
- Script uses AWS CLI built-in retry logic
- For persistent throttling, displays error and suggests retry after delay

### NixOS Bootstrap Errors

**nix-shell Not Available:**
- If `/etc/NIXOS` exists but `nix-shell` not in PATH
- Displays error: "NixOS detected but nix-shell not found. Please install Nix."
- Exits with code 1

**Package Installation Failures:**
- If nix-shell fails to install packages
- Displays nix-shell error output
- Suggests checking Nix configuration and network connectivity

### File System Errors

**Output Directory Creation:**
- Script creates output directory with `mkdir -p`
- If creation fails (permissions, disk full), displays error
- Exits with code 1

**Config File Write Failures:**
- If writing client config fails, displays error with path
- Suggests checking disk space and permissions
- Exits with code 1

**File Permission Errors:**
- After writing client configs, script sets permissions to 600
- If chmod fails, displays warning but continues
- User should manually secure files


## Testing Strategy

### Overview

The testing strategy employs a dual approach combining unit tests and property-based tests to ensure comprehensive coverage:

- **Unit tests** validate specific examples, edge cases, and error conditions
- **Property-based tests** validate universal properties across all inputs
- Both are complementary and necessary for comprehensive correctness validation

### Property-Based Testing

**Framework:** We will use `shunit2` for Bash script testing and `yq`/`jq` for YAML/JSON validation in property tests.

**Configuration:**
- Each property test runs a minimum of 100 iterations
- Each test is tagged with a comment referencing the design property
- Tag format: `# Feature: another-betterthannothing-vpn, Property N: <property_text>`

**Property Test Implementation:**

**Property 1: Cost Center Tag Completeness**
- Generate variations of the CloudFormation template
- For each taggable resource type, verify costcenter tag exists
- Test with different stack names to ensure tag value is parameterized

**Property 2: Client Configuration Completeness**
- Generate client configs with random parameters (modes, CIDRs, endpoints)
- Parse each config file and verify all required INI sections and keys
- Validate values are non-empty and properly formatted

**Property 3: Stack Name Uniqueness Format**
- Generate 100+ stack names
- Verify each matches regex: `^another-[0-9]{8}-[a-z0-9]{4}$`
- Verify no duplicates in generated set (probabilistic uniqueness)

**Property 4: Security Group Inbound Restriction**
- Parse template with various VpnPort parameters
- Verify exactly one ingress rule exists
- Verify no rule allows port 22
- Verify ingress rule references VpnPort parameter

**Property 5: Mode-Dependent Configuration Consistency**
- Generate client configs for both modes with random VPC CIDRs
- Verify full-tunnel configs have AllowedIPs = "0.0.0.0/0, ::/0"
- Verify split-tunnel configs have AllowedIPs = VPC CIDR

**Property 6: NAT Configuration Presence**
- Generate bootstrap scripts for both modes
- Verify full-tunnel includes "iptables -t nat -A POSTROUTING"
- Verify split-tunnel does NOT include NAT rules

**Property 7: Required CloudFormation Outputs**
- Parse template and extract Outputs section
- Verify all 7 required output keys are present
- Test with template variations

**Property 8: IMDSv2 Enforcement**
- Parse template and locate EC2::Instance resource
- Verify MetadataOptions.HttpTokens = "required"
- Verify MetadataOptions.HttpPutResponseHopLimit = 1

**Property 9: EBS Encryption**
- Parse template and locate all BlockDeviceMappings
- Verify each has Ebs.Encrypted = true

**Property 10: Minimal IAM Permissions**
- Parse template and locate IAM::Role resource
- Verify ManagedPolicyArns contains exactly one ARN
- Verify ARN is AmazonSSMManagedInstanceCore

### Unit Testing

**Framework:** `shunit2` for Bash, `bats` as alternative.

**Test Categories:**

**1. Template Validation Tests**
- Verify template is valid YAML
- Verify all required resources are present
- Verify parameter defaults are correct
- Verify resource dependencies are correct (DependsOn)

**2. Script Command Parsing Tests**
- Test each command (create, delete, status, list, add-client, ssm) is recognized
- Test invalid commands produce help message
- Test --help flag displays usage
- Test parameter parsing for all flags

**3. Stack Name Generation Tests**
- Test auto-generation produces valid names
- Test manual names are accepted
- Test name validation rejects invalid characters

**4. Public IP Detection Tests**
- Test detect_my_ip() returns valid IPv4 with /32 suffix
- Test detect_my_ip() returns valid IPv6 with /128 suffix (if applicable)
- Test detect_my_ip() handles network failures gracefully
- Test --my-ip and --allowed-cidr are mutually exclusive (script exits with error)
- Test --my-ip sets AllowedIngressCidr parameter correctly

**5. VPC CIDR Validation Tests**
- Test validate_vpc_cidr() accepts valid RFC 1918 CIDRs (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- Test validate_vpc_cidr() rejects public IP ranges (e.g., 8.8.8.0/24)
- Test validate_vpc_cidr() rejects invalid CIDR notation (e.g., "10.10.0.0", "10.10.0.0/33")
- Test validate_vpc_cidr() rejects prefix lengths outside /16-/28 range
- Test validate_vpc_cidr() accepts various valid private CIDRs (10.10.0.0/16, 172.16.0.0/20, 192.168.1.0/24)
- Test --vpc-cidr parameter is passed correctly to CloudFormation

**6. Dependency Checking Tests**
- Test check_dependencies detects missing aws CLI
- Test check_dependencies detects missing jq
- Test check_dependencies detects missing session-manager-plugin
- Test NixOS detection via /etc/NIXOS

**5. Dependency Checking Tests**
- Test check_dependencies detects missing aws CLI
- Test check_dependencies detects missing jq
- Test check_dependencies detects missing session-manager-plugin
- Test NixOS detection via /etc/NIXOS

**6. NixOS Bootstrap Tests**
- Test nixos_bootstrap constructs correct nix-shell command
- Test script re-execution with preserved arguments

**6. NixOS Bootstrap Tests**
- Test nixos_bootstrap constructs correct nix-shell command
- Test script re-execution with preserved arguments

**7. Configuration Generation Tests**
- Test server config generation includes correct interface address
- Test server config generation includes correct listen port
- Test client config generation includes correct peer section
- Test client config file permissions are set to 600

**7. Configuration Generation Tests**
- Test server config generation includes correct interface address
- Test server config generation includes correct listen port
- Test client config generation includes correct peer section
- Test client config file permissions are set to 600

**8. Mode-Specific Tests**
- Test full-tunnel generates iptables NAT rules
- Test split-tunnel omits NAT rules
- Test full-tunnel client config has AllowedIPs = 0.0.0.0/0
- Test split-tunnel client config has AllowedIPs = VPC CIDR

**8. Mode-Specific Tests**
- Test full-tunnel generates iptables NAT rules
- Test split-tunnel omits NAT rules
- Test full-tunnel client config has AllowedIPs = 0.0.0.0/0
- Test split-tunnel client config has AllowedIPs = VPC CIDR

**9. Error Handling Tests**
- Test script exits with error when stack already exists
- Test script displays warning for 0.0.0.0/0 ingress CIDR
- Test script handles missing AWS credentials gracefully
- Test script handles SSM agent timeout
- Test script handles client ID exhaustion

**9. Error Handling Tests**
- Test script exits with error when stack already exists
- Test script displays warning for 0.0.0.0/0 ingress CIDR
- Test script handles missing AWS credentials gracefully
- Test script handles SSM agent timeout
- Test script handles client ID exhaustion
- Test script rejects --my-ip used with --allowed-cidr
- Test script handles IP detection failures gracefully

**10. AWS CLI Command Construction Tests**
- Test create-stack command includes correct parameters
- Test create-stack command includes tags
- Test delete-stack command includes correct stack name
- Test SSM start-session command includes correct instance ID

**10. AWS CLI Command Construction Tests**
- Test create-stack command includes correct parameters
- Test create-stack command includes tags
- Test delete-stack command includes correct stack name
- Test SSM start-session command includes correct instance ID

**11. Output and Logging Tests**
- Test script displays progress messages
- Test script displays connection instructions after creation
- Test script does not display private keys in stdout
- Test script displays security warning for 0.0.0.0/0

**11. Output and Logging Tests**
- Test script displays progress messages
- Test script displays connection instructions after creation
- Test script does not display private keys in stdout
- Test script displays security warning for 0.0.0.0/0
- Test script displays detected IP when --my-ip is used

### Integration Testing

**Note:** Integration tests require actual AWS resources and are not part of the automated test suite. They should be run manually before releases.

**Integration Test Scenarios:**

1. **Full Stack Creation and Deletion**
   - Create stack in test region
   - Verify all resources created
   - Verify SSM access works
   - Generate client config
   - Delete stack
   - Verify all resources deleted

2. **VPN Connectivity**
   - Create stack with full-tunnel mode
   - Import client config to WireGuard client
   - Establish connection
   - Verify traffic routes through VPN (check public IP)
   - Disconnect and test split-tunnel mode

3. **Multi-Client Scenario**
   - Create stack with --clients 3
   - Verify 3 client configs generated
   - Add 4th client with add-client command
   - Verify all 4 clients can connect simultaneously

4. **Multi-Region Deployment**
   - Create stacks in 3 different regions
   - Verify each is independent
   - Verify list command shows all stacks

5. **Error Recovery**
   - Attempt to create stack with existing name (should fail)
   - Create stack, manually stop SSM agent, verify script detects
   - Create stack with invalid CIDR (should fail)

### Test Execution

**Local Development:**
```bash
# Run all unit tests
./tests/run_unit_tests.sh

# Run property tests
./tests/run_property_tests.sh

# Run specific test file
shunit2 tests/test_template_validation.sh
```

**CI/CD Pipeline:**
- Unit tests run on every commit
- Property tests run on every commit
- Integration tests run on release branches (manual trigger)
- Template validation runs on every commit

### Test Coverage Goals

- **Unit test coverage:** 80%+ of script functions
- **Property test coverage:** 100% of defined correctness properties
- **Edge case coverage:** All identified edge cases have explicit tests
- **Error path coverage:** All error handling paths tested

