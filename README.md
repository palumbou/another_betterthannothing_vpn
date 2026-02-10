# Another Betterthannothing VPN

A disposable VPN infrastructure on AWS with minimal attack surface and complete lifecycle automation.

> **Available languages**: [English (current)](README.md) | [Italiano](README.it.md)

## Overview

`Another Betterthannothing VPN` creates a dedicated AWS VPC with an EC2 instance running WireGuard VPN, manageable entirely through CloudFormation and a single Bash script. The infrastructure supports both full-tunnel (all traffic through VPN) and split-tunnel (only VPC traffic through VPN) modes, with secure access via AWS Systems Manager (SSM) only—no public SSH exposure.

**Key Features:**
- 🔒 **Secure by default**: SSM-only access, no SSH exposure, IMDSv2 enforced
- 💰 **Cost transparent**: All resources tagged with `CostCenter` for accurate tracking
- ⚡ **Single-command deployment**: Create, configure, and generate client configs in one step
- 🌍 **Multi-region support**: Deploy VPN infrastructure in any AWS region
- 🔄 **Ephemeral**: Designed for temporary use cases, easy to create and destroy
- 🐧 **NixOS compatible**: Automatic dependency management for declarative environments

## Table of Contents

- [Security / Threat Model](#security--threat-model)
- [Ephemeral Compute Box](#ephemeral-compute-box)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [CLI Reference](#cli-reference)
- [Understanding CIDR Parameters](#understanding-cidr-parameters)
- [Elastic IP (EIP) Support](#elastic-ip-eip-support)
- [Security Best Practices](#security-best-practices)
- [Cost Considerations](#cost-considerations)
- [Examples](#examples)
- [Execution Logs](#execution-logs)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

## Security / Threat Model

### The "Better Than Nothing" Approach

This VPN is designed for **temporary, low-stakes scenarios** where you need basic network privacy or access to AWS resources. It is **NOT** a replacement for enterprise VPN solutions or privacy-focused services like Mullvad or ProtonVPN.

**When to use this VPN:**
- ✅ Accessing AWS resources in a private VPC from your laptop
- ✅ Temporary lab environments for testing and development
- ✅ Quick access to internal services during travel
- ✅ Running ephemeral compute workloads (see below)
- ✅ Learning about VPN infrastructure and WireGuard

**When NOT to use this VPN:**
- ❌ Protecting sensitive corporate data or communications
- ❌ Bypassing censorship in hostile environments (single point of failure)
- ❌ Long-term production workloads requiring high availability
- ❌ Scenarios requiring anonymity (AWS account is tied to your identity)
- ❌ Compliance-regulated environments (HIPAA, PCI-DSS, etc.)

### Limitations and Risks

**Infrastructure Limitations:**
- **Single point of failure**: One EC2 instance, no redundancy
- **No DDoS protection**: Basic Security Group rules only
- **AWS account linkage**: All traffic is associated with your AWS account
- **Spot instance interruptions**: If using `--spot`, instance can be terminated with 2-minute notice
- **Public IP changes**: Stopping/starting the instance changes the public IP

**Security Considerations:**
- **Trust in AWS**: You're trusting AWS infrastructure and your account security
- **CloudWatch logs**: VPC Flow Logs (if enabled) can capture metadata
- **Cost tracking**: All resources are tagged with your stack name
- **Key management**: Client private keys are stored locally on your machine

### What This VPN Protects Against

✅ **Unencrypted WiFi**: Encrypts traffic on untrusted networks (coffee shops, airports)  
✅ **Basic snooping**: Prevents casual observation of your traffic  
✅ **IP-based restrictions**: Access services that filter by IP address  
✅ **VPC access**: Securely access private AWS resources without exposing them publicly

### What This VPN Does NOT Protect Against

❌ **Determined adversaries**: State-level actors, sophisticated attackers  
❌ **AWS itself**: AWS can see your traffic metadata and resource usage  
❌ **Endpoint compromise**: If your laptop is compromised, VPN doesn't help  
❌ **Traffic analysis**: Timing and volume patterns may still be observable

## Ephemeral Compute Box

One powerful use case is treating the VPN server as a **temporary compute environment** for running workloads that need:
- A clean, isolated environment
- A different IP address or geographic location
- Access to AWS services from within the same region (lower latency, no data transfer costs)

### Example: Running Docker Containers

Once connected to the VPN, you can SSH into the instance via SSM and run Docker workloads:

```bash
# Open SSM session to the VPN server
./another_betterthannothing_vpn.sh ssm --name my-vpn-stack

# Inside the instance, install Docker
sudo dnf install -y docker
sudo systemctl start docker

# Run a temporary web scraper
sudo docker run --rm -it python:3.11 bash
pip install requests beautifulsoup4
python your_script.py

# Run a database for testing
sudo docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=test postgres:15

# Access from your laptop (through the VPN tunnel)
psql -h 10.10.1.x -U postgres
```

### Example: Temporary Build Environment

```bash
# Connect via SSM
./another_betterthannothing_vpn.sh ssm --name my-vpn-stack

# Install build tools
sudo dnf install -y gcc make git

# Clone and build a project
git clone https://github.com/example/project.git
cd project
make

# Copy artifacts back to your laptop via S3 or SCP through VPN
```

### Accessing Services on the VPN Server

To access services running on the VPN server itself (Docker containers, Apache, databases, etc.) from your VPN client, use the `--reach-server` flag when creating the VPN:

```bash
./another_betterthannothing_vpn.sh create --my-ip --reach-server
```

This adds the VPN subnet (`10.99.0.0/24`) to the client's AllowedIPs, allowing you to reach the server at `10.99.0.1`.

**Important:** Services must bind to `0.0.0.0` or `10.99.0.1` to be reachable via VPN:

```bash
# Inside the VPN server (via SSM)

# Docker: expose on all interfaces
sudo docker run -d -p 0.0.0.0:8080:80 nginx

# Or bind specifically to VPN interface
sudo docker run -d -p 10.99.0.1:8080:80 nginx

# From your laptop (connected to VPN)
curl http://10.99.0.1:8080
```

**Benefits:**
- 🧹 **Clean slate**: Fresh environment every time, no leftover dependencies
- 💸 **Cost-effective**: Pay only for what you use, destroy when done
- 🔒 **Isolated**: Separate from your laptop, easy to wipe
- ⚡ **Fast AWS access**: Same-region access to S3, RDS, etc. with no data transfer costs

## Prerequisites

Before using this tool, ensure you have the following installed:

### 1. AWS CLI (v2 recommended)

**Installation:**
- **Linux**: `curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install`
- **macOS**: `brew install awscli` or download from [AWS](https://aws.amazon.com/cli/)
- **Windows**: Download installer from [AWS](https://aws.amazon.com/cli/)

**Configuration:**
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, default region, and output format
```

**Required IAM Permissions:**
Your AWS credentials must have permissions for:
- `cloudformation:CreateStack`, `DeleteStack`, `DescribeStacks`, `ListStacks`
- `ec2:DescribeInstances`, `DescribeImages`, `StartInstances`, `StopInstances`
- `ssm:DescribeInstanceInformation`, `StartSession`, `SendCommand`
- `iam:PassRole` (for attaching the instance profile)

### 2. AWS Systems Manager Session Manager Plugin

**Installation:**
- **Linux**: [Installation guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html#install-plugin-linux)
- **macOS**: `brew install --cask session-manager-plugin`
- **Windows**: [Download installer](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html#install-plugin-windows)

**Verify installation:**
```bash
session-manager-plugin
# Should display usage information
```

### 3. jq (JSON processor)

**Installation:**
- **Linux**: `sudo dnf install jq` or `sudo apt install jq`
- **macOS**: `brew install jq`
- **Windows**: Download from [jq website](https://stedolan.github.io/jq/)

### 4. WireGuard Client (on your devices)

**Installation:**
- **Linux**: `sudo dnf install wireguard-tools` or `sudo apt install wireguard`
- **macOS**: Download from [WireGuard website](https://www.wireguard.com/install/) or `brew install wireguard-tools`
- **Windows**: Download from [WireGuard website](https://www.wireguard.com/install/)
- **iOS/Android**: Install WireGuard app from App Store / Google Play

### NixOS Users

If you're on NixOS, the script will automatically detect missing dependencies and create a temporary shell with all required packages. No manual installation needed!

## Quick Start

### Create a VPN (Split-Tunnel Mode)

Split-tunnel mode routes only VPC traffic through the VPN, leaving internet traffic on your local connection:

```bash
# Create VPN with auto-detected public IP restriction (most secure)
./another_betterthannothing_vpn.sh create --my-ip --mode split

# Or specify your IP manually
./another_betterthannothing_vpn.sh create --allowed-cidr 203.0.113.42/32 --mode split

# Custom VPC CIDR (if default 10.10.0.0/16 conflicts with your network)
./another_betterthannothing_vpn.sh create --my-ip --mode split --vpc-cidr 172.16.0.0/16
```

**What happens:**
1. Creates CloudFormation stack with VPC, subnet, security group, IAM role, and EC2 instance
2. Waits for instance to be ready and SSM agent to connect
3. Installs and configures WireGuard on the server
4. Generates client configuration file
5. Displays connection instructions

**Output:**
```
Creating stack 'abthn-vpn-20260201-a3f9' in region 'us-east-1'...
Stack creation complete!
Instance ready, bootstrapping VPN server...
VPN server configured successfully!

Client configuration saved to: ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-1.conf

Connection Instructions:
  Endpoint: 54.123.45.67:51820
  Mode: split-tunnel (only VPC traffic: 10.10.0.0/16)

To connect:
  1. Import the config file to your WireGuard client
  2. Activate the connection

To add more clients:
  ./another_betterthannothing_vpn.sh add-client --name abthn-vpn-20260201-a3f9
```

### Create a VPN (Full-Tunnel Mode)

Full-tunnel mode routes ALL traffic through the VPN:

```bash
# Create full-tunnel VPN with IP restriction
./another_betterthannothing_vpn.sh create --my-ip --mode full

# Use Spot instances for lower cost (can be interrupted)
./another_betterthannothing_vpn.sh create --my-ip --mode full --spot
```

### Import Configuration to WireGuard Client

**Linux/macOS:**
```bash
# Copy config to WireGuard directory
sudo cp ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-1.conf /etc/wireguard/

# Start the VPN
sudo wg-quick up client-1

# Stop the VPN
sudo wg-quick down client-1
```

**Windows/macOS GUI:**
1. Open WireGuard application
2. Click "Import tunnel(s) from file"
3. Select the `.conf` file
4. Click "Activate"

**iOS/Android:**
1. Open WireGuard app
2. Tap "+" → "Create from file or archive"
3. Select the `.conf` file (transfer via AirDrop, email, etc.)
4. Tap the toggle to connect

## CLI Reference

### Commands

#### `create`

Create a new VPN stack with all infrastructure and configuration.

```bash
./another_betterthannothing_vpn.sh create [options]
```

**Options:**
- `--region <region>` - AWS region (default: us-east-1)
- `--name <stack-name>` - Stack name (default: auto-generated as `another-YYYYMMDD-xxxx`)
- `--mode <full|split>` - Tunnel mode (default: split)
  - `full`: Route all traffic through VPN
  - `split`: Route only VPC traffic through VPN
- `--allowed-cidr <cidr>` - Source CIDR allowed to connect to VPN port (repeatable, default: 0.0.0.0/0)
- `--my-ip` - Auto-detect and use your public IP/32 (mutually exclusive with --allowed-cidr)
- `--vpc-cidr <cidr>` - VPC CIDR block (default: 10.10.0.0/16, must be RFC 1918 private range)
- `--instance-type <type>` - EC2 instance type (default: t4g.nano)
- `--spot` - Use EC2 Spot instances for lower cost (can be interrupted)
- `--eip` - Allocate an Elastic IP for persistent public IP address
- `--reach-server` - Include VPN server subnet (10.99.0.0/24) in client AllowedIPs, allowing clients to reach services running on the VPN server itself (e.g., Docker containers)
- `--clients <n>` - Number of initial client configs to generate (default: 1)
- `--output-dir <path>` - Output directory for client configs (default: ./another_betterthannothing_vpn_config)
- `--yes` - Skip confirmation prompts

**Examples:**
```bash
# Minimal secure setup
./another_betterthannothing_vpn.sh create --my-ip

# Full-tunnel with custom region
./another_betterthannothing_vpn.sh create --my-ip --mode full --region eu-west-1

# Generate 3 client configs at creation
./another_betterthannothing_vpn.sh create --my-ip --clients 3

# Use Spot instance for cost savings
./another_betterthannothing_vpn.sh create --my-ip --spot

# Custom VPC CIDR to avoid conflicts
./another_betterthannothing_vpn.sh create --my-ip --vpc-cidr 172.16.0.0/16

# Create VPN with Elastic IP (persistent IP address)
./another_betterthannothing_vpn.sh create --my-ip --eip

# Create VPN with access to server itself (for Docker containers, etc.)
./another_betterthannothing_vpn.sh create --my-ip --reach-server
```

#### `delete`

Delete a VPN stack and all associated infrastructure.

```bash
./another_betterthannothing_vpn.sh delete --name <stack-name> [options]
```

**Options:**
- `--region <region>` - AWS region (default: us-east-1)
- `--yes` - Skip confirmation prompt

**Example:**
```bash
./another_betterthannothing_vpn.sh delete --name abthn-vpn-20260201-a3f9 --yes
```

**Note:** This deletes all AWS resources but does NOT delete local client configuration files.

#### `status`

Display status information for a VPN stack.

```bash
./another_betterthannothing_vpn.sh status --name <stack-name> [options]
```

**Options:**
- `--region <region>` - AWS region (default: us-east-1)

**Example:**
```bash
./another_betterthannothing_vpn.sh status --name abthn-vpn-20260201-a3f9
```

**Output:**
```
Stack: abthn-vpn-20260201-a3f9
Status: CREATE_COMPLETE
Region: us-east-1
Instance ID: i-0123456789abcdef0
Instance State: running
Public IP: 54.123.45.67
VPC CIDR: 10.10.0.0/16
VPN Endpoint: 54.123.45.67:51820
Client Configs: 2
```

#### `list`

List all VPN stacks in a region.

```bash
./another_betterthannothing_vpn.sh list [options]
```

**Options:**
- `--region <region>` - AWS region (default: us-east-1)

**Example:**
```bash
./another_betterthannothing_vpn.sh list --region us-east-1
```

**Output:**
```
Stack Name                  Status              Region      VPN Endpoint
abthn-vpn-20260201-a3f9      CREATE_COMPLETE     us-east-1   54.123.45.67:51820
abthn-vpn-20260201-b7k2      CREATE_COMPLETE     us-east-1   54.234.56.78:51820
```

#### `add-client`

Generate a new client configuration for an existing VPN stack.

```bash
./another_betterthannothing_vpn.sh add-client --name <stack-name> [options]
```

**Options:**
- `--region <region>` - AWS region (default: us-east-1)

**Example:**
```bash
./another_betterthannothing_vpn.sh add-client --name abthn-vpn-20260201-a3f9
```

**Output:**
```
Generating new client configuration...
Client configuration saved to: ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-2.conf

Connection Instructions:
  Endpoint: 54.123.45.67:51820
  Import the config file to your WireGuard client
```

#### `ssm`

Open an interactive SSM session to the VPN server for troubleshooting or manual operations.

```bash
./another_betterthannothing_vpn.sh ssm --name <stack-name> [options]
```

**Options:**
- `--region <region>` - AWS region (default: us-east-1)

**Example:**
```bash
./another_betterthannothing_vpn.sh ssm --name abthn-vpn-20260201-a3f9
```

**Inside the session:**
```bash
# Check WireGuard status
sudo wg show

# View WireGuard logs
sudo journalctl -u wg-quick@wg0

# Check connected peers
sudo wg show wg0 peers

# View server configuration
sudo cat /etc/wireguard/wg0.conf
```

#### `start` / `stop`

Start or stop the EC2 instance (VPN will be unavailable when stopped).

```bash
./another_betterthannothing_vpn.sh start --name <stack-name>
./another_betterthannothing_vpn.sh stop --name <stack-name>
```

**Note:** Stopping and starting the instance will change its public IP address. You'll need to update client configurations with the new endpoint.

## Understanding CIDR Parameters

The system uses **two distinct CIDR parameters** with different purposes. Understanding the difference is crucial for proper configuration.

### 1. VPC CIDR (`--vpc-cidr`)

**Purpose:** Defines the internal private network for the AWS VPC.

**Default:** `10.10.0.0/16`

**Used for:**
- VPC subnet allocation
- EC2 instance private IP assignment
- Internal routing within AWS

**When to customize:**
- Your local network or corporate VPN uses `10.10.0.0/16` (conflict)
- You need a different subnet size
- You're connecting multiple VPCs and need non-overlapping ranges

**Valid values:**
- Must be RFC 1918 private address space:
  - `10.0.0.0/8` (10.0.0.0 - 10.255.255.255)
  - `172.16.0.0/12` (172.16.0.0 - 172.31.255.255)
  - `192.168.0.0/16` (192.168.0.0 - 192.168.255.255)
- Prefix length must be between `/16` and `/28`

**Examples:**
```bash
# Use 172.16.x.x range instead of 10.10.x.x
./another_betterthannothing_vpn.sh create --my-ip --vpc-cidr 172.16.0.0/16

# Smaller VPC for minimal resource usage
./another_betterthannothing_vpn.sh create --my-ip --vpc-cidr 192.168.100.0/24
```

### 2. Allowed Ingress CIDR (`--allowed-cidr` or `--my-ip`)

**Purpose:** Controls WHO can connect to the VPN server (Security Group ingress rule).

**Default:** `0.0.0.0/0` (anyone on the internet - **least secure**)

**Used for:**
- AWS Security Group inbound rule for VPN port (UDP/51820)
- Access control and security hardening

**When to customize:**
- **Always!** The default `0.0.0.0/0` allows anyone to attempt VPN connections
- Use `--my-ip` to restrict to your current public IP (most secure)
- Use `--allowed-cidr` to specify a known IP range (office network, home ISP)

**Valid values:**
- Any valid CIDR notation (IPv4 or IPv6)
- Can be specified multiple times for multiple allowed ranges
- Use `/32` for single IP addresses (e.g., `203.0.113.42/32`)

**Examples:**
```bash
# Auto-detect your public IP (recommended)
./another_betterthannothing_vpn.sh create --my-ip

# Manually specify your IP
./another_betterthannothing_vpn.sh create --allowed-cidr 203.0.113.42/32

# Allow your home and office networks
./another_betterthannothing_vpn.sh create \
  --allowed-cidr 203.0.113.0/24 \
  --allowed-cidr 198.51.100.0/24

# Allow anyone (not recommended - displays security warning)
./another_betterthannothing_vpn.sh create --allowed-cidr 0.0.0.0/0
```

### Visual Comparison

```
┌─────────────────────────────────────────────────────────────┐
│  VPC CIDR (--vpc-cidr)                                      │
│  "What is the internal network range?"                      │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  VPC: 10.10.0.0/16                                    │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │  Subnet: 10.10.1.0/24                           │  │  │
│  │  │  ┌───────────────────────────────────────────┐  │  │  │
│  │  │  │  EC2 Instance: 10.10.1.42                 │  │  │  │
│  │  │  └───────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Allowed Ingress CIDR (--allowed-cidr / --my-ip)            │
│  "Who can connect to the VPN?"                              │
│                                                             │
│  Internet                                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Your IP: 203.0.113.42/32  ✅ ALLOWED               │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Other IP: 198.51.100.99   ❌ BLOCKED               │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Security Group Rule:                                       │
│  Allow UDP/51820 from 203.0.113.42/32                       │
└─────────────────────────────────────────────────────────────┘
```

### Common Mistakes

❌ **Using public IP range for VPC CIDR:**
```bash
# WRONG - 8.8.8.0/24 is a public IP range
./another_betterthannothing_vpn.sh create --vpc-cidr 8.8.8.0/24
# Error: VPC CIDR must be a private address range (RFC 1918)
```

❌ **Confusing the two parameters:**
```bash
# WRONG - Using VPC CIDR for access control
./another_betterthannothing_vpn.sh create --allowed-cidr 10.10.0.0/16
# This allows anyone in 10.10.0.0/16 to connect, but that's your VPC's internal range!
```

✅ **Correct usage:**
```bash
# RIGHT - Separate concerns
./another_betterthannothing_vpn.sh create \
  --my-ip \                    # Access control: only my IP
  --vpc-cidr 172.16.0.0/16     # Internal network: custom range
```

## Elastic IP (EIP) Support

### What is an Elastic IP?

An Elastic IP (EIP) is a static, public IPv4 address that persists even when you stop and start your EC2 instance. Without an EIP, your VPN server gets a new public IP address every time the instance is stopped and restarted, requiring you to regenerate all client configurations.

### When to Use EIP

**Use EIP when:**
- ✅ You plan to stop/start the instance frequently to save costs
- ✅ You need a persistent VPN endpoint that doesn't change
- ✅ You want to avoid regenerating client configurations after instance restarts
- ✅ You're using the VPN for longer-term projects (weeks/months)

**Skip EIP when:**
- ❌ You're creating a truly ephemeral VPN (create → use → delete in one session)
- ❌ You want to minimize costs (EIP costs ~$3.60/month when instance is stopped)
- ❌ You don't mind regenerating client configs if the IP changes

### Cost Considerations

**EIP Pricing (as of 2026):**
- **While instance is running:** Free (no additional charge)
- **While instance is stopped:** ~$0.005/hour = ~$3.60/month
- **If not associated with an instance:** ~$0.005/hour = ~$3.60/month

**Example cost scenarios:**

| Scenario | Without EIP | With EIP |
|----------|-------------|----------|
| Always running (730h/month) | $3.02/month | $3.02/month (no extra cost) |
| Run 8h/day, stop 16h/day | $1.01/month | $2.81/month ($1.80 EIP charge) |
| Run 1 day/week, stopped rest | $0.43/month | $3.17/month ($2.74 EIP charge) |

**Key insight:** EIP is cost-effective if your instance runs most of the time. If you stop the instance frequently, EIP adds significant cost.

### How to Use EIP

To allocate an Elastic IP for your VPN server, use the `--eip` flag when creating the stack:

```bash
# Create VPN with Elastic IP
./another_betterthannothing_vpn.sh create --my-ip --eip

# With other options
./another_betterthannothing_vpn.sh create --my-ip --eip --mode full --region eu-west-1
```

The Elastic IP will be automatically allocated and associated with your VPN instance. The IP address will persist even if you stop and start the instance.

### What Happens Without EIP

When you stop and start an EC2 instance without an EIP:

1. **Instance stops:** VPN becomes unavailable
2. **Instance starts:** AWS assigns a new random public IP
3. **Client configs break:** All existing client configurations point to the old IP
4. **Manual fix required:** You must:
   - Get the new IP: `./another_betterthannothing_vpn.sh status --name <stack-name>`
   - Regenerate all client configs: `./another_betterthannothing_vpn.sh add-client --name <stack-name>`
   - Redistribute new configs to all devices

### Best Practices

1. **For ephemeral VPNs (hours/days):** Skip EIP, delete the stack when done
2. **For persistent VPNs (weeks/months):** Use EIP to avoid IP changes
3. **For cost optimization:** If using EIP, keep the instance running or delete the stack entirely (don't leave it stopped)
4. **For testing:** Start without EIP, add it later if needed (requires stack recreation)

## Security Best Practices

### 1. Always Restrict Ingress CIDR

**❌ Never use the default `0.0.0.0/0` in production:**
```bash
# BAD - Anyone can attempt to connect
./another_betterthannothing_vpn.sh create
```

**✅ Always use `--my-ip` or specific `--allowed-cidr`:**
```bash
# GOOD - Only your IP can connect
./another_betterthannothing_vpn.sh create --my-ip

# GOOD - Only your office network can connect
./another_betterthannothing_vpn.sh create --allowed-cidr 203.0.113.0/24
```

**Why it matters:** While WireGuard requires cryptographic authentication, limiting ingress CIDR reduces attack surface and prevents port scanning, DoS attempts, and brute-force attacks.

### 2. Use Spot Instances for Temporary Workloads

If you're using the VPN for short-term tasks, use `--spot` to save ~70% on compute costs:

```bash
./another_betterthannothing_vpn.sh create --my-ip --spot
```

**Trade-off:** Spot instances can be interrupted with 2-minute notice. Not suitable for long-running connections.

### 3. Rotate VPN Infrastructure Regularly

For temporary use cases, destroy and recreate the VPN periodically:

```bash
# Delete old stack
./another_betterthannothing_vpn.sh delete --name abthn-vpn-20260201-a3f9 --yes

# Create new stack with fresh keys
./another_betterthannothing_vpn.sh create --my-ip
```

**Benefits:**
- Fresh cryptographic keys
- New IP address
- Clean instance (no accumulated logs or state)
- Reduced cost (only pay for what you use)

### 4. Secure Client Configuration Files

Client configuration files contain private keys. Protect them:

```bash
# Verify permissions (should be 600)
ls -la ./another_betterthannothing_vpn_config/*/clients/*.conf

# If needed, fix permissions
chmod 600 ./another_betterthannothing_vpn_config/*/clients/*.conf

# Delete configs when no longer needed
rm -rf ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/
```

### 5. Use Split-Tunnel Mode When Possible

Split-tunnel mode (`--mode split`) only routes VPC traffic through the VPN, leaving internet traffic on your local connection:

**Advantages:**
- Better performance (internet traffic doesn't go through VPN)
- Lower data transfer costs (only VPC traffic uses AWS bandwidth)
- Reduced latency for general browsing
- Less load on the VPN server

**Use full-tunnel only when:**
- You need to hide your public IP address
- You're on an untrusted network (public WiFi)
- You need to bypass IP-based restrictions

### 6. Monitor Costs with Tags

All resources are tagged with `CostCenter=<stack-name>`. Use AWS Cost Explorer to track spending:

1. Go to AWS Cost Explorer
2. Filter by tag: `CostCenter = abthn-vpn-20260201-a3f9`
3. View costs by service (EC2, data transfer, etc.)

### 7. Enable VPC Flow Logs (Optional)

For audit trails, enable VPC Flow Logs:

```bash
# After creating the stack, enable flow logs via AWS Console or CLI
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids <vpc-id> \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/another-betterthannothing-vpn
```

**Note:** Flow Logs incur additional costs (~$0.50 per GB ingested).

### 8. IMDSv2 is Enforced

The CloudFormation template enforces IMDSv2 (Instance Metadata Service version 2) to prevent SSRF attacks:

- `HttpTokens: required` - Requires session tokens
- `HttpPutResponseHopLimit: 1` - Prevents forwarding from containers

This is configured automatically; no action needed.

### 9. No SSH Access

The Security Group does NOT allow SSH (port 22). All access is via SSM:

```bash
# Use SSM for interactive access
./another_betterthannothing_vpn.sh ssm --name <stack-name>
```

**Benefits:**
- No SSH key management
- No exposed SSH port
- IAM-based authentication
- Session logging via CloudTrail

### 10. Review CloudFormation Template

Before deploying, review the `template.yaml` to understand what resources are created:

```bash
# View the template
cat template.yaml

# Validate the template
aws cloudformation validate-template --template-body file://template.yaml
```

## Cost Considerations

### Pricing Estimates (us-east-1, as of 2026)

**On-Demand Instance (t4g.nano):**
- Compute: ~$0.0042/hour = ~$3.02/month (if running 24/7)
- Data transfer OUT: $0.09/GB (first 100 GB/month free)
- Data transfer IN: Free

**Spot Instance (t4g.nano):**
- Compute: ~$0.0013/hour = ~$0.94/month (if running 24/7)
- Savings: ~70% compared to on-demand
- Risk: Can be interrupted with 2-minute notice

**Other Costs:**
- CloudFormation: Free
- VPC: Free (no NAT Gateway or VPC endpoints)
- Security Groups: Free
- SSM: Free (no additional charges for Session Manager)
- EBS: ~$0.08/GB-month (8 GB root volume = ~$0.64/month)

**Total Monthly Cost (24/7 operation):**
- On-demand: ~$3.66/month
- Spot: ~$1.58/month

**Typical Usage Patterns:**

| Usage Pattern | Hours/Month | On-Demand Cost | Spot Cost |
|---------------|-------------|----------------|-----------|
| Always-on | 730 | $3.66 | $1.58 |
| Business hours (8h/day, 5 days/week) | 160 | $0.80 | $0.35 |
| Ad-hoc (10h/month) | 10 | $0.05 | $0.02 |

**Data Transfer Costs:**

Assuming 10 GB/month of VPN traffic:
- First 100 GB: Free
- Additional: $0.09/GB

**Cost Optimization Tips:**

1. **Stop when not in use:**
   ```bash
   ./another_betterthannothing_vpn.sh stop --name <stack-name>
   ```
   Stopped instances only incur EBS storage costs (~$0.64/month).

2. **Use Spot instances:**
   ```bash
   ./another_betterthannothing_vpn.sh create --my-ip --spot
   ```
   Save ~70% on compute costs.

3. **Delete when done:**
   ```bash
   ./another_betterthannothing_vpn.sh delete --name <stack-name> --yes
   ```
   Zero cost when stack is deleted.

4. **Use split-tunnel mode:**
   Only VPC traffic uses AWS data transfer. Internet traffic stays local (free).

5. **Choose smaller instance types:**
   For light usage, t4g.nano is sufficient. For heavier loads, consider t4g.micro (~$6/month).

### Cost Tracking with Tags

All resources are tagged with `CostCenter=<stack-name>`. Use this to track costs:

**AWS Cost Explorer:**
1. Navigate to AWS Cost Explorer
2. Click "Cost & Usage Reports"
3. Add filter: Tag → `CostCenter` → `<your-stack-name>`
4. View breakdown by service

**AWS CLI:**
```bash
# Get cost for a specific stack (last 30 days)
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-02-01 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter file://filter.json

# filter.json:
{
  "Tags": {
    "Key": "CostCenter",
    "Values": ["abthn-vpn-20260201-a3f9"]
  }
}
```

### Budget Alerts

Set up a budget alert to avoid surprises:

```bash
aws budgets create-budget \
  --account-id <your-account-id> \
  --budget file://budget.json

# budget.json:
{
  "BudgetName": "VPN-Monthly-Budget",
  "BudgetLimit": {
    "Amount": "10",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostFilters": {
    "TagKeyValue": ["user:CostCenter$abthn-vpn-*"]
  }
}
```

## Examples

### Example 1: Quick VPN for Accessing Private RDS Database

You have an RDS database in a private subnet and need to connect from your laptop:

```bash
# Create split-tunnel VPN (only VPC traffic)
./another_betterthannothing_vpn.sh create --my-ip --mode split --region us-east-1

# Import config to WireGuard and connect
sudo wg-quick up client-1

# Connect to RDS (private IP)
psql -h 10.10.1.123 -U admin -d mydb

# When done, disconnect
sudo wg-quick down client-1

# Delete the stack
./another_betterthannothing_vpn.sh delete --name abthn-vpn-20260201-a3f9 --yes
```

**Cost:** ~$0.05 for 1 hour of usage.

### Example 2: Temporary Build Environment

You need a clean Linux environment to build a project:

```bash
# Create VPN with Spot instance
./another_betterthannothing_vpn.sh create --my-ip --spot

# Open SSM session
./another_betterthannothing_vpn.sh ssm --name abthn-vpn-20260201-a3f9

# Inside the instance
sudo dnf install -y gcc make git docker
git clone https://github.com/myproject/repo.git
cd repo
make build

# Copy artifacts to S3
aws s3 cp ./build/output s3://my-bucket/artifacts/

# Exit and delete
exit
./another_betterthannothing_vpn.sh delete --name abthn-vpn-20260201-a3f9 --yes
```

### Example 3: Multi-Device VPN Access

You need VPN access from laptop, phone, and tablet:

```bash
# Create VPN with 3 initial clients
./another_betterthannothing_vpn.sh create --my-ip --clients 3

# Configs are generated:
# ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-1.conf (laptop)
# ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-2.conf (phone)
# ./another_betterthannothing_vpn_config/abthn-vpn-20260201-a3f9/clients/client-3.conf (tablet)

# Transfer configs to devices (AirDrop, email, etc.)
# Import each config to the respective device's WireGuard app

# Later, add a 4th device
./another_betterthannothing_vpn.sh add-client --name abthn-vpn-20260201-a3f9
```

### Example 4: Full-Tunnel VPN for Public WiFi

You're at a coffee shop and want to encrypt all traffic:

```bash
# Create full-tunnel VPN
./another_betterthannothing_vpn.sh create --my-ip --mode full

# Import config and connect
sudo wg-quick up client-1

# All traffic now routes through AWS
curl ifconfig.me
# Shows AWS EC2 public IP

# When done
sudo wg-quick down client-1
```

### Example 5: Multi-Region Deployment

You need VPN access in multiple regions:

```bash
# Create VPN in us-east-1
./another_betterthannothing_vpn.sh create --my-ip --region us-east-1 --name vpn-us-east

# Create VPN in eu-west-1
./another_betterthannothing_vpn.sh create --my-ip --region eu-west-1 --name vpn-eu-west

# Create VPN in ap-southeast-1
./another_betterthannothing_vpn.sh create --my-ip --region ap-southeast-1 --name vpn-ap-se

# List all VPNs
./another_betterthannothing_vpn.sh list --region us-east-1
./another_betterthannothing_vpn.sh list --region eu-west-1
./another_betterthannothing_vpn.sh list --region ap-southeast-1

# Connect to the closest region for best latency
```

### Example 6: Custom VPC CIDR to Avoid Conflicts

Your corporate VPN uses `10.0.0.0/8`, so you need a different range:

```bash
# Use 172.16.x.x range instead
./another_betterthannothing_vpn.sh create \
  --my-ip \
  --vpc-cidr 172.16.0.0/16 \
  --mode split

# Client config will have AllowedIPs = 172.16.0.0/16
# No conflict with corporate VPN (10.0.0.0/8)
```

### Example 7: Allowing Multiple Source IPs

You want to allow connections from both home and office:

```bash
./another_betterthannothing_vpn.sh create \
  --allowed-cidr 203.0.113.0/24 \
  --allowed-cidr 198.51.100.0/24 \
  --mode split
```

### Example 8: Running Docker Workloads

Use the VPN server as a temporary Docker host:

```bash
# Create VPN
./another_betterthannothing_vpn.sh create --my-ip

# Open SSM session
./another_betterthannothing_vpn.sh ssm --name abthn-vpn-20260201-a3f9

# Install Docker
sudo dnf install -y docker
sudo systemctl start docker

# Run a PostgreSQL database
sudo docker run -d \
  --name postgres \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=testpass \
  postgres:15

# From your laptop (connected via VPN)
psql -h 10.10.1.x -U postgres
# Enter password: testpass

# When done, delete everything
exit
./another_betterthannothing_vpn.sh delete --name abthn-vpn-20260201-a3f9 --yes
```

## Execution Logs

The script automatically saves execution logs to track stack information across different script runs. This is useful for:
- Recovering stack information after a session ends
- Tracking the status of created stacks
- Finding the correct output directory when deleting stacks

### Log Location

Execution logs are saved in the output directory (default: `./another_betterthannothing_vpn_config/`) as `execution_log.json`.

### Log Contents

The log file contains an array of entries, one per stack:

```json
[
  {
    "stack_name": "abthn-vpn-20260204-x1y2",
    "region": "eu-west-1",
    "status": "READY",
    "last_updated": "2026-02-04T10:30:00Z",
    "output_dir": "/home/user/vpn",
    "additional_info": "VPN setup complete, 2 client(s) configured"
  }
]
```

### Status Values

- `CREATING` - Stack creation initiated
- `CREATE_COMPLETE` - CloudFormation stack created successfully
- `CREATE_FAILED` - Stack creation failed
- `READY` - VPN fully configured and ready to use
- `DELETED` - Stack has been deleted

### Using Logs for Recovery

If you need to find information about a previously created stack:

```bash
# View all logged stacks
cat ./another_betterthannothing_vpn_config/execution_log.json | jq '.'

# Find a specific stack
cat ./another_betterthannothing_vpn_config/execution_log.json | jq '.[] | select(.stack_name == "abthn-vpn-20260204-x1y2")'

# List all stacks with their status
cat ./another_betterthannothing_vpn_config/execution_log.json | jq '.[] | {name: .stack_name, status: .status, region: .region}'
```

## Troubleshooting

### SSM Agent Issues

**Problem:** Script times out waiting for SSM agent to be ready.

**Symptoms:**
```
Waiting for SSM agent to be ready...
Timeout: SSM agent did not become ready after 5 minutes
```

**Solutions:**

1. **Check instance system logs:**
   ```bash
   aws ec2 get-console-output --instance-id <instance-id>
   ```
   Look for errors during boot or SSM agent startup.

2. **Verify IAM role attachment:**
   ```bash
   aws ec2 describe-instances --instance-ids <instance-id> \
     --query 'Reservations[0].Instances[0].IamInstanceProfile'
   ```
   Should show the instance profile ARN.

3. **Check SSM agent status manually:**
   ```bash
   # Wait a few more minutes, then try
   aws ssm describe-instance-information \
     --filters "Key=InstanceIds,Values=<instance-id>"
   ```

4. **Verify internet connectivity:**
   - Instance needs internet access to reach SSM endpoints
   - Check route table has default route to Internet Gateway
   - Check Security Group allows outbound HTTPS (443)

5. **Restart SSM agent (if you can access via EC2 Serial Console):**
   ```bash
   sudo systemctl restart amazon-ssm-agent
   ```

**Prevention:**
- Use default VPC CIDR and Security Group settings
- Ensure CloudFormation template hasn't been modified
- Check AWS service health dashboard for SSM outages

### WireGuard Connection Problems

**Problem:** VPN connection fails or times out.

**Symptoms:**
- WireGuard shows "Handshake failed" or "No recent handshake"
- No traffic flows through the tunnel

**Solutions:**

1. **Verify endpoint is correct:**
   ```bash
   # Check current public IP
   ./another_betterthannothing_vpn.sh status --name <stack-name>
   
   # Compare with client config
   grep Endpoint ./another_betterthannothing_vpn_config/<stack-name>/clients/client-1.conf
   ```
   
   If IPs don't match (instance was stopped/started), regenerate client config:
   ```bash
   ./another_betterthannothing_vpn.sh add-client --name <stack-name>
   ```

2. **Check Security Group allows your IP:**
   ```bash
   aws ec2 describe-security-groups \
     --filters "Name=tag:CostCenter,Values=<stack-name>" \
     --query 'SecurityGroups[0].IpPermissions'
   ```
   
   If your IP changed, recreate the stack with `--my-ip` or update the Security Group manually.

3. **Verify WireGuard service is running:**
   ```bash
   ./another_betterthannothing_vpn.sh ssm --name <stack-name>
   sudo systemctl status wg-quick@wg0
   sudo wg show
   ```

4. **Check for port conflicts:**
   ```bash
   # On your local machine
   sudo wg show
   # Ensure no other WireGuard interfaces are using the same keys
   ```

5. **Test connectivity to VPN port:**
   ```bash
   # From your machine
   nc -zvu <server-public-ip> 51820
   ```
   
   If this fails, check:
   - Your firewall allows outbound UDP/51820
   - Your ISP doesn't block VPN protocols
   - Security Group allows your current IP

6. **Regenerate keys:**
   ```bash
   # Delete and recreate the stack
   ./another_betterthannothing_vpn.sh delete --name <stack-name> --yes
   ./another_betterthannothing_vpn.sh create --my-ip
   ```

### CloudFormation Stack Failures

**Problem:** Stack creation fails.

**Symptoms:**
```
Stack creation failed: CREATE_FAILED
Resource: VpnInstance
Reason: You have exceeded your maximum instance limit
```

**Solutions:**

1. **Check stack events:**
   ```bash
   aws cloudformation describe-stack-events \
     --stack-name <stack-name> \
     --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
   ```

2. **Common failures and fixes:**

   **Insufficient EC2 capacity:**
   ```
   Reason: We currently do not have sufficient t4g.nano capacity
   ```
   Solution: Use a different instance type or region:
   ```bash
   ./another_betterthannothing_vpn.sh create --my-ip --instance-type t4g.micro
   # or
   ./another_betterthannothing_vpn.sh create --my-ip --region us-west-2
   ```

   **Instance limit exceeded:**
   ```
   Reason: You have exceeded your maximum instance limit
   ```
   Solution: Request limit increase via AWS Service Quotas or delete unused instances.

   **Invalid CIDR:**
   ```
   Reason: The CIDR '8.8.8.0/24' is invalid
   ```
   Solution: Use a valid RFC 1918 private CIDR:
   ```bash
   ./another_betterthannothing_vpn.sh create --my-ip --vpc-cidr 10.10.0.0/16
   ```

3. **Clean up failed stack:**
   ```bash
   aws cloudformation delete-stack --stack-name <stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <stack-name>
   ```

### IP Detection Failures

**Problem:** `--my-ip` flag fails to detect public IP.

**Symptoms:**
```
Error: Unable to detect public IP. Please use --allowed-cidr <your-ip>/32 instead.
```

**Solutions:**

1. **Check internet connectivity:**
   ```bash
   curl -s https://api.ipify.org
   # Should return your public IP
   ```

2. **Use manual IP specification:**
   ```bash
   # Find your IP manually
   curl ifconfig.me
   
   # Use it in the command
   ./another_betterthannothing_vpn.sh create --allowed-cidr $(curl -s ifconfig.me)/32
   ```

3. **Check if behind corporate proxy:**
   If you're behind a corporate proxy, the detected IP might be the proxy's IP. Verify with your network admin.

### Client Configuration Import Issues

**Problem:** WireGuard client rejects configuration file.

**Symptoms:**
- "Invalid configuration file"
- "Unable to parse configuration"

**Solutions:**

1. **Verify file integrity:**
   ```bash
   cat ./another_betterthannothing_vpn_config/<stack-name>/clients/client-1.conf
   ```
   
   Should contain `[Interface]` and `[Peer]` sections with all required fields.

2. **Check file permissions:**
   ```bash
   ls -la ./another_betterthannothing_vpn_config/<stack-name>/clients/client-1.conf
   # Should be -rw------- (600)
   
   chmod 600 ./another_betterthannothing_vpn_config/<stack-name>/clients/client-1.conf
   ```

3. **Regenerate configuration:**
   ```bash
   ./another_betterthannothing_vpn.sh add-client --name <stack-name>
   ```

### Performance Issues

**Problem:** Slow VPN speeds or high latency.

**Solutions:**

1. **Use split-tunnel mode:**
   Only route VPC traffic through VPN:
   ```bash
   ./another_betterthannothing_vpn.sh create --my-ip --mode split
   ```

2. **Choose closer region:**
   Deploy VPN in a region geographically closer to you:
   ```bash
   ./another_betterthannothing_vpn.sh create --my-ip --region eu-west-1
   ```

3. **Upgrade instance type:**
   ```bash
   # Stop current instance
   ./another_betterthannothing_vpn.sh stop --name <stack-name>
   
   # Modify instance type via AWS Console or CLI
   aws ec2 modify-instance-attribute \
     --instance-id <instance-id> \
     --instance-type t4g.small
   
   # Start instance
   ./another_betterthannothing_vpn.sh start --name <stack-name>
   ```

4. **Check for network congestion:**
   ```bash
   # Test latency
   ping <server-public-ip>
   
   # Test bandwidth
   iperf3 -c <server-private-ip>  # Requires iperf3 on server
   ```

### Spot Instance Interruptions

**Problem:** Spot instance was terminated unexpectedly.

**Symptoms:**
- VPN connection drops
- Instance state shows "terminated"

**Solutions:**

1. **Check interruption notice:**
   ```bash
   aws ec2 describe-spot-instance-requests \
     --filters "Name=instance-id,Values=<instance-id>"
   ```

2. **Recreate with on-demand:**
   ```bash
   ./another_betterthannothing_vpn.sh delete --name <stack-name> --yes
   ./another_betterthannothing_vpn.sh create --my-ip  # Without --spot
   ```

3. **Use Spot for non-critical workloads only:**
   Spot instances are best for temporary, interruptible workloads.

### Getting Help

If you're still stuck:

1. **Check AWS CloudTrail logs** for API errors
2. **Review CloudFormation stack events** for detailed error messages


## Cleanup

### Deleting a VPN Stack

To remove all AWS resources and stop incurring costs:

```bash
# Interactive (prompts for confirmation)
./another_betterthannothing_vpn.sh delete --name <stack-name>

# Non-interactive (skips confirmation)
./another_betterthannothing_vpn.sh delete --name <stack-name> --yes
```

**What gets deleted:**
- ✅ CloudFormation stack
- ✅ EC2 instance
- ✅ VPC and all networking resources (subnet, route table, Internet Gateway)
- ✅ Security Group
- ✅ IAM Role and Instance Profile
- ✅ EBS volumes

**What does NOT get deleted:**
- ❌ Local client configuration files in `./another_betterthannothing_vpn_config/`
- ❌ CloudWatch Logs (if you enabled VPC Flow Logs)
- ❌ Any data you stored on the instance

### Deleting Local Configuration Files

Client configuration files are stored locally and contain private keys. Delete them when no longer needed:

```bash
# Delete configs for a specific stack
rm -rf ./another_betterthannothing_vpn_config/<stack-name>/

# Delete all VPN configs
rm -rf ./another_betterthannothing_vpn_config/
```

### Verifying Deletion

Confirm all resources are deleted:

```bash
# Check stack status
aws cloudformation describe-stacks --stack-name <stack-name>
# Should return: "Stack with id <stack-name> does not exist"

# List all VPN stacks
./another_betterthannothing_vpn.sh list --region <region>
# Should not show the deleted stack

# Check for orphaned resources (rare, but possible)
aws ec2 describe-instances \
  --filters "Name=tag:CostCenter,Values=<stack-name>" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]'
# Should return empty
```

### Cleaning Up Multiple Stacks

If you have multiple VPN stacks across regions:

```bash
# List all stacks in all regions
for region in us-east-1 us-west-2 eu-west-1; do
  echo "Region: $region"
  ./another_betterthannothing_vpn.sh list --region $region
done

# Delete all stacks (be careful!)
for region in us-east-1 us-west-2 eu-west-1; do
  for stack in $(aws cloudformation list-stacks \
    --region $region \
    --query 'StackSummaries[?starts_with(StackName, `abthn-vpn-`) && StackStatus!=`DELETE_COMPLETE`].StackName' \
    --output text); do
    echo "Deleting $stack in $region"
    ./another_betterthannothing_vpn.sh delete --name $stack --region $region --yes
  done
done
```

### Cost After Deletion

Once the stack is deleted, you should see:
- **EC2 charges:** Stop immediately
- **EBS charges:** Stop immediately
- **Data transfer charges:** Only for data transferred before deletion
- **CloudFormation:** No charges (always free)

**Verify zero cost:**
1. Wait 24-48 hours for billing to update
2. Check AWS Cost Explorer filtered by `CostCenter=<stack-name>`
3. Should show no new charges after deletion timestamp

### Troubleshooting Deletion Failures

**Problem:** Stack deletion fails or hangs.

**Symptoms:**
```
Stack deletion failed: DELETE_FAILED
Resource: VpnInstance
Reason: resource sg-xxxxx has a dependent object
```

**Solutions:**

1. **Check stack events:**
   ```bash
   aws cloudformation describe-stack-events \
     --stack-name <stack-name> \
     --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`]'
   ```

2. **Common deletion failures:**

   **ENI still attached:**
   ```bash
   # Find and delete ENI manually
   aws ec2 describe-network-interfaces \
     --filters "Name=tag:CostCenter,Values=<stack-name>"
   
   aws ec2 delete-network-interface --network-interface-id <eni-id>
   ```

   **Security Group has dependencies:**
   ```bash
   # Find dependent resources
   aws ec2 describe-security-groups \
     --group-ids <sg-id> \
     --query 'SecurityGroups[0].IpPermissions'
   
   # Delete dependent resources first, then retry stack deletion
   ```

3. **Force deletion (last resort):**
   ```bash
   # Manually delete resources via AWS Console
   # Then delete the stack
   aws cloudformation delete-stack --stack-name <stack-name>
   ```

### Best Practices for Cleanup

1. **Delete stacks when not in use:** Don't leave VPN infrastructure running idle
2. **Set calendar reminders:** If you create a VPN for a specific task, set a reminder to delete it
3. **Use AWS Budgets:** Set up alerts to notify you of unexpected costs
4. **Regular audits:** Periodically run `list` command to check for forgotten stacks
5. **Tag everything:** The `CostCenter` tag makes it easy to track and clean up resources

---

## License

This project is provided as-is for educational and personal use, under the Creative Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0), and is used at your own risk.

See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please open an issue or pull request on the project repository.

## Acknowledgments

- **WireGuard:** Modern, fast, and secure VPN protocol
- **AWS Systems Manager:** Secure instance access without SSH
- **AWS CloudFormation:** Infrastructure as Code for reproducible deployments

---

**Remember:** This is a "better than nothing" VPN for temporary use cases. For production workloads or sensitive data, use enterprise VPN solutions with proper redundancy, monitoring, and compliance certifications.
