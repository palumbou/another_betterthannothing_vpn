# Implementation Plan: another_betterthannothing_vpn

## Overview

This implementation plan breaks down the "another_betterthannothing_vpn" project into discrete, incremental tasks. The approach follows this sequence:

1. Create CloudFormation template with all infrastructure resources
2. Implement core orchestration script structure and utilities
3. Implement stack lifecycle commands (create, delete, status, list)
4. Implement VPN bootstrap and client management
5. Add documentation and final integration

Each task builds on previous work, with checkpoints to validate functionality before proceeding.

## Tasks

- [x] 1. Create CloudFormation template with VPC and networking
  - Create `template.yaml` with Parameters section (VpcCidr, InstanceType, VpnPort, VpnProtocol, AllowedIngressCidr)
  - Define VPC resource with CIDR parameter reference
  - Define public subnet in first availability zone
  - Define Internet Gateway and VPC attachment
  - Define route table with default route to IGW
  - Define subnet route table association
  - Add costcenter tags to all resources using `!Ref AWS::StackName`
  - _Requirements: 1.1, 1.2, 2.1_

- [x] 2. Add Security Group and IAM resources to CloudFormation template
  - Define Security Group with single ingress rule for VPN port/protocol from AllowedIngressCidr
  - Define egress rule allowing all outbound traffic (required for SSM and package installation)
  - Verify no SSH (port 22) ingress rule exists
  - Define IAM Role with AmazonSSMManagedInstanceCore managed policy ARN
  - Define IAM Instance Profile referencing the role
  - Add costcenter tags to Security Group and IAM Role
  - _Requirements: 1.3, 1.4, 3.1, 3.2, 3.7_

- [x] 3. Add EC2 instance to CloudFormation template
  - Define EC2 instance resource with latest Amazon Linux 2023 AMI (use SSM parameter for AMI lookup)
  - Configure instance with IamInstanceProfile, SecurityGroupIds, and SubnetId
  - Add conditional InstanceMarketOptions for Spot instances (when UseSpotInstance=true)
  - Set InstanceMarketOptions: MarketType=spot, SpotOptions with MaxPrice (optional, use on-demand price as max)
  - Set MetadataOptions: HttpTokens=required, HttpPutResponseHopLimit=1 (IMDSv2)
  - Configure BlockDeviceMappings with Encrypted=true for root volume
  - Add minimal UserData script (update SSM agent if needed, set hostname)
  - Set default InstanceType parameter to t4g.nano
  - Add costcenter tag to instance
  - _Requirements: 1.5, 3.4, 3.6, 9.13, 9.14, 9.15_

- [x] 3.1 Add Elastic IP resources to CloudFormation template
  - Add AllocateEIP parameter (String, default: "false")
  - Create Condition "ShouldAllocateEIP" that evaluates AllocateEIP parameter
  - Define AWS::EC2::EIP resource with Condition: ShouldAllocateEIP
  - Set EIP Domain to "vpc"
  - Add costcenter tag to EIP resource
  - Define AWS::EC2::EIPAssociation resource with Condition: ShouldAllocateEIP
  - Associate EIP with VpnInstance using AllocationId and InstanceId
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.7_

- [x] 4. Add CloudFormation outputs
  - Define output for InstanceId
  - Define output for PublicIp (conditional: use EIP if AllocateEIP=true, otherwise instance public IP)
  - Define output for VpcId
  - Define output for VpcCidr
  - Define output for AWS::Region
  - Define output for VpnPort parameter
  - Define output for VpnProtocol parameter
  - Define output for HasElasticIP (boolean indicating if EIP was allocated)
  - _Requirements: 1.7, 10.5_

- [x] 5. Create orchestration script structure and core utilities
  - Create `another_betterthannothing_vpn.sh` with shebang `#!/usr/bin/env bash` and `set -euo pipefail`
  - Define global variables (SCRIPT_DIR, TEMPLATE_FILE, DEFAULT_OUTPUT_DIR, DEFAULT_REGION)
  - Implement `display_help()` function with usage information and all command/option descriptions
  - Implement `parse_args()` function to parse command and options (including --spot and --eip flags)
  - Implement main() function with command routing (create, delete, start, stop, status, list, add-client, ssm)
  - Add help text explaining --allowed-cidr vs --vpc-cidr distinction
  - Add help text explaining --spot option for cost savings
  - Add help text explaining --eip option for persistent IP address
  - _Requirements: 5.7, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.13, 9.16, 13.3, 14.6_

- [x] 6. Implement dependency checking and NixOS support
  - Implement `check_dependencies()` function to verify aws, jq, session-manager-plugin in PATH
  - Implement `nixos_bootstrap()` function to detect /etc/NIXOS and re-exec in nix-shell
  - Add nix-shell command with awscli2, session-manager-plugin, jq packages
  - Call check_dependencies() early in main()
  - Display clear error messages for missing dependencies with installation instructions
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 12.5_

- [x] 7. Implement validation functions
  - Implement `validate_vpc_cidr()` function to validate CIDR format, RFC 1918 ranges, and prefix length (/16-/28)
  - Implement `validate_cidr_format()` helper for general CIDR validation
  - Implement `detect_my_ip()` function with primary method (curl ipify.org) and fallback (dig OpenDNS)
  - Add IPv4 and IPv6 detection with appropriate suffix (/32 or /128)
  - Return validated values or exit with clear error messages and examples
  - _Requirements: 9.9, 9.11, 9.12_

- [x] 8. Implement stack name generation and validation
  - Implement `generate_stack_name()` function to create name in format `another-YYYYMMDD-xxxx`
  - Use date command for date portion and random alphanumeric for suffix
  - Implement `validate_stack_exists()` function using `aws cloudformation describe-stacks`
  - Handle stack not found gracefully (return false, don't error)
  - Implement `get_stack_outputs()` function to retrieve and parse stack outputs
  - _Requirements: 5.5, 8.3, 8.4, 12.1_

- [x] 9. Checkpoint - Validate script structure and utilities
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Implement create command - preparation phase
  - Implement `cmd_create()` function skeleton
  - Parse and store all command-line options (region, name, mode, vpc-cidr, allowed-cidr, my-ip, instance-type, spot, eip, clients, output-dir, yes)
  - Validate mutually exclusive flags (--my-ip and --allowed-cidr)
  - Call validate_vpc_cidr() if --vpc-cidr provided
  - Call detect_my_ip() if --my-ip flag set
  - Generate stack name if not provided
  - Check if stack already exists and fail with clear message if yes
  - Display security warning if AllowedIngressCidr is 0.0.0.0/0
  - Display cost savings note if --spot flag is used
  - Display warning if --eip flag is NOT used: "WARNING: Without an Elastic IP, the public IP address will change if you stop and start the instance. Use --eip to allocate a persistent IP address."
  - _Requirements: 3.5, 5.1, 5.5, 9.10, 9.13, 10.6, 15.4_

- [x] 10. Implement create command - CloudFormation stack creation
  - Prepare CloudFormation parameters array (VpcCidr, InstanceType, VpnPort, VpnProtocol, AllowedIngressCidr, UseSpotInstance, AllocateEIP)
  - Set AllocateEIP parameter to "true" if --eip flag is set, "false" otherwise
  - Build aws cloudformation create-stack command with parameters and tags
  - Add stack-level tag: `--tags Key=costcenter,Value=<stack-name>`
  - Execute create-stack command
  - Display progress message "Creating stack '<name>' in region '<region>'..."
  - Execute `aws cloudformation wait stack-create-complete` with timeout
  - Handle stack creation failures by retrieving and displaying failed events
  - _Requirements: 2.2, 5.1, 5.6, 9.14, 9.15, 9.16, 13.2, 15.1_

- [x] 11. Implement create command - SSM readiness and bootstrap
  - Retrieve stack outputs using get_stack_outputs()
  - Implement `wait_for_ssm_ready()` function to poll `aws ssm describe-instance-information`
  - Poll every 10 seconds for up to 5 minutes
  - Display progress dots or messages while waiting
  - On timeout, display troubleshooting steps
  - Once SSM ready, display "Instance ready, bootstrapping VPN server..."
  - _Requirements: 5.1, 7.4_

- [x] 12. Implement VPN server bootstrap
  - Implement `bootstrap_vpn_server()` function
  - Implement `execute_remote_command()` helper using `aws ssm send-command` or start-session
  - Install wireguard-tools via SSM: `dnf install -y wireguard-tools` (Amazon Linux 2023)
  - Generate server WireGuard keys on server: `wg genkey | tee server_private.key | wg pubkey > server_public.key`
  - Retrieve server public key for later use
  - Create /etc/wireguard/wg0.conf with Interface section (Address=10.99.0.1/24, ListenPort, PrivateKey)
  - Add PostUp/PostDown iptables rules if mode=full (NAT masquerade)
  - Enable IP forwarding: `sysctl -w net.ipv4.ip_forward=1` and persist to /etc/sysctl.d/99-wireguard.conf
  - Start and enable service: `systemctl enable --now wg-quick@wg0`
  - Verify service is running: `systemctl is-active wg-quick@wg0`
  - _Requirements: 4.1, 4.4, 4.5, 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

- [x] 13. Implement client configuration generation
  - Implement `generate_client_config()` function with parameters (stack_name, client_name, client_id, mode, vpc_cidr, endpoint, port)
  - Generate client private/public key pair on server via SSM
  - Add peer to server config: `wg set wg0 peer <client-pubkey> allowed-ips 10.99.0.<client-id>/32`
  - Save server config: `wg-quick save wg0`
  - Retrieve client private key securely
  - Create client config file with [Interface] and [Peer] sections
  - Set AllowedIPs based on mode: "0.0.0.0/0, ::/0" for full, VPC CIDR for split
  - Add PersistentKeepalive=25
  - Create output directory: `mkdir -p <output-dir>/<stack-name>/clients`
  - Write config to `<output-dir>/<stack-name>/clients/<client-name>.conf`
  - Set file permissions: `chmod 600 <config-file>`
  - _Requirements: 4.2, 4.3, 6.1, 6.3, 6.4, 6.5, 6.6_

- [x] 14. Implement create command - client generation and completion
  - After bootstrap, loop to generate N client configs (from --clients parameter, default 1)
  - Name clients as client-1, client-2, etc.
  - Call generate_client_config() for each client
  - Create metadata.json file in output directory with stack info and client list
  - Display connection instructions: endpoint, port, config file locations
  - Display next steps: how to import config to WireGuard client
  - Display command to add more clients: `./another_betterthannothing_vpn.sh add-client --name <stack>`
  - _Requirements: 6.2, 6.5, 14.2, 14.5_

- [x] 15. Checkpoint - Test create command end-to-end
  - Ensure all tests pass, ask the user if questions arise.

- [x] 16. Implement delete command
  - Implement `cmd_delete()` function
  - Parse stack name from arguments
  - Validate stack exists using validate_stack_exists()
  - If --yes flag not set, prompt for confirmation: "Delete stack '<name>'? (y/N)"
  - Execute `aws cloudformation delete-stack --stack-name <name>`
  - Display progress message "Deleting stack '<name>'..."
  - Execute `aws cloudformation wait stack-delete-complete` with timeout
  - Handle deletion failures with clear error messages
  - Display success message with reminder that local client configs remain
  - _Requirements: 5.2, 5.6, 12.2, 14.1_

- [x] 17. Implement start command
  - Implement `cmd_start()` function
  - Parse stack name from arguments
  - Validate stack exists using validate_stack_exists()
  - Retrieve InstanceId from stack outputs
  - Check current instance state using `aws ec2 describe-instances`
  - If already running, display message and exit
  - Execute `aws ec2 start-instances --instance-ids <instance-id>`
  - Wait for instance to be running: `aws ec2 wait instance-running`
  - Display success message with new public IP (may have changed)
  - Display reminder to update client configs if IP changed
  - _Requirements: 5.3, 14.1_

- [x] 18. Implement stop command
  - Implement `cmd_stop()` function
  - Parse stack name from arguments
  - Validate stack exists using validate_stack_exists()
  - Retrieve InstanceId from stack outputs
  - Check current instance state using `aws ec2 describe-instances`
  - If already stopped, display message and exit
  - If --yes flag not set, prompt for confirmation: "Stop instance '<instance-id>'? (y/N)"
  - Execute `aws ec2 stop-instances --instance-ids <instance-id>`
  - Wait for instance to be stopped: `aws ec2 wait instance-stopped`
  - Display success message
  - Display reminder that VPN will be unavailable until started again
  - _Requirements: 5.3, 14.1_

- [x] 19. Implement status command
  - Implement `cmd_status()` function
  - Parse stack name from arguments
  - Retrieve stack information using `aws cloudformation describe-stacks`
  - Display stack status (CREATE_COMPLETE, DELETE_IN_PROGRESS, etc.)
  - Retrieve and display stack outputs (InstanceId, PublicIp, VpcCidr, VpnPort)
  - Query instance status using `aws ec2 describe-instances`
  - Display instance state (running, stopped, etc.)
  - Check SSM agent status using `aws ssm describe-instance-information`
  - Display VPN endpoint: `<PublicIp>:<VpnPort>`
  - Display number of client configs in output directory
  - _Requirements: 5.3, 14.1_

- [x] 20. Implement list command
  - Implement `cmd_list()` function
  - Query all stacks in region using `aws cloudformation list-stacks`
  - Filter stacks with names matching pattern `another-*`
  - Filter out deleted stacks (status DELETE_COMPLETE)
  - Display table with columns: Stack Name, Status, Region, VPN Endpoint
  - Retrieve VPN endpoint from stack outputs
  - Handle case where no stacks found: "No VPN stacks found in region '<region>'"
  - _Requirements: 5.4, 14.1_

- [x] 21. Implement add-client command
  - Implement `cmd_add_client()` function
  - Parse stack name from arguments
  - Validate stack exists and is in CREATE_COMPLETE status
  - Retrieve stack outputs to get endpoint, port, VPC CIDR, mode
  - Load metadata.json to determine next client ID
  - Generate new client name: client-<next-id>
  - Call generate_client_config() with stack parameters
  - Update metadata.json with new client entry
  - Display new client config location and connection instructions
  - _Requirements: 6.1, 12.4, 14.1_

- [x] 22. Implement ssm command
  - Implement `cmd_ssm()` function
  - Parse stack name from arguments
  - Validate stack exists
  - Retrieve InstanceId from stack outputs
  - Verify session-manager-plugin is installed
  - If missing, display installation instructions for common platforms (Linux, macOS, Windows)
  - Execute `aws ssm start-session --target <instance-id> --region <region>`
  - Handle SSM connection failures with troubleshooting steps
  - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [x] 23. Checkpoint - Test all commands
  - Ensure all tests pass, ask the user if questions arise.

- [x] 24. Create README.md (English)
  - Add project title and description
  - Add "Security / Threat Model" section explaining better-than-nothing approach, limitations, and when to use
  - Add "Ephemeral Compute Box" section explaining temporary lab use case with Docker examples
  - Add Prerequisites section (AWS CLI, session-manager-plugin, WireGuard client)
  - Add Quick Start section with create examples (full-tunnel and split-tunnel)
  - Add CLI Reference section with all commands and options
  - Add detailed explanation of --allowed-cidr vs --vpc-cidr
  - Add Security Best Practices section (use --my-ip, avoid 0.0.0.0/0, IMDSv2, etc.)
  - Add Cost Considerations section with pricing estimates and costcenter tagging
  - Add Troubleshooting section (SSM agent issues, WireGuard connection problems, stack failures)
  - Add Examples section with common use cases
  - Add Cleanup section explaining delete command
  - _Requirements: 13.1, 13.3, 13.4, 13.5_

- [x] 25. Create README.it.md (Italian)
  - Translate all content from README.md to Italian
  - Maintain same structure and sections
  - Ensure technical terms are appropriately translated or kept in English where standard
  - _Requirements: 13.2_

- [x] 26. Add error handling and logging improvements
  - Review all functions for proper error handling
  - Ensure all AWS CLI commands check exit codes
  - Add error messages for common failure scenarios
  - Verify no private keys are logged to stdout (except in client config files)
  - Add progress indicators for long-running operations
  - Ensure all error messages include actionable next steps
  - _Requirements: 12.2, 12.3, 14.1, 14.3_

- [x] 27. Final integration and testing
  - Test create command with various parameter combinations
  - Test create with --my-ip flag
  - Test create with custom --vpc-cidr
  - Test create with --allowed-cidr
  - Test full-tunnel and split-tunnel modes
  - Test start and stop commands
  - Test add-client command
  - Test delete command
  - Test status and list commands
  - Test ssm command
  - Test NixOS bootstrap (if on NixOS)
  - Verify all CloudFormation resources are properly tagged
  - Verify stack deletion removes all resources
  - Test error cases (invalid CIDR, stack already exists, missing credentials)
  - _Requirements: All_

- [x] 28. Final checkpoint - Complete system validation
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- The CloudFormation template and Bash script are the two main deliverables
- All code should include comments explaining key logic
- Error messages should be clear and actionable
- Security is paramount: no SSH exposure, minimal IAM permissions, IMDSv2 enforced
- Cost tracking via costcenter tags is critical for all resources
- The script should be idempotent where possible (e.g., don't recreate existing stacks)
- NixOS support ensures the tool works in declarative environments
- Documentation should emphasize the security model and limitations
