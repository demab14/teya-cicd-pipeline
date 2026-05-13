# Secure CI/CD Pipeline
### GitHub Actions · Docker · AWS ECS Fargate · Terraform

A production-grade DevSecOps pipeline with security embedded at every stage.

## Pipeline
1. SAST & secret scan (Semgrep)
2. IaC scan (Checkov)
3. Container CVE scan + SBOM (Trivy)
4. Push to ECR via OIDC — no stored credentials
5. Deploy to ECS Fargate with manual approval gate

## Security Controls
- OIDC authentication — no static AWS credentials
- Immutable image tags (git SHA)
- ECS tasks in private subnets
- Read-only filesystem + all Linux caps dropped
- SBOM generated per build (PCI-DSS audit trail)
