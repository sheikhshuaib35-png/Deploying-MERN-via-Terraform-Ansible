# TravelMemory AWS Deployment Guide

This guide records the current EC2 deployment and the remaining work for the AWS Cloud Deployment assignment. It is written so the remaining setup can be completed later. Replace example values such as `YOUR_REPOSITORY` with your own values; never commit real credentials.

The target architecture diagram is [docs/travelmemory-aws-architecture.drawio](./docs/travelmemory-aws-architecture.drawio). Open it with [diagrams.net](https://app.diagrams.net/) to view or edit it.

## Deployment status

| Requirement | Status |
|---|---|
| Ubuntu EC2 instance and Nginx | Complete |
| Backend process managed by PM2 | Complete |
| MongoDB Atlas connection | Previously verified healthy; rotate the exposed database password before continuing |
| Nginx serves the React build | Verified locally on the instance |
| Nginx `/api/health` proxy | Verified healthy |
| Full browser workflow, including creating a trip | Verify after fixing/checking the browser CORS error |
| Two frontend EC2 instances behind a frontend load balancer | Pending |
| Two backend EC2 instances behind a backend load balancer | Pending |
| Cloudflare DNS records and custom domain | Pending |
| Deployment screenshots/evidence | Pending |
| Push documentation and diagram to your GitHub repository | Pending |

The current application uses backend port **3001** (`backend/.env.example`, backend configuration, and local API URL). The assignment mentions port 3000, but changing the application port is not required: this guide consistently uses 3001 internally. If you choose to change it, update the backend environment, process, target groups, security groups, Nginx proxy, and tests together.

## Before continuing

### Rotate the database credential

The MongoDB connection string was exposed in the working conversation. Consider its password compromised:

1. In MongoDB Atlas, change the password for the database user (this is not necessarily the Atlas website login).
2. Update `MONGO_URI` in the private `.env` file on every backend instance.
3. Restart the backend process and verify `/health` reports a connected database.
4. Do not paste the replacement URI into chat, screenshots, documentation, or Git.

The repository `.gitignore` excludes `.env` files. Keep this protection in place and verify no real `.env` file is tracked before pushing.

### Cost and access

Multiple EC2 instances, Application Load Balancers, public IPv4 addresses, NAT gateways, and data transfer can incur AWS charges. Check current pricing, use only the resources needed for the assignment, and remove temporary resources when finished.

Use the Identity Center permission set for routine work. Restrict SSH to a trusted source or use an approved managed connection method. Do not expose the backend port to the public internet.

## Target layout

```text
Browser
  |
  +-- Cloudflare www (CNAME) --> Public Frontend ALB :80/:443
  |                                |-- Frontend EC2 1 (Nginx + React)
  |                                `-- Frontend EC2 2 (Nginx + React)
  |                                      |
  |                                      `-- /api --> Internal Backend ALB :80
  |                                                       |-- Backend EC2 1 :3001
  |                                                       `-- Backend EC2 2 :3001
  |                                                             |
  |                                                             `--> MongoDB Atlas
  |
  `-- Cloudflare direct (A) --> Frontend EC2 1 public IP (bypasses the ALB)
```

The direct A record is included because the assignment requests it. It is not load-balanced or highly available; the CNAME to the frontend ALB should be the normal application address. A single DNS hostname cannot have both a CNAME and an A record, so use different hostnames.

## Phase 1: Secure and validate the existing instance

The current instance already has the frontend and backend on one EC2 host. Preserve it as **Frontend 1** after the backend tier is ready.

1. Rotate and update the database credentials as described above.
2. Check PM2 and the API:

   ```bash
   pm2 status
   curl http://127.0.0.1:3001/health
   ```

   Expect `status: ok` and `db: connected`.
3. Check Nginx and the served frontend:

   ```bash
   sudo nginx -t
   curl -I http://127.0.0.1/
   curl http://127.0.0.1/api/health
   ```

4. Open the instance's current HTTP URL in a browser. Test loading the app and submitting a trip. A healthy `/api/health` alone does not prove that the browser's API requests or file uploads work.
5. If the browser reports a CORS error, inspect the browser-visible frontend origin and backend configuration. With the recommended same-origin `/api` proxy, the frontend should call `/api/...` on its own host; rebuild the React app if its API URL was baked in as localhost or another host. Do not set CORS to `*` as a shortcut.

## Phase 2: Create security groups

Create these security groups in the same VPC as the existing EC2 instance. Refer to security groups as sources rather than opening application ports to all IPv4 addresses.

| Security group | Inbound |
|---|---|
| `tm-frontend-alb-sg` | TCP 80 from `0.0.0.0/0`; add TCP 443 when HTTPS is configured |
| `tm-frontend-ec2-sg` | TCP 80 from `tm-frontend-alb-sg`; SSH only from the required trusted source/connection path |
| `tm-backend-alb-sg` | TCP 80 from `tm-frontend-ec2-sg` |
| `tm-backend-ec2-sg` | TCP 3001 from `tm-backend-alb-sg`; SSH only from the required trusted source/connection path |

Leave required outbound access enabled for package installation and Atlas connectivity. Atlas uses IP access rules, not EC2 security-group references. For a stable and restricted Atlas allowlist across multiple backends, route outbound traffic through a NAT gateway with an Elastic IP, or otherwise use stable backend egress IPs. Avoid allowing all internet addresses in Atlas as a permanent configuration.

When moving the existing instance to `tm-frontend-ec2-sg`, ensure your administrative connection still works before removing its old security group.

## Phase 3: Launch and configure two backend instances

1. In **EC2 → Instances → Launch instances**, choose Ubuntu, select an appropriate instance size, and use `tm-backend-ec2-sg`.
2. Launch two instances in the same VPC and preferably in different Availability Zones. Keep them private where the chosen administration and outbound networking design permits.
3. Connect to each instance using the approved method. Install Git, Node.js 22, and PM2:

   ```bash
   sudo apt update
   sudo apt install -y ca-certificates curl git
   curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
   sudo bash /tmp/nodesource_setup.sh
   sudo apt install -y nodejs
   sudo npm install --global pm2
   ```

4. Clone your own repository and install backend dependencies. Example:

   ```bash
   git clone https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git ~/travelmemory
   cd ~/travelmemory/backend
   npm ci
   mkdir -p uploads
   ```

5. Create a private `backend/.env` on each instance. Set the rotated Atlas connection string and values such as:

   ```env
   PORT=3001
   CORS_ORIGIN=https://www.example.com
   UPLOAD_DIR=uploads
   MAX_UPLOAD_MB=5
   TRUST_PROXY=1
   ```

   Replace the example origin with the final browser-facing origin. If using HTTP while testing, use the exact `http://` origin instead. Do not use quotes around an actual credential unless needed, and do not commit the file.
6. Start the service:

   ```bash
   pm2 start index.js --name travelmemory-api --cwd /home/ubuntu/travelmemory/backend
   pm2 startup
   ```

   Run the `sudo ...` command printed by `pm2 startup`, then run:

   ```bash
   pm2 save
   curl http://127.0.0.1:3001/health
   ```

7. Repeat on Backend 2. Confirm both show a healthy database connection before creating the target group.

### Important: uploaded image persistence

The application stores uploaded images in its local `UPLOAD_DIR`. With multiple backend instances, an image uploaded to one instance may not exist on the other. The ALB does not synchronize files. Before relying on uploads in the scaled deployment, use shared durable storage (for example, S3 with appropriate application changes, or a suitably configured shared filesystem) or document and test the limitation. Do not assume local instance disks are shared.

## Phase 4: Create the internal backend load balancer

1. Open **EC2 → Target Groups → Create target group**.
2. Choose **Instances**, protocol **HTTP**, port **3001**, and the backend VPC.
3. Set the health check protocol to HTTP and path to `/health`. Register Backend 1 and Backend 2.
4. Create an **Application Load Balancer** named `tm-backend-alb`.
5. Choose **Internal**, select subnets in at least two Availability Zones, and attach `tm-backend-alb-sg`.
6. Add an HTTP listener on port **80** that forwards to the backend target group. The ALB listener can use port 80 while its targets use port 3001.
7. Wait for both targets to report **Healthy**. Record the internal ALB DNS name; it is reachable only from the VPC.

If targets are unhealthy, check the target group health reason, backend process/logs, `/health`, VPC/subnet selection, and security-group references. Do not open port 3001 to the public internet to troubleshoot.

## Phase 5: Configure two frontend instances

### Frontend 1 (current EC2)

The current instance already serves the React build from `/var/www/travelmemory`. After Backend 1 and 2 are healthy behind the internal ALB:

1. Edit `/etc/nginx/sites-available/default`.
2. Inside the active `server { ... }` block listening on port 80, configure the site root and locations below. Replace the placeholder with the internal backend ALB DNS name:

   ```nginx
   root /var/www/travelmemory;
   index index.html;

   location /api/ {
       proxy_pass http://BACKEND_INTERNAL_ALB_DNS/;
       proxy_http_version 1.1;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto $scheme;
   }

   location / {
       try_files $uri $uri/ /index.html;
   }
   ```

   The trailing slash on `proxy_pass` intentionally strips the `/api/` prefix, so `/api/health` is sent to the backend as `/health`.
3. Verify and reload:

   ```bash
   sudo nginx -t
   sudo systemctl reload nginx
   curl http://127.0.0.1/api/health
   ```

4. Once the frontend is confirmed to work through the backend ALB, stop the old API process on this frontend host to avoid running an unregistered backend:

   ```bash
   pm2 delete travelmemory-api
   ```

### Frontend 2 (new EC2)

1. Launch a second Ubuntu instance, preferably in another Availability Zone, with `tm-frontend-ec2-sg`.
2. Install Node.js, Nginx, and Git; clone your repository:

   ```bash
   sudo apt update
   sudo apt install -y nginx ca-certificates curl git
   curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
   sudo bash /tmp/nodesource_setup.sh
   sudo apt install -y nodejs
   ```

   Then clone your own repository:

   ```bash
   git clone https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git ~/travelmemory
   ```

3. Build the React app with a same-origin API path. This environment variable is baked into the production build:

   ```bash
   cd ~/travelmemory/frontend
   printf 'REACT_APP_BACKEND_URL=/api\n' > .env
   npm ci
   npm run build
   sudo mkdir -p /var/www/travelmemory
   sudo cp -a build/. /var/www/travelmemory/
   ```

4. Configure Nginx on Frontend 2 with the same `root` and `location` blocks as Frontend 1, using the internal backend ALB DNS name.
5. Validate and enable Nginx:

   ```bash
   sudo nginx -t
   sudo systemctl enable --now nginx
   sudo systemctl reload nginx
   curl http://127.0.0.1/
   curl http://127.0.0.1/api/health
   ```

## Phase 6: Create the public frontend load balancer

1. Create a target group for **Instances**, protocol **HTTP**, port **80**, in the frontend VPC. Use `/` as the health check path.
2. Register Frontend 1 and Frontend 2. The instance security group must allow port 80 from `tm-frontend-alb-sg`.
3. Create an **internet-facing Application Load Balancer** named `tm-frontend-alb`.
4. Select public subnets in at least two Availability Zones and attach `tm-frontend-alb-sg`.
5. Add an HTTP listener on port **80** forwarding to the frontend target group.
6. Wait for both frontend targets to report **Healthy**.
7. Open the ALB DNS name in a browser and test navigation, API reads, trip creation, and uploaded images if enabled.

If browser calls fail, inspect the browser Network/Console panels. Confirm the React build uses `/api`, frontend Nginx proxies `/api/` to the internal ALB, and the backend target group is healthy.

## Phase 7: Cloudflare DNS and HTTPS

Create two different hostnames in Cloudflare DNS, as requested by the assessment:

| Name | Type | Target | Purpose |
|---|---|---|---|
| `www` | CNAME | Public frontend ALB DNS name | Normal load-balanced application address |
| `direct` | A | Frontend 1 public IPv4 address (or Elastic IP) | Assignment-requested direct EC2 address; bypasses the ALB |

Do not create both a CNAME and an A record for the same hostname. The direct A record is not highly available; an EC2 public IPv4 address can change if the instance is stopped and started. Use an Elastic IP if the record must remain stable.

Start with Cloudflare **DNS only** while testing. For HTTPS on the normal hostname:

1. Request an ACM public certificate in the same AWS Region as the frontend ALB, covering the hostname (for example, `www.example.com`).
2. Validate the certificate using the DNS validation record ACM provides; add that record in Cloudflare.
3. Add an HTTPS listener on port 443 to the frontend ALB and attach the validated certificate. Add a port 80 listener rule to redirect to HTTPS if desired.
4. Add inbound 443 to the frontend ALB security group.
5. Set Cloudflare SSL/TLS mode to **Full (strict)** after the ALB certificate is active.

The `direct` hostname goes straight to EC2 and does not use the ALB certificate. Configure TLS on that instance separately if HTTPS is required there, or use the ALB hostname as the normal application endpoint.

## Phase 8: Evidence and submission

Capture clear screenshots for the documentation, with credentials, account identifiers where unnecessary, and sensitive values redacted:

- The running application through the custom domain.
- The frontend and backend target groups with both instances healthy.
- The frontend and internal backend ALBs, listeners, and target groups.
- EC2 instances and Availability Zones (do not expose SSH keys or `.env`).
- Cloudflare CNAME and A records using distinct hostnames.
- Application health/API verification and an end-to-end trip submission.
- The architecture diagram open in diagrams.net.

Add your screenshots to the repository (for example, `docs/screenshots/`) only after checking them for secrets. Update the deployment status table above as each pending item is completed. Push the guide and diagram to your own GitHub repository, then submit a text, Word, or PDF file containing that repository URL through Vlearn.

## Cleanup

After assessment evidence is collected, remove unused resources to avoid ongoing charges. Check EC2 instances, load balancers, target groups, Elastic IPs, NAT gateways, and any storage resources. Keep only the resources you intend to maintain.
