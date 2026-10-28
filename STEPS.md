# STEPS: CI/CD Pipeline in a Box

## Prerequisites (set these up BEFORE step 1)

| Need | Details |
|---|---|
| **AWS account** | Any account that can launch EC2. No IAM role, no other AWS service. Pick one region and use it for everything below. |
| **Instance type** | `m7i-flex.large` (2 vCPU, 8 GiB). This project needs only about 1 GiB, so smaller also works, but use this one for demos. |
| **OS image (AMI)** | Ubuntu Server 24.04 LTS (64-bit x86). 22.04 also works. |
| **Disk** | 25 GiB gp3 (the default 8 GiB is too small for Docker images). |
| **Key pair** | An RSA `.pem` key pair created in EC2 (step 0a). |
| **Security group** | Created in step 0b. **Inbound: exactly one rule, SSH (TCP port 22) from My IP.** Do NOT open ports 3000, 5000, 8081 or 8082; everything binds to localhost and you reach it through an SSH tunnel. **Outbound: leave the default (All traffic, 0.0.0.0/0)**, because the instance must reach Docker Hub, Ubuntu's apt mirrors and Docker's apt repo. |
| **Code on the instance** | Option A: private GitHub repo plus a fine-grained token (Contents: Read) used as the password for `git clone`. Option B: copy the zip with `scp` (step 2). |
| **Accounts / tokens** | None else. No Docker Hub login needed, but a free one helps if pulls get rate-limited (see troubleshooting). |
| **On your laptop** | A terminal with `ssh`/`scp` and a web browser (to watch Gitea through the tunnel). |

**Time:** about 10 minutes of setup, 3 minutes for the first pipeline run, 6-8 minutes for the full demo. **Cost:** the instance is about $0.10/hour at your quoted rate, plus pennies for the disk. Do step 12 when finished.

---

## Step 0: Create the key pair, security group and instance (AWS console)

**0a. Key pair.** EC2 > Network & Security > Key pairs > **Create key pair**. Name `cicd-box-key`, type **RSA**, format **.pem**. The file downloads once; keep it safe. On your laptop, lock down its permissions:

```bash
# Linux / macOS
chmod 400 ~/Downloads/cicd-box-key.pem
```
```powershell
# Windows PowerShell (OpenSSH)
icacls "$HOME\Downloads\cicd-box-key.pem" /inheritance:r /grant:r "$($env:USERNAME):(R)"
```

**0b. Security group.** EC2 > Network & Security > Security Groups > **Create security group**.
- Name: `cicd-box-sg`, Description: `SSH only`, VPC: the default VPC.
- **Inbound rules > Add rule:** Type `SSH`, Protocol `TCP`, Port range `22`, Source `My IP`.
- **Outbound rules:** leave the default rule (Type `All traffic`, Destination `0.0.0.0/0`).
- Create the group.

**0c. Launch the instance.** EC2 > Instances > **Launch instances**.
- Name: `cicd-box`
- Application and OS Image: **Ubuntu**, choose **Ubuntu Server 24.04 LTS**, architecture **64-bit (x86)**
- Instance type: `m7i-flex.large`
- Key pair: `cicd-box-key`
- Network settings > **Edit**: Auto-assign public IP **Enable**; Firewall: **Select existing security group** > `cicd-box-sg`
- Configure storage: **25 GiB**, `gp3`
- Advanced details > IAM instance profile: leave as **No IAM role**
- Click **Launch instance**, wait until Instance state is `Running` and Status check is `2/2 passed`, then copy the **Public IPv4 address**.

> If your home or phone network changes later, SSH will time out because "My IP" no longer matches. Edit the security group's inbound rule and set Source to My IP again.

## Step 1: Connect to the instance (from your laptop)

```bash
ssh -i ~/Downloads/cicd-box-key.pem ubuntu@<PUBLIC-IP>
```
Type `yes` at the fingerprint prompt. Every command from here to step 8 runs **on the instance**.

## Step 2: Update packages and get the code

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git unzip
```

**Option A (private GitHub repo):**
```bash
git clone https://github.com/<you>/cicd-pipeline-in-a-box.git
cd cicd-pipeline-in-a-box
```
When asked, username = your GitHub username, password = the fine-grained token.

**Option B (no GitHub), run from your laptop in the folder holding the zip, then continue on the instance:**
```bash
# on your laptop
scp -i ~/Downloads/cicd-box-key.pem cicd-pipeline-in-a-box.zip ubuntu@<PUBLIC-IP>:~
# on the instance
unzip cicd-pipeline-in-a-box.zip
cd cicd-pipeline-in-a-box
```

## Step 3: Make the scripts executable (do not skip)

Files that were zipped, uploaded to GitHub or copied between systems often lose their "executable" flag. Without this you get `Permission denied`.

```bash
chmod +x scripts/*.sh sample-app/deploy/*.sh
ls -l scripts/        # every .sh line should start with -rwxr-xr-x
```

## Step 4: Install Docker and Compose

```bash
./scripts/setup.sh
```
It runs `apt update`/`upgrade`, installs `curl git gnupg openssl python3 unzip`, installs Docker Engine and Compose v2 from Docker's official repo (falling back to Ubuntu's `docker.io` package if that repo is unreachable), starts Docker and prints the versions. Takes 3-5 minutes. It ends with `Setup complete.`

## Step 5: Unit tests

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
(cd sample-app && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v)
```
Both end with `OK`. (The first checks this repo's layout, the second tests the app. One test is skipped if PyYAML is absent; that is fine.)

## Step 6: Preflight (run this well before the demo)

```bash
./scripts/preflight.sh
```
Pulls every image, builds the runner image and runs the tests. Every line must say `ok`, and the last line is `Preflight passed. Safe to run ./scripts/up.sh`. First run takes 3-5 minutes.

## Step 7: Start the platform

```bash
./scripts/up.sh
```
Starts Gitea and the registry, creates the `demo` admin user, registers the runner, creates the `demo/hello-app` repo and pushes the first commit, which starts the first pipeline run. Takes about 2 minutes. It prints the login and the URLs. The password is random and saved in `.env`:

```bash
grep DEMO_PASSWORD .env
```

## Step 8: Health check

```bash
./scripts/smoke.sh
```
Waits (up to 5 minutes) for the first pipeline run, then checks everything. Every line says `ok` and it ends with **`All 12 checks passed.`**

## Step 9: Watch it live (on your LAPTOP, in a new terminal; keep it open)

```bash
ssh -i ~/Downloads/cicd-box-key.pem \
  -L 3000:localhost:3000 -L 8081:localhost:8081 -L 5000:localhost:5000 \
  ubuntu@<PUBLIC-IP>
```
- Gitea: http://localhost:3000 (login `demo` and the password from step 7)
- Pipeline runs: http://localhost:3000/demo/hello-app/actions
- Live app: http://localhost:8081
- Registry tags: http://localhost:5000/v2/hello-app/tags/list

If a local port is already in use, change the left number, for example `-L 3001:localhost:3000`, and browse to port 3001.

## Step 10: Run the demo (on the instance)

```bash
./scripts/demo.sh good          # version bump: green pipeline, new version live (about 1 min)
./scripts/demo.sh bad-test      # broken test: pipeline fails at step 2, old version keeps serving
./scripts/demo.sh bad-health    # tests pass but container is broken: deploy blocked at step 5
./scripts/demo.sh all           # all three, about 6-8 minutes
```
Keep the Actions page open in your browser while it runs. Each scenario prints `pipeline result: ... (expected: ...)` and ends with an `ok` line. In the final `bad-health` run, open the failed run in Gitea and expand step 5 to show `Deploy BLOCKED. The previous version is still serving`.

You can also trigger a run by hand: in Gitea open `demo/hello-app`, edit `app/main.py` with the web editor, change `VERSION`, commit to `main`, and watch the Actions tab.

## Step 11: Useful commands

```bash
sudo docker compose ps                     # the three platform containers
sudo docker ps                             # also shows the deployed hello-app
sudo docker compose logs --tail 30 runner  # runner log
curl -s localhost:8081                     # live app JSON (version and commit)
```

## Step 12: Clean up, then terminate the instance

```bash
./scripts/destroy.sh
```
Then in the AWS console: EC2 > Instances > select `cicd-box` > **Instance state > Terminate instance**. Optionally delete the `cicd-box-sg` security group and `cicd-box-key` key pair too.

---

## What you should see

| Step | Result |
|---|---|
| 5 | Both test runs end with `OK` |
| 6 | All `ok`, then `Preflight passed.` |
| 7 | `Stack is up.` with the login |
| 8 | `All 12 checks passed.` |
| 9/10 | Pipeline runs with 7 steps, green for `good`; red at step 2 for `bad-test`; red at step 5 for `bad-health` |

## Risky dependencies and fallbacks

| Dependency | Risk | Fallback |
|---|---|---|
| Docker Hub images (`gitea/gitea`, `registry`, `gitea/act_runner`, `docker`, `python`) | Rate limit or a withdrawn tag | `sudo docker login` with a free account, or change the tag in `.env` (e.g. `RUNNER_BASE_IMAGE=gitea/act_runner:latest`) and re-run `./scripts/preflight.sh` |
| `download.docker.com` (Docker apt repo) | Unreachable | `setup.sh` falls back to Ubuntu's `docker.io` automatically |
| Alpine package mirror (used while building the runner image) | Unreachable | Re-run preflight; check outbound rule |
| github.com, PyPI | **Not used** | none needed |

## If something goes wrong

| Symptom | Fix |
|---|---|
| SSH: `Connection timed out` | Your IP changed. Edit security group `cicd-box-sg` inbound rule: SSH, port 22, Source My IP. Also confirm the instance has a public IP and is Running. |
| SSH: `Permission denied (publickey)` | Use user `ubuntu` (not `ec2-user`), the right `.pem`, and `chmod 400` on it. |
| SSH: `UNPROTECTED PRIVATE KEY FILE` | `chmod 400 cicd-box-key.pem` |
| `./scripts/x.sh: Permission denied` | `chmod +x scripts/*.sh sample-app/deploy/*.sh` (step 3). Or run with `bash scripts/x.sh`. |
| `bad interpreter: /usr/bin/env bash^M` | Windows line endings. Run `sed -i 's/\r$//' scripts/*.sh sample-app/deploy/*.sh` |
| `permission denied` on the Docker socket | The scripts use `sudo` for you. For manual commands use `sudo docker ...`, or log out and back in once. |
| Preflight: image pull fails | `sudo docker login` (free account) and re-run, or change the tag in `.env`. Check the outbound rule is All traffic. |
| Preflight: `Port 3000 is free` fails | `sudo ss -ltnp \| grep -E ':(3000\|5000\|8081\|8082)'`, stop what uses it, or `./scripts/destroy.sh` if it is an old run of this project. |
| `up.sh`: Gitea did not answer | `sudo docker compose logs --tail 40 gitea` |
| Smoke: `Runner registered with Gitea` fails | `sudo docker compose logs --tail 40 runner`. If the token was rejected: `./scripts/destroy.sh` then `./scripts/up.sh`. |
| Pipeline stays `waiting` / never starts | Runner offline. In Gitea: Site Administration (top-right menu) > Actions > Runners should show `box-runner` as Idle. Else check the runner log. |
| Repo has no Actions tab | Repo > Settings > Advanced Settings > tick **Enable Repository Actions** > Update. |
| Pipeline fails at step 1 (clone) | `curl -s localhost:3000/api/healthz` on the instance should return `pass`. |
| Pipeline fails with `docker: command not found` or socket error | Run `./scripts/preflight.sh` (checks the runner image) and `sudo docker compose up -d --build runner`. |
| Live app missing on :8081 | `sudo docker ps -a`, then read step 5 of the pipeline run in Gitea. |
| Disk full | `sudo docker system prune -af` |
| Tunnel: `bind: Address already in use` | Use another local port, e.g. `-L 3001:localhost:3000`. |
