# TravelMemory on AWS with Terraform and Ansible

This guide follows the assessment PDF's topology: **one Ubuntu web/application EC2 instance in a public subnet** and **one Ubuntu MongoDB EC2 instance in a private subnet**. Terraform creates the AWS network, security groups, IAM role, key pair, and instances. Ansible installs and configures MongoDB, Node.js, PM2, Nginx, and the TravelMemory application.

The project is intentionally separate from the prior manual EC2 assignment. The deployable code lives in `terraform/` and `ansible/`; the app remains in `backend/` and `frontend/`. The AWS resources are **not** created by committing this repository. You will run Terraform and Ansible yourself after reviewing the plan.

## Assessment checklist

| Requirement | Implementation |
|---|---|
| Terraform project for AWS | `terraform/` with AWS provider, inputs, resources, and outputs |
| VPC with public and private subnets | Terraform creates one of each in the selected Region |
| Internet Gateway and NAT Gateway | IGW provides public web access; NAT provides private-instance outbound access |
| Route tables | Public route to the IGW; private default route to the NAT Gateway |
| Two EC2 instances | Public Ubuntu web/app host and private Ubuntu MongoDB host |
| SSH access | Web host restricted to `admin_cidr`; private DB SSH only from web SG for Ansible ProxyJump |
| Security groups and IAM roles | Narrow web/database ingress plus an EC2 SSM role |
| Public web IP output | `terraform output web_public_ip` |
| Ansible communication | Static inventory from Terraform outputs; SSH to DB through the web host |
| Web setup and application deployment | Ansible installs Node/NPM, clones the application, installs dependencies, builds React, and configures Nginx/PM2 |
| Database setup | Ansible installs MongoDB, enables authentication, creates admin/app users and the application database |
| Security hardening | Private database, app-scoped database role, secret vault, IMDSv2, encrypted EBS, restricted SSH and MongoDB rules |
| Report, architecture, and evidence | `docs/terraform-ansible-report.md`, `docs/terraform-ansible-architecture.drawio`, and screenshots you capture |

## Important before you start

- **Costs:** a NAT Gateway has hourly and data-processing charges; EC2 and public IPv4 addresses can also cost money. Review AWS pricing and your account budget before applying. Destroy the resources when the assignment is finished if you do not need them.
- **Account access:** use an IAM Identity Center permission set or another authorized deployment identity, not root. The identity running Terraform needs permission to create the listed VPC/EC2/IAM resources and `iam:PassRole` for the EC2 role. The attached EC2 role uses the AWS-managed `AmazonSSMManagedInstanceCore` policy.
- **Region:** Terraform defaults to `ap-southeast-2`. Keep the Terraform, EC2 key, and AWS CLI profile in the same Region.
- **SSH:** use a dedicated key pair. Keep the private key in your WSL home directory and out of Git. The web security group admits SSH only from your public IP `/32`; the DB is private and can be reached by Ansible through SSH ProxyJump.
- **SSH hardening:** Ansible disables SSH root, password, and keyboard-interactive logins on both hosts while preserving public-key login.
- **MongoDB Atlas is not used in this assignment topology:** this setup installs MongoDB on the private EC2 instance per the PDF. If you have already used Atlas, do not put its URI in these files.
- **Secrets:** the MongoDB passwords go into an Ansible Vault file ignored by Git. Never commit `.env`, `vault.yml`, Terraform state, private keys, or screenshots that reveal secrets.
- **Uploads:** the application currently stores uploaded images on the web instance's disk. That is suitable for the single-web-host assessment topology but is not durable across instance replacement. Back up uploaded data before destroying the instance.

## Part 1 - Prepare your Windows workstation

Ansible does not run natively on Windows. Use **WSL 2 with Ubuntu** as the control machine; run the commands below in the Ubuntu/WSL terminal, not PowerShell. Install and configure:

- Terraform CLI
- AWS CLI v2
- Ansible
- OpenSSH client
- Python 3 and `community.mongodb` Ansible collection

On Ubuntu 24.04 in WSL, the following installs Ansible and Terraform. Install AWS CLI v2 using AWS's official installer:

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg unzip ansible
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip
```

The AWS CLI example above is for x86_64 WSL. Use AWS's ARM64 installer if your WSL distribution is ARM64. Terraform should be installed from HashiCorp's official package repository.

Verify the tools:

```bash
terraform version
aws --version
ansible --version
ssh -V
```

In WSL, install the `community.mongodb` collection when you reach the Ansible directory:

```bash
cd "/mnt/d/HV/Assessment/Deploying MERN via Terraform-Ansible/MERN App Deployment with Terraform-Ansible/ansible"
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
ansible-galaxy collection install -r requirements.yml
```

Set `ANSIBLE_CONFIG` in each new WSL terminal before running Ansible. This repository is on a Windows-mounted drive; without the explicit setting, Ansible may ignore `ansible.cfg` because mounted Windows directories can appear world-writable. If WSL reports a different mounted-drive path, use the actual path shown by `pwd` and quote it because the directory names contain spaces.

## Part 2 - Configure AWS credentials

Configure an AWS IAM Identity Center profile (use the portal start URL and SSO Region provided by your account):

```bash
aws configure sso --profile travelmemory
aws sso login --profile travelmemory
export AWS_PROFILE=travelmemory
aws sts get-caller-identity
```

Confirm that the returned account is the intended assessment account. The principal must be allowed to create VPC/subnet/routes/IGW/NAT/EIP/security groups, EC2 instances and key pairs, and the EC2 IAM role/profile/policy attachment. If IAM role creation or `iam:PassRole` is restricted, ask the account administrator to authorize the specific Terraform resources rather than switching to root.

## Part 3 - Prepare the SSH key and Terraform inputs

From the WSL terminal:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/travelmemory-terraform -C travelmemory-terraform
chmod 600 ~/.ssh/travelmemory-terraform
```

Use a passphrase when prompted and keep the private key (`travelmemory-terraform`) private. Terraform only needs the public key.

Prepare the Terraform variable file:

```bash
cd "/mnt/d/HV/Assessment/Deploying MERN via Terraform-Ansible/MERN App Deployment with Terraform-Ansible/terraform"
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

- Set `admin_cidr` to your current public IPv4 address with `/32`, for example `198.51.100.24/32`. Do not use `0.0.0.0/0` for SSH.
- To check your current public IPv4 from WSL, run `curl -4 https://checkip.amazonaws.com` and append `/32`; update it if your ISP address changes.
- Set `ssh_public_key` to the WSL path of the `.pub` file. The example uses `/home/YOUR_LINUX_USER/.ssh/travelmemory-terraform.pub`; replace `YOUR_LINUX_USER`.
- Set `aws_region` to the intended Region if not `ap-southeast-2`.
- Choose EC2 sizes that satisfy the assignment and your budget. The database defaults to `t3.small` because MongoDB benefits from more memory; smaller types may fail or perform poorly.

The `.gitignore` excludes `terraform.tfvars` and Terraform state. Do not remove those rules.

## Part 4 - Review and create infrastructure with Terraform

From `terraform/`:

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan -out=travelmemory.tfplan
```

Review the plan carefully. It should create one VPC, two subnets, an Internet Gateway, a NAT Gateway and Elastic IP, route tables, two security groups, an EC2 role/profile, a key pair, and two Ubuntu instances. It should **not** change or destroy unrelated AWS resources.

If the plan is correct:

```bash
terraform apply travelmemory.tfplan
```

Save these outputs for the Ansible inventory:

```bash
terraform output
terraform output -raw web_public_ip
terraform output -raw database_private_ip
```

The web host receives a public IPv4 address. The database has no public IP. Terraform state contains infrastructure metadata; keep it private and never commit it. The configuration currently creates both subnets in one Availability Zone to match the assignment's two-subnet design and keep the topology simple; this is not multi-AZ high availability.

## Part 5 - Prepare the Ansible inventory

Copy the example inventory and replace the placeholders using Terraform outputs:

```bash
cd "../ansible"
cp inventory.ini.example inventory.ini
```

Edit `inventory.ini`:

- Replace `REPLACE_WITH_WEB_PUBLIC_IP` with `terraform output -raw web_public_ip`.
- Replace `REPLACE_WITH_DATABASE_PRIVATE_IP` with `terraform output -raw database_private_ip`.
- Replace `YOUR_LINUX_USER` with the WSL username whose `~/.ssh/travelmemory-terraform` private key corresponds to the Terraform public key.

The database's `ansible_ssh_common_args` uses the public web host as an SSH jump host. The private key must be readable by the WSL user. Do not copy the private key onto the EC2 server.

Check the inventory parses:

```bash
ansible-inventory --graph
```

## Part 6 - Create and encrypt MongoDB passwords

Create random passwords locally in WSL (do not paste them into chat or Git):

```bash
openssl rand -hex 32
openssl rand -hex 32
```

Hexadecimal passwords avoid reserved URI characters when the application connection string is generated. Copy the example to the ignored vault file:

```bash
mkdir -p group_vars/all
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
nano group_vars/all/vault.yml
```

Replace both example passwords with the two different generated values. Save in nano with **Ctrl+O**, **Enter**, then **Ctrl+X**. Encrypt the file:

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

Use a vault password that is different from both MongoDB passwords. Keep it somewhere secure; it cannot be recovered if lost. The encrypted file is also ignored by Git because it contains sensitive credentials.

## Part 7 - Set application URL and test Ansible connectivity

Edit `group_vars/all/main.yml` and replace `REPLACE_WITH_WEB_PUBLIC_IP` in `app_public_url` with the Terraform web public IP:

```yaml
app_public_url: "http://WEB_PUBLIC_IP"
```

The default app repository points to the assessment's public TravelMemory repository. If you want deployment from your own public fork, change `app_repo_url` to that repository. A private GitHub repository requires a separately secured deploy key/token; do not put a token in the URL or inventory.

Install the required Ansible collection and test SSH:

```bash
ansible-galaxy collection install -r requirements.yml
ansible all -m ping
```

Both `web` and `database` should respond with `pong`. For SSH issues, check `admin_cidr`, the WSL key path/permissions, the web host's public IP, and the database ProxyJump entry. Do not expose the database publicly as a workaround.

## Part 8 - Configure MongoDB and deploy the app with Ansible

Run the playbook from `ansible/`:

```bash
ansible-playbook site.yml --ask-vault-pass
```

Enter the Ansible Vault password. The playbook runs the database play first, then the web/application play. It:

1. Installs MongoDB 8.0 on the private Ubuntu instance.
2. Creates an administrator, enables MongoDB authorization, and creates a separate app user with `readWrite` only on the TravelMemory database.
3. Allows MongoDB network access only from the web EC2 security group.
4. Installs Node.js 22, NPM, Nginx, and PM2 on the public web host.
5. Clones the application, installs backend/frontend dependencies using lock files, builds React with `/api`, and writes the backend `.env` from encrypted variables.
6. Configures PM2 to run the Express backend and start after reboots.
7. Configures Nginx to serve the frontend and reverse proxy `/api/` to the Node API.
8. Disables SSH password/root logins while retaining public-key authentication.
9. Checks the backend health endpoint directly and through Nginx, including that MongoDB reports connected.

If a task fails, fix the reported cause and safely rerun the playbook; tasks are designed to be repeatable. Never print the Vault variables or `.env` contents when troubleshooting.

## Part 9 - Verify the deployment

From WSL, test the API and frontend:

```bash
WEB_IP=$(terraform -chdir=../terraform output -raw web_public_ip)
curl -i "http://${WEB_IP}/api/health"
```

Open `http://WEB_PUBLIC_IP` in a browser. Verify:

- TravelMemory frontend loads and client-side routes work.
- Trips can be read from MongoDB.
- Creating a trip works.
- An image upload works and the uploaded image is served.
- `/api/health` reports a connected database.
- Port 27017 is not publicly reachable; only the web security group can connect to it.

The application has a same-origin `/api` route through Nginx, so browser calls use the page's origin. If you add a DNS name or HTTPS later, update `app_public_url` and rerun Ansible so `CORS_ORIGIN` stays aligned.

## Part 10 - Capture report, diagram, and evidence

Complete [docs/terraform-ansible-report.md](./docs/terraform-ansible-report.md) with actual Region, VPC/subnet IDs, instance IDs, public IP, screenshots, and verification outcomes. The architecture diagram is [docs/terraform-ansible-architecture.drawio](./docs/terraform-ansible-architecture.drawio); open it with diagrams.net and adjust labels/values if needed.

Capture and add sanitized screenshots under `docs/screenshots/`:

- Terraform plan/apply success and outputs (hide account details if unnecessary).
- VPC, public/private subnets, route tables, NAT Gateway, and security groups.
- Both EC2 instances showing web public and database private placement.
- Ansible play recap and successful health check.
- The running app in a browser, including an API-backed trip view/create.
- The architecture diagram.

Before adding screenshots, inspect them for keys, passwords, MongoDB URIs, account-sensitive details, and Vault content. Do not include `.env`, vault files, private keys, or Terraform state in the repository.

## Part 11 - Push to your GitHub repository and submit

This local clone has an `upstream` remote to the original TravelMemory source and intentionally has **no `origin` remote**. Create a new GitHub repository named `MERN App Deployment with Terraform-Ansible`, then add it as `origin`:

```bash
git remote add origin https://github.com/YOUR_USERNAME/MERN-App-Deployment-with-Terraform-Ansible.git
git status --short
git add README.md .gitignore TERRAFORM_ANSIBLE_DEPLOYMENT.md terraform ansible docs
git diff --cached --check
git commit -m "Add Terraform and Ansible AWS deployment"
git push -u origin main
```

Verify before staging that no `.env`, `vault.yml`, private key, `terraform.tfvars`, or state file is listed. Submit a text, Word, or PDF file containing the new repository URL through Vlearn.

## Cleanup after grading

To avoid continued charges, keep the deployment only as long as needed for evaluation. When ready to remove all resources created by this Terraform project, from `terraform/` run:

```bash
terraform destroy
```

Review the destroy plan before confirming. This deletes the VPC, EC2 instances, NAT Gateway, Elastic IP, and other resources managed by this project. Download required evidence and back up any uploaded images before destroying them.
