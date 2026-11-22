# TravelMemory AWS Deployment Report

> Complete this report after deployment. Replace bracketed prompts with observed values and insert sanitized screenshots. Do not include credentials, private keys, `.env`, Ansible Vault contents, or Terraform state.

## 1. Objective

Deploy the TravelMemory MERN application on AWS using Terraform for infrastructure and Ansible for server configuration, database setup, and application deployment.

## 2. Tools and versions

| Tool | Version / details |
|---|---|
| Terraform | [Run `terraform version`] |
| AWS CLI | [Run `aws --version`] |
| Ansible | [Run `ansible --version`] |
| Ansible collection | `community.mongodb`: [version] |
| AWS Region | [Region] |
| Ubuntu AMI | [AMI ID and release] |

## 3. Architecture and resource inventory

Describe the flow:

```text
Browser → Internet Gateway → Public subnet: Nginx + React + Express
                                      |
                                      +---- Private subnet: MongoDB
Private subnet outbound package traffic → NAT Gateway → Internet Gateway
Ansible control host → SSH to web; SSH ProxyJump via web to private DB
```

| Resource | Name / ID | Configuration |
|---|---|---|
| VPC | [ID, CIDR] | [DNS settings] |
| Public subnet | [ID, CIDR, AZ] | Web instance |
| Private subnet | [ID, CIDR, AZ] | MongoDB instance |
| Internet Gateway | [ID] | Public routing |
| NAT Gateway / EIP | [ID / address] | Private outbound access |
| Public route table | [ID] | Default route to IGW |
| Private route table | [ID] | Default route to NAT |
| Web security group | [ID] | SSH from admin CIDR; HTTP from internet |
| Database security group | [ID] | MongoDB/SSH only from web security group |
| Web EC2 | [ID, type, public IP] | Nginx, React, Node.js, PM2 |
| Database EC2 | [ID, type, private IP] | MongoDB with authorization |
| EC2 IAM role | [Role name] | SSM managed instance core |

Insert a screenshot of the architecture diagram and AWS resource layout here.

## 4. Terraform implementation

Summarize how `terraform/` provisions the VPC, public/private subnets, Internet Gateway, NAT Gateway, route tables, security groups, EC2 instances, key pair, and least-privilege instance role. Record plan/validation/apply outcomes:

- `terraform fmt -recursive`: [result]
- `terraform init`: [result]
- `terraform validate`: [result]
- `terraform plan`: [resource summary]
- `terraform apply`: [result/date]
- Public web IP output: [value]

Insert sanitized Terraform plan/apply and output screenshots.

## 5. Ansible implementation

Document how the inventory uses the public web instance as a jump host to access the private MongoDB instance. Summarize:

- MongoDB installation, private binding, authentication, admin user, app database user, and `readWrite` scope.
- Node.js/NPM and PM2 installation.
- Repository checkout and dependency installation.
- React build using same-origin `/api`.
- Backend environment generation from Ansible Vault.
- Nginx serving the frontend and proxying API requests.
- PM2 startup persistence and automated health checks.

Record the Ansible command and outcome:

```text
ansible-playbook site.yml --ask-vault-pass
Play recap: [ok / changed / unreachable / failed]
```

Insert sanitized Ansible output screenshots. Do not display Vault values.

## 6. Application component communication

Explain the request flow:

1. A browser requests the React application from the public EC2 instance over HTTP.
2. Nginx serves the static React build from `/var/www/travelmemory`.
3. The React app sends API requests to same-origin `/api/...`.
4. Nginx proxies `/api/` to Express on `127.0.0.1:3001`, stripping the `/api/` prefix.
5. Express connects to MongoDB over the VPC private network on port 27017 using the app-specific database user.
6. MongoDB accepts network connections only from the web security group and requires authentication.

## 7. Verification evidence

| Check | Expected | Actual result |
|---|---|---|
| `terraform validate` | Valid configuration | [result] |
| Ansible ping: web and database | Both `pong` | [result] |
| `http://<web-ip>/api/health` | HTTP 200, database connected | [result] |
| Browser frontend | React application loads | [result] |
| Read trips | Data returned from MongoDB | [result] |
| Create trip | Successful API response and persisted data | [result] |
| Image upload/display | Upload stored and image loads | [result] |
| Database exposure | Port 27017 not publicly reachable | [result] |
| Reboot persistence | Nginx, MongoDB, PM2 services enabled | [result] |

Insert sanitized browser screenshots and relevant AWS console evidence.

## 8. Security and operational notes

- SSH is limited to the configured administrator CIDR on the web host; the database host has no public IP.
- SSH password, keyboard-interactive, and root logins are disabled by Ansible; public-key authentication remains enabled.
- MongoDB ingress is limited to the web security group, and the app user has access only to the application database.
- MongoDB passwords are stored in Ansible Vault; the Vault file and private SSH key are excluded from Git.
- EC2 requires IMDSv2 and encrypted root EBS volumes.
- The NAT Gateway incurs ongoing AWS charges.
- Uploads are stored on local web-instance storage and require backups; object/shared storage would be needed for resilient production use.
- HTTP is used for the assessment unless HTTPS is added separately.

## 9. Issues and resolutions

| Issue | Root cause | Resolution |
|---|---|---|
| [Issue] | [Cause] | [Resolution] |

## 10. Repository and submission

- GitHub repository: [URL]
- Vlearn submission date: [date]
- Evidence directory: [`docs/screenshots/`](./screenshots/)
