# EC2 deployment with GitHub Actions

The repository includes CI in `.github/workflows/verify.yml` and CD in `.github/workflows/deploy.yml`. A successful CI run for a push to `main` triggers CD when the repository variable `DEPLOY_ENABLED` is `true`. CD builds on GitHub, publishes commit-tagged images to Amazon ECR, and updates one EC2 instance through Systems Manager. There is no SSH key or permanent AWS access key in GitHub.

The pipeline has been prepared and locally checked, but has not deployed to your AWS account. Complete the following setup once.

## 1. Create the AWS resources

Use one region, for example `ap-south-1`.

- Launch **Ubuntu Server 24.04 LTS, x86_64**. The pipeline builds amd64 images; do not select a Graviton/ARM instance without adding multi-platform image builds. A `t3.small` gives more headroom than a 1 GB `t3.micro`. A micro can be used for initial testing; measure memory and concurrent usage before admitting 2,000 students.
- Start with an encrypted 20–30 GB gp3 disk. Enable IMDSv2. Give the instance outbound internet access.
- Attach a stable public address and point your domain's DNS A record at it.
- Security group: allow TCP 80 and 443 inbound. No public database or API port is needed. Use Session Manager instead of opening SSH for CI.
- Create private ECR repositories named **hostelcc-server** and **hostelcc-web**, with immutable tags and scanning enabled.
- Create a private S3 bucket for deployment bundles, with public access blocked and SSE-S3 encryption enabled. Use a name such as `hostelcc-deploy-YOUR_ACCOUNT_ID`. Keep it in the same region.

This stack is not guaranteed to be free. Check your account's credits and eligibility, including disk, public IPv4, ECR and S3 charges, and create an AWS Budget alert. [AWS EC2 free-tier guidance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html).

## 2. Give EC2 its instance role

Create an EC2 IAM role and attach:

- `AmazonSSMManagedInstanceCore`
- `AmazonEC2ContainerRegistryReadOnly`
- A custom policy allowing `s3:GetObject` on `arn:aws:s3:::YOUR_BUCKET/releases/*`.

Attach the role to the instance. Confirm the instance appears **Online** in Systems Manager, then open **Session Manager → Start session**. Ubuntu images often include the agent; check `sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service`. [AWS instance-permission setup](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-permissions.html).

## 3. Prepare the instance

Install Docker Engine and the Compose plugin using the [official Ubuntu instructions](https://docs.docker.com/engine/install/ubuntu/). Install [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html). The instance role supplies AWS credentials; do not run `aws configure` with personal access keys.

Verify:

```sh
sudo docker version
sudo docker compose version
aws --version
sudo aws sts get-caller-identity
sudo install -d -m 700 /opt/hostelcc /opt/hostelcc/backups
sudo install -m 600 /dev/null /opt/hostelcc/.env.deploy
sudo nano /opt/hostelcc/.env.deploy
```

Run the `install ... /dev/null` command only for the first setup; it would empty an existing configuration. Fill the file using `.env.example` from this repository:

```dotenv
SITE_DOMAIN=hostel.example.edu
SITE_PORT=8080
ADMIN_EMAIL=your-admin@example.edu
ALLOWED_ORIGINS=https://hostel.example.edu
HOSTELCC_DB_PASSWORD=REPLACE_WITH_RANDOM_SECRET
JWT_SECRET=REPLACE_WITH_RANDOM_SECRET
SMTP_HOST=smtp.your-provider.example
SMTP_PORT=587
SMTP_AUTH=true
SMTP_STARTTLS=true
SMTP_USERNAME=your-smtp-username
SMTP_PASSWORD='your-provider-app-password'
SMTP_FROM=hostel@example.edu
OTP_IP_LIMIT=300
```

Use two independently generated secrets (`openssl rand -hex 32`). Keep the environment file on EC2 only. Single-quote values containing `$` or `#` according to Compose environment-file syntax. Bootstrap creates `ADMIN_EMAIL` only when the database is empty; it does not rename an existing administrator. Admin sign-in remains OTP-only.

The production stack requires SMTP with STARTTLS on port 587 and a verified sender. Do not add the local or test Compose overrides to the EC2 deployment. `110606` works only in the explicitly enabled localhost development mode.

## 4. Create the GitHub AWS role

Add the GitHub OIDC provider in AWS IAM:

- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

Create a role named, for example, `HostelCCGitHubDeploy`. Its trust policy must restrict access to this repository's **production** environment:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {"StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:kmahesh110606/HostelCC:environment:production"
    }}
  }]
}
```

Give this role the policy in [deploy/github-aws-policy.json](deploy/github-aws-policy.json), replacing `YOUR_REGION`, `YOUR_ACCOUNT_ID`, `YOUR_INSTANCE_ID` and `YOUR_BUCKET`. It grants ECR publishing, bundle uploads and SSM commands to the selected instance. `ssm:GetCommandInvocation` and ECR authentication require wildcard resources. [GitHub's AWS OIDC instructions](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

## 5. Configure GitHub

In **Settings → Environments**, create `production`. Restrict deployment branches to `main`. Optionally require your approval before each deployment. Protect `main` with pull requests and passing CI.

In **Settings → Secrets and variables → Actions → Variables**, add these repository variables:

| Variable | Value |
| --- | --- |
| `DEPLOY_ENABLED` | `true` after all setup is complete; use `false` to pause CD |
| `AWS_REGION` | e.g. `ap-south-1` |
| `AWS_DEPLOY_ROLE_ARN` | ARN of `HostelCCGitHubDeploy` |
| `EC2_INSTANCE_ID` | Your `i-...` instance ID |
| `DEPLOY_BUCKET` | Private S3 bucket name |
| `PUBLIC_API_URL` | `https://hostel.example.edu/api` |

The website includes a signed Android APK built for that public API URL. Generate and retain your release keystore using the instructions in `hostelCC-app/android/key.properties.example` and Android tooling. Add these **production environment secrets**:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded keystore file |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Key password |
| `ANDROID_KEY_ALIAS` | Signing alias |

Create the key on your own machine, answering the password prompts:

```sh
keytool -genkeypair -v -keystore hostelcc-release.jks -alias hostelcc -keyalg RSA -keysize 2048 -validity 10000
```

On Windows, copy the base64 value directly to the clipboard, then paste it into the GitHub secret:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path ./hostelcc-release.jks))) | Set-Clipboard
```

Keep a separate secure backup of the keystore and passwords: app updates need the same signing key. Never commit the keystore, decoded base64 or `key.properties`.

## 6. Deploy

Push to `main` or merge a reviewed pull request. Watch **Actions → Verify HostelCC**, then **Deploy HostelCC to EC2**. If you enabled CD after the last push, rerun CI for the latest `main` commit.

The deployment:

1. Confirms CI passed and the commit is still the latest `main`.
2. Builds the signed APK, Java JAR and Docker images on GitHub.
3. Pushes immutable commit tags and uploads the Compose bundle.
4. Uses SSM to run `deploy/ec2-deploy.sh` on EC2.
5. Takes a database backup when an existing database is running.
6. Applies migrations, starts containers, and checks readiness.
7. Checks public HTTPS and APK availability.

Open `https://YOUR_DOMAIN`, request an OTP and verify actual email delivery. Check a student and staff workflow on a physical device before inviting users. The iOS button stays disabled.

The instance keeps configuration in `/opt/hostelcc/.env.deploy`, releases in `/opt/hostelcc/releases/`, backups in `/opt/hostelcc/backups/`, and the last successfully started release SHA in `/opt/hostelcc/current-release`. Docker's project name is always `hostelcc`, so database and certificate volumes persist across releases.

## Updates, failures and recovery

Normal updates are another push to `main`. Re-running a failed deployment reuses existing immutable images for that SHA; change the commit if you change the public APK URL or signing inputs.

If CD fails, inspect its GitHub log and the SSM command's output. The script does not erase the database or automatically roll back migrations. The old successful-release marker is retained if container readiness fails. Use the pre-deployment dump and the previous image tags for a deliberate recovery after assessing migration compatibility. See [DEPLOYMENT.md](DEPLOYMENT.md) for restore instructions.

Backups currently stay on the instance: arrange an encrypted off-instance copy and test restoring it. The scheduled backup service expires database/report files after the configured retention period. Monitor disk space and remove old unused images/releases deliberately; do not delete Docker volumes. A single EC2 instance has downtime during updates and is not a highly available deployment.
