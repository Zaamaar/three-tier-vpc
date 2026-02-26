# Three-Tier VPC Architecture on AWS

A production-grade, secure three-tier network architecture
built entirely with AWS CLI and bash scripting.
No clicking in the console — everything is code.

---

## Architecture
```
                         INTERNET
                             │
                    YOUR IP  │  HTTP/HTTPS
                    SSH ─────┤  from anywhere
                             │
                             ▼
                    [Internet Gateway]
                             │
         ┌───────────────────────────────────────┐
         │           three-tier-vpc               │
         │            10.0.0.0/16                 │
         │                                        │
         │  ┌──────────────────────────────────┐  │
         │  │         PUBLIC SUBNET            │  │
         │  │         10.0.1.0/24              │  │
         │  │                                  │  │
         │  │  ┌─────────────┐                 │  │
         │  │  │ Bastion Host│◄── SSH from     │  │
         │  │  │             │    YOUR IP only  │  │
         │  │  └──────┬──────┘                 │  │
         │  │         │ SSH jump               │  │
         │  │  ┌──────▼──────┐                 │  │
         │  │  │ Web Server  │◄── HTTP/HTTPS   │  │
         │  │  │             │    from anywhere │  │
         │  │  └──────┬──────┘                 │  │
         │  │         │ port 8080 only         │  │
         │  │  [NAT Gateway]                   │  │
         │  │       │                          │  │
         │  └───────┼──────────────────────────┘  │
         │          │ outbound only                │
         │          ▼                              │
         │       INTERNET                         │
         │                                        │
         │  ┌──────────────────────────────────┐  │
         │  │        PRIVATE SUBNET            │  │
         │  │        10.0.2.0/24               │  │
         │  │                                  │  │
         │  │  ┌─────────────┐                 │  │
         │  │  │ App Server  │◄── port 8080    │  │
         │  │  │             │    from web only │  │
         │  │  │             │◄── SSH from      │  │
         │  │  └─────────────┘    bastion only  │  │
         │  │                                  │  │
         │  │   ✗ NO PUBLIC IP                 │  │
         │  │   ✗ UNREACHABLE FROM INTERNET    │  │
         │  └──────────────────────────────────┘  │
         └───────────────────────────────────────┘
```

---

## How the Bastion Host Works

The Bastion Host is the single controlled entry point
into the entire infrastructure. Instead of opening SSH
on every server, you SSH into the bastion first —
then jump from the bastion into any private server.
```
Your Mac
    │
    │  SSH (port 22) — your IP only
    ▼
Bastion Host (public subnet)
    │
    │  SSH jump (-J flag)
    ▼
App Server (private subnet)
```

The app server has no public IP and no direct
internet route. The only way to reach it is
through the bastion. If the bastion is
compromised, the blast radius is contained —
the attacker still cannot reach private servers
without the SSH key.

---

## What This Project Demonstrates

- Custom VPC with public and private subnet design
- Internet Gateway for public internet connectivity
- NAT Gateway for private subnet outbound access
- Route tables that define public vs private subnets
- Security Groups as stateful instance level firewalls
- NACLs as stateless subnet level firewalls
- Bastion Host pattern for secure jump server access
- IAM Instance Profiles with least privilege permissions
- Infrastructure as Code using AWS CLI and bash
- Automated cleanup script to avoid ongoing charges

---

## Services Used

| Service | Purpose |
|---|---|
| Amazon VPC | Isolated private network foundation |
| EC2 | Virtual servers for each tier |
| Internet Gateway | Connects VPC to public internet |
| NAT Gateway | Outbound internet for private subnet |
| Route Tables | Controls traffic flow between subnets |
| Security Groups | Stateful firewall per instance |
| Network ACLs | Stateless firewall per subnet |
| IAM Roles | Least privilege permissions for EC2 |
| Elastic IP | Fixed public IP for NAT Gateway |
| SSH Key Pair | Secure keyless authentication to EC2 |

---

## Network Design

| Resource | CIDR | Purpose |
|---|---|---|
| VPC | 10.0.0.0/16 | Entire private network |
| Public Subnet | 10.0.1.0/24 | Internet-facing resources |
| Private Subnet | 10.0.2.0/24 | Protected resources |

---

## Security Design

### Two Independent Layers of Defence

**Layer 1 — Security Groups**
Stateful firewall attached to each EC2 instance.
Automatically allows return traffic.

| Instance | Allowed Inbound | Source |
|---|---|---|
| Bastion Host | SSH port 22 | Your IP only |
| Web Server | HTTP port 80 | Anywhere |
| Web Server | HTTPS port 443 | Anywhere |
| Web Server | SSH port 22 | Bastion SG only |
| App Server | Port 8080 | Web Server SG only |
| App Server | SSH port 22 | Bastion SG only |

**Layer 2 — Network ACLs**
Stateless firewall attached to each subnet.
Must explicitly allow both directions including
ephemeral return ports 1024-65535.

| Subnet | Inbound | Outbound |
|---|---|---|
| Public | HTTP, HTTPS, SSH from your IP, ephemeral | HTTP, HTTPS, SSH to VPC, ephemeral |
| Private | Port 8080 from public subnet, SSH from public subnet, ephemeral | HTTP, HTTPS, ephemeral to VPC |

### IAM Least Privilege

Each server has only the permissions it needs.
Nothing more.

| Instance | IAM Permissions | Why |
|---|---|---|
| Bastion Host | SSM only | Jump server needs no AWS API access |
| Web Server | S3 read, CloudWatch, SSM | Serve static assets and write logs |
| App Server | DynamoDB, CloudWatch, SSM | Database access and write logs |

---

## Prerequisites

- AWS account with CLI configured
- IAM user with EC2, VPC, and IAM permissions
- Bash shell (Mac or Linux)
- SSH client

---

## Deployment

**1. Clone the repository**
```bash
git clone https://github.com/Zaamaar/three-tier-vpc.git
cd three-tier-vpc
```

**2. Make scripts executable**
```bash
chmod +x infrastructure.sh cleanup.sh
```

**3. Deploy the entire architecture**
```bash
./infrastructure.sh
```

The script takes about 3-4 minutes. When complete
it prints your connection details:
```
============================================
  ALL INSTANCES READY!
============================================

  Connection Details:
  Bastion Host:   54.123.45.67
  Web Server:     54.123.45.89
  App Server:     10.0.2.45 (private only)

  How to connect:

  SSH to Bastion:
  ssh -i ~/.ssh/three-tier-key.pem ec2-user@54.123.45.67

  SSH to App Server via Bastion:
  ssh -i ~/.ssh/three-tier-key.pem -J ec2-user@54.123.45.67 ec2-user@10.0.2.45

  View Web Server:
  http://54.123.45.89
============================================
```

**4. Tear down everything when done**
```bash
./cleanup.sh
```

The cleanup script asks for confirmation before
deleting anything and removes all resources in
the correct dependency order.

---

## File Structure
```
three-tier-vpc/
├── infrastructure.sh    # Builds entire AWS architecture
├── cleanup.sh           # Tears down all resources safely
└── README.md            # This file
```

---

## Real World Applications

This architecture is the standard secure foundation
used across industries:

**Fintech**
Web tier handles customer requests publicly.
App tier processes transactions privately.
Database tier stores financial records in complete
isolation. PCI DSS compliance requires this
separation.

**E-commerce**
Public web servers absorb traffic spikes during
sales events. Private app servers process orders
and handle payment logic away from direct internet
exposure.

**Healthcare**
Patient data lives in private subnets completely
isolated from the internet. HIPAA compliance
requires that sensitive data never be directly
internet accessible.

**SaaS Products**
Multi-tier isolation means a compromise of the
web tier cannot directly reach business logic
or customer data in the private tier.

---

## Key Concepts Demonstrated

**Why is a subnet public or private?**
Not the subnet itself — it's the route table.
A public subnet has a route sending internet
traffic to an Internet Gateway.
A private subnet has a route sending internet
traffic to a NAT Gateway — outbound only.

**Why use a Bastion Host instead of opening SSH everywhere?**
One hardened entry point with strict IP
restrictions is easier to monitor, audit,
and secure than SSH open on every server.
All SSH sessions go through one chokepoint.

**Why do NACLs need ephemeral port rules?**
NACLs are stateless — they don't track
connections. Return traffic on random high
ports 1024-65535 must be explicitly allowed
or responses never reach their destination.

**Why attach IAM roles instead of using access keys?**
IAM role credentials are temporary and rotate
automatically every few hours. Access keys are
permanent until manually rotated and can be
accidentally exposed in code or config files.

---

## Cost Warning
```
NAT Gateway: ~$0.045/hour = ~$32/month
EC2 (x3 t2.micro): Free tier eligible
Elastic IP: Free while attached
```

**Always run cleanup.sh when finished.**
The NAT Gateway is the only resource with
significant ongoing cost. The cleanup script
deletes it first to stop the billing clock.

---

## Author

**Ayotomiwa Ayorinde**
[LinkedIn](https://linkedin.com/in/YOUR_LINKEDIN) •
[Medium](https://medium.com/@YOUR_MEDIUM) •
[GitHub](https://github.com/Zaamaar)