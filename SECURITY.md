# Security Policy

## Reporting a Vulnerability

Do not report security vulnerabilities through public issues or pull requests.

Use GitHub private vulnerability reporting when it is enabled for the affected repository. If private reporting is not enabled, contact the repository maintainers through a private channel and include only the minimum detail required to start triage.

## Sensitive Data

Never commit:

- AWS access keys
- GitHub personal access tokens
- kubeconfig files
- Terraform state
- Private keys
- `.env` files containing secrets
- Kubernetes Secret manifests containing real values

If sensitive information is committed, revoke or rotate it immediately. Removing it from the latest commit is not sufficient because it may remain in Git history.

## Supported Scope

This project is a learning platform. Security reports should focus on repository content, insecure examples, leaked sensitive data, unsafe IAM guidance or workflows that could expose credentials.
