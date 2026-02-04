# Requirements Document

## Introduction

This document specifies the requirements for "another_betterthannothing_vpn", a disposable VPN infrastructure on AWS. The system creates a dedicated VPC with an EC2 instance running a VPN service (WireGuard by default), manageable entirely through CloudFormation and a Bash orchestration script. The infrastructure supports both full-tunnel (all traffic through VPN) and split-tunnel (only VPC traffic through VPN) modes, with secure access via AWS Systems Manager (SSM) only—no public SSH exposure.

## Glossary

- **Stack**: AWS CloudFormation stack containing all infrastructure resources
- **VPN_Server**: EC2 instance running the VPN service (WireGuard)
- **Orchestration_Script**: Bash script (`another.sh`) that manages stack lifecycle
- **SSM**: AWS Systems Manager, used for secure instance access
- **Full_Tunnel**: VPN mode routing all client traffic through the VPN
- **Split_Tunnel**: VPN mode routing only VPC-destined traffic through the VPN
- **Client_Config**: WireGuard configuration file for client devices
- **Stack_Name**: Unique identifier for the infrastructure instance
- **Cost_Center_Tag**: AWS tag `costcenter=<Stack_Name>` applied to all resources

## Requirements

### Requirement 1: CloudFormation Infrastructure Management

**User Story:** As a cloud engineer, I want all infrastructure defined in CloudFormation, so that I can create and destroy the entire stack with a single operation.

#### Acceptance Criteria

1. THE CloudFormation_Template SHALL define a complete VPC with dedicated CIDR (parametric, default 10.10.0.0/16)
2. THE CloudFormation_Template SHALL define at least one subnet with Internet Gateway and route table
3. THE CloudFormation_Template SHALL define a Security Group allowing inbound traffic ONLY on the VPN port (parametric protocol and port, default UDP/51820)
4. THE CloudFormation_Template SHALL define an IAM Role with AmazonSSMManagedInstanceCore policy for the VPN_Server
5. THE CloudFormation_Template SHALL define an EC2 instance with SSM enabled, IMDSv2 enforced, and EBS encryption enabled
6. WHEN a user deletes the stack, THEN THE System SHALL remove all created resources without manual intervention
7. THE CloudFormation_Template SHALL output InstanceId, PublicIp, VpcId, VpcCidr, Region, VpnPort, and VpnProtocol

### Requirement 2: Cost Tracking and Tagging

**User Story:** As a finance manager, I want all resources tagged with cost center information, so that I can track and allocate costs accurately.

#### Acceptance Criteria

1. THE CloudFormation_Template SHALL apply the tag `costcenter=<Stack_Name>` to all resources that support tagging
2. THE CloudFormation_Stack SHALL have the tag `costcenter=<Stack_Name>` applied at stack level
3. WHEN creating resources, THE System SHALL ensure the Stack_Name is used as the cost center value

### Requirement 3: Security and Network Isolation

**User Story:** As a security engineer, I want the VPN server accessible only through the VPN port and SSM, so that I minimize attack surface.

#### Acceptance Criteria

1. THE Security_Group SHALL allow inbound traffic ONLY on the configured VPN port and protocol
2. THE Security_Group SHALL NOT allow inbound SSH (port 22) from the internet
3. THE VPN_Server SHALL be accessible via AWS Systems Manager Session Manager
4. THE VPN_Server SHALL enforce IMDSv2 (Instance Metadata Service version 2)
5. WHEN AllowedIngressCidr parameter is 0.0.0.0/0, THEN THE System SHALL display a security warning
6. THE VPN_Server SHALL have EBS volumes encrypted
7. THE IAM_Role SHALL have minimal permissions (AmazonSSMManagedInstanceCore only)

### Requirement 4: VPN Service Configuration

**User Story:** As a user, I want to choose between full-tunnel and split-tunnel VPN modes, so that I can control which traffic routes through the VPN.

#### Acceptance Criteria

1. WHEN Full_Tunnel mode is selected, THEN THE VPN_Server SHALL configure NAT/masquerade for all client traffic
2. WHEN Full_Tunnel mode is selected, THEN THE Client_Config SHALL set AllowedIPs to 0.0.0.0/0, ::/0
3. WHEN Split_Tunnel mode is selected, THEN THE Client_Config SHALL set AllowedIPs to only VPC CIDR ranges
4. WHEN Split_Tunnel mode is selected, THEN THE VPN_Server SHALL NOT route internet traffic through the VPN
5. THE VPN_Server SHALL enable IP forwarding when Full_Tunnel mode is configured
6. THE VPN_Server SHALL use WireGuard as the default VPN protocol

### Requirement 5: Orchestration Script - Stack Lifecycle

**User Story:** As a user, I want a single script to manage the entire VPN lifecycle, so that I can easily create, manage, and destroy VPN infrastructure.

#### Acceptance Criteria

1. THE Orchestration_Script SHALL support a `create` command that creates the stack, waits for completion, bootstraps VPN, and generates client configurations
2. THE Orchestration_Script SHALL support a `delete` command that deletes the CloudFormation stack
3. THE Orchestration_Script SHALL support a `status` command that displays stack and instance information
4. THE Orchestration_Script SHALL support a `list` command that enumerates all stacks matching the naming pattern
5. WHEN a stack with the same name exists, THEN THE Orchestration_Script SHALL fail with a clear error message
6. THE Orchestration_Script SHALL wait for stack operations to complete using AWS CLI wait commands
7. THE Orchestration_Script SHALL support both interactive (menu) and non-interactive (CLI flags) modes

### Requirement 6: Orchestration Script - Client Management

**User Story:** As a user, I want to generate VPN client configurations, so that I can connect devices to the VPN.

#### Acceptance Criteria

1. THE Orchestration_Script SHALL support an `add-client` command that generates a new client configuration
2. WHEN creating a stack, THE Orchestration_Script SHALL generate the number of client configurations specified by the `--clients` parameter
3. THE Orchestration_Script SHALL save Client_Config files to `<output-dir>/<Stack_Name>/clients/<clientName>.conf`
4. THE Orchestration_Script SHALL generate cryptographic keys securely (preferably on the server via SSM)
5. THE Orchestration_Script SHALL display connection instructions after generating client configurations
6. THE Client_Config SHALL contain endpoint, port, keys, and AllowedIPs appropriate for the selected mode

### Requirement 7: Orchestration Script - SSM Access

**User Story:** As a user, I want to access the VPN server securely via SSM, so that I can troubleshoot or perform manual operations.

#### Acceptance Criteria

1. THE Orchestration_Script SHALL support an `ssm` command that opens an SSM session to the VPN_Server
2. THE Orchestration_Script SHALL verify the presence of `session-manager-plugin` before attempting SSM connections
3. WHEN `session-manager-plugin` is missing, THEN THE Orchestration_Script SHALL display installation instructions
4. THE Orchestration_Script SHALL execute remote commands on the VPN_Server using SSM Run Command or start-session

### Requirement 8: Multi-Region Support

**User Story:** As a user, I want to deploy VPN infrastructure in different AWS regions, so that I can choose optimal geographic locations.

#### Acceptance Criteria

1. THE Orchestration_Script SHALL accept a `--region` parameter to specify the target AWS region
2. THE Orchestration_Script SHALL support multiple VPN deployments in the same region with different Stack_Names
3. WHEN no Stack_Name is provided, THEN THE Orchestration_Script SHALL auto-generate a unique name (e.g., `another-<date>-<random>`)
4. WHEN a Stack_Name is provided, THE Orchestration_Script SHALL validate uniqueness in the target region

### Requirement 9: Configuration Parameters

**User Story:** As a user, I want to customize VPN deployment parameters, so that I can adapt the infrastructure to my needs.

#### Acceptance Criteria

1. THE Orchestration_Script SHALL accept `--mode full|split` to specify tunnel mode
2. THE Orchestration_Script SHALL accept `--allowed-cidr` (repeatable) to specify which source IP addresses/networks are allowed to connect to the VPN port
3. THE Orchestration_Script SHALL accept `--my-ip` flag to automatically detect and use the operator's public IP as the only allowed ingress CIDR
4. THE Orchestration_Script SHALL accept `--vpc-cidr` to specify the VPC CIDR block (default: 10.10.0.0/16)
5. THE Orchestration_Script SHALL accept `--instance-type` to specify EC2 instance type (default: minimal viable type)
6. THE Orchestration_Script SHALL accept `--clients <n>` to specify number of initial client configurations
7. THE Orchestration_Script SHALL accept `--output-dir` to specify where client configurations are saved
8. THE Orchestration_Script SHALL accept `--yes` or `--non-interactive` to skip confirmation prompts
9. WHEN `--my-ip` flag is used, THEN THE Orchestration_Script SHALL detect the operator's public IP address and use it with /32 suffix as AllowedIngressCidr
10. WHEN `--my-ip` flag is used with `--allowed-cidr`, THEN THE Orchestration_Script SHALL fail with an error message indicating the flags are mutually exclusive
11. WHEN `--vpc-cidr` is provided, THEN THE Orchestration_Script SHALL validate it is a valid private CIDR block (RFC 1918: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
12. WHEN `--vpc-cidr` is provided, THEN THE Orchestration_Script SHALL validate the CIDR has an appropriate prefix length (minimum /28, maximum /16)
13. THE Orchestration_Script SHALL accept `--spot` flag to use EC2 Spot instances instead of on-demand instances
14. WHEN `--spot` flag is used, THEN THE CloudFormation_Template SHALL configure the instance with spot market options
15. WHEN `--spot` flag is NOT used, THEN THE CloudFormation_Template SHALL use on-demand instances (default behavior)
16. THE Orchestration_Script SHALL accept `--eip` flag to allocate an Elastic IP for the VPN instance
17. WHEN `--eip` flag is NOT used, THEN THE Orchestration_Script SHALL display a warning that the public IP may change after instance stop/start operations

### Requirement 10: Elastic IP Management

**User Story:** As a user, I want to optionally allocate an Elastic IP for my VPN instance, so that the public IP address remains stable across instance stop/start operations.

#### Acceptance Criteria

1. THE CloudFormation_Template SHALL accept an `AllocateEIP` parameter (boolean, default: false)
2. WHEN `AllocateEIP` is true, THEN THE CloudFormation_Template SHALL create an AWS::EC2::EIP resource
3. WHEN `AllocateEIP` is true, THEN THE CloudFormation_Template SHALL create an AWS::EC2::EIPAssociation to attach the EIP to the VPN instance
4. WHEN `AllocateEIP` is false, THEN THE CloudFormation_Template SHALL NOT create EIP resources and the instance SHALL use a standard public IP
5. THE CloudFormation_Template SHALL output the public IP address regardless of whether it is an EIP or standard public IP
6. WHEN `--eip` flag is NOT used during stack creation, THEN THE Orchestration_Script SHALL display a warning: "WARNING: Without an Elastic IP, the public IP address will change if you stop and start the instance. Use --eip to allocate a persistent IP address."
7. THE EIP resource SHALL have the costcenter tag applied
8. WHEN the stack is deleted, THEN THE System SHALL automatically release the Elastic IP

### Requirement 11: VPN Server Bootstrap

**User Story:** As a system, I want to automatically configure the VPN server after instance launch, so that the VPN is ready to use without manual intervention.

#### Acceptance Criteria

1. WHEN the stack is created, THEN THE Orchestration_Script SHALL install wireguard-tools on the VPN_Server via SSM
2. THE Orchestration_Script SHALL configure `/etc/wireguard/wg0.conf` on the VPN_Server
3. THE Orchestration_Script SHALL enable IP forwarding on the VPN_Server
4. WHEN Full_Tunnel mode is selected, THEN THE Orchestration_Script SHALL configure iptables/nftables for NAT
5. THE Orchestration_Script SHALL start and enable the `wg-quick@wg0` service
6. THE Orchestration_Script SHALL verify the VPN service is running after bootstrap

### Requirement 11: VPN Server Bootstrap

**User Story:** As a system, I want to automatically configure the VPN server after instance launch, so that the VPN is ready to use without manual intervention.

#### Acceptance Criteria

1. WHEN the stack is created, THEN THE Orchestration_Script SHALL install wireguard-tools on the VPN_Server via SSM
2. THE Orchestration_Script SHALL configure `/etc/wireguard/wg0.conf` on the VPN_Server
3. THE Orchestration_Script SHALL enable IP forwarding on the VPN_Server
4. WHEN Full_Tunnel mode is selected, THEN THE Orchestration_Script SHALL configure iptables/nftables for NAT
5. THE Orchestration_Script SHALL start and enable the `wg-quick@wg0` service
6. THE Orchestration_Script SHALL verify the VPN service is running after bootstrap

### Requirement 12: NixOS Compatibility

**User Story:** As a NixOS user, I want the script to automatically handle missing dependencies, so that I can use the tool without manual environment setup.

#### Acceptance Criteria

1. WHEN the script runs on NixOS and AWS CLI is not in PATH, THEN THE Orchestration_Script SHALL open a temporary shell with awscli2 available
2. WHEN the script runs on NixOS and session-manager-plugin is not in PATH, THEN THE Orchestration_Script SHALL include it in the temporary shell
3. WHEN the script runs on NixOS and jq is not in PATH, THEN THE Orchestration_Script SHALL include it in the temporary shell
4. THE Orchestration_Script SHALL detect NixOS by checking for `/etc/NIXOS`
5. THE Orchestration_Script SHALL re-execute itself within the temporary shell environment

### Requirement 12: NixOS Compatibility

**User Story:** As a NixOS user, I want the script to automatically handle missing dependencies, so that I can use the tool without manual environment setup.

#### Acceptance Criteria

1. WHEN the script runs on NixOS and AWS CLI is not in PATH, THEN THE Orchestration_Script SHALL open a temporary shell with awscli2 available
2. WHEN the script runs on NixOS and session-manager-plugin is not in PATH, THEN THE Orchestration_Script SHALL include it in the temporary shell
3. WHEN the script runs on NixOS and jq is not in PATH, THEN THE Orchestration_Script SHALL include it in the temporary shell
4. THE Orchestration_Script SHALL detect NixOS by checking for `/etc/NIXOS`
5. THE Orchestration_Script SHALL re-execute itself within the temporary shell environment

### Requirement 13: Idempotency and Error Handling

**User Story:** As a user, I want the script to handle errors gracefully and avoid duplicate operations, so that I can safely retry failed operations.

#### Acceptance Criteria

1. WHEN a stack already exists with the same name, THEN THE Orchestration_Script SHALL NOT attempt to recreate it
2. WHEN a CloudFormation operation fails, THEN THE Orchestration_Script SHALL display a clear error message
3. THE Orchestration_Script SHALL use `set -euo pipefail` for robust error handling
4. WHEN adding a client to an existing stack, THEN THE Orchestration_Script SHALL NOT recreate existing clients
5. THE Orchestration_Script SHALL validate required AWS CLI commands are available before execution

### Requirement 13: Idempotency and Error Handling

**User Story:** As a user, I want the script to handle errors gracefully and avoid duplicate operations, so that I can safely retry failed operations.

#### Acceptance Criteria

1. WHEN a stack already exists with the same name, THEN THE Orchestration_Script SHALL NOT attempt to recreate it
2. WHEN a CloudFormation operation fails, THEN THE Orchestration_Script SHALL display a clear error message
3. THE Orchestration_Script SHALL use `set -euo pipefail` for robust error handling
4. WHEN adding a client to an existing stack, THEN THE Orchestration_Script SHALL NOT recreate existing clients
5. THE Orchestration_Script SHALL validate required AWS CLI commands are available before execution

### Requirement 14: Documentation and User Guidance

**User Story:** As a user, I want comprehensive documentation, so that I can understand how to use the system and troubleshoot issues.

#### Acceptance Criteria

1. THE System SHALL include a README.md in English with prerequisites, quickstart, CLI examples, security notes, cost warnings, and troubleshooting
2. THE System SHALL include a README.it.md in Italian with the same content as README.md
3. THE README SHALL explain the security threat model and limitations of the VPN approach
4. THE README SHALL explain the "ephemeral compute box" use case for temporary workloads
5. THE README SHALL include instructions for deleting all resources
6. THE Orchestration_Script SHALL display a help message when invoked with `--help` or invalid arguments

### Requirement 14: Documentation and User Guidance

**User Story:** As a user, I want comprehensive documentation, so that I can understand how to use the system and troubleshoot issues.

#### Acceptance Criteria

1. THE System SHALL include a README.md in English with prerequisites, quickstart, CLI examples, security notes, cost warnings, and troubleshooting
2. THE System SHALL include a README.it.md in Italian with the same content as README.md
3. THE README SHALL explain the security threat model and limitations of the VPN approach
4. THE README SHALL explain the "ephemeral compute box" use case for temporary workloads
5. THE README SHALL include instructions for deleting all resources
6. THE Orchestration_Script SHALL display a help message when invoked with `--help` or invalid arguments

### Requirement 15: Output and Logging

**User Story:** As a user, I want clear output and minimal logging, so that I can understand what the system is doing without exposing sensitive information.

#### Acceptance Criteria

1. THE Orchestration_Script SHALL display progress messages during stack operations
2. THE Orchestration_Script SHALL display a summary of connection information after successful creation
3. THE Orchestration_Script SHALL NOT log or display private keys except in the generated Client_Config files
4. THE Orchestration_Script SHALL display warnings for security-sensitive configurations (e.g., 0.0.0.0/0 ingress)
5. WHEN operations complete, THE Orchestration_Script SHALL display next steps or usage instructions
