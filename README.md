# team4-aiops — AWS AI 기반 인프라 운영·비용 분석 플랫폼

AWS 워크로드의 메트릭·로그·비용·구성 데이터를 통합 수집·분석하고, Amazon Bedrock Agent로 자연어 질의응답·자동 리포트·실시간 알림을 제공하는 운영 자동화 플랫폼.

- 리포지토리: [Kjihoo/aws-aiops-platform](https://github.com/Kjihoo/aws-aiops-platform)
- AWS 계정 ID: `089955620282`
- 리전: `ap-northeast-2` (서울)
- project_name: `team4-aiops`

## W1 산출물 (현재 상태)

- 모노레포 디렉터리 구조
- Terraform bootstrap (state 백엔드 S3 + DynamoDB lock)
- network 모듈 (VPC, 퍼블릭/프라이빗 서브넷 2쌍, IGW, NAT)
- GitHub Actions: `infra-plan` (PR), `infra-apply` (main, OIDC)
- pre-commit 훅

## 기술 스택

- AWS / Terraform 1.7+ / GitHub Actions
- 컴퓨트: ECS Fargate, Lambda
- DB: RDS PostgreSQL 16, DynamoDB
- 데이터 레이크: S3 + Glue + Athena
- AI: Amazon Bedrock (Claude)
- 언어: Python 3.12 + FastAPI, React 18 + Vite

## 디렉터리 구조

- `infrastructure/`: Terraform IaC
  - `bootstrap/`: state 백엔드 1회성 부트스트랩 (local backend)
  - `environments/dev/`: dev 환경 root module (S3 backend)
  - `modules/`: 재사용 가능한 Terraform 모듈
- `apps/`: 샘플 워크로드 (api-gateway, data-ingestion, query-service, frontend)
- `platform/`: 운영 플랫폼 (Lambda, Glue, Grafana 대시보드)
- `docs/`: 아키텍처 문서·ADR·런북
- `.github/workflows/`: CI/CD

## 빠른 시작

### 사전 준비 (최초 1회, 수동)

1. **AWS GitHub OIDC IAM Role** 을 별도로 생성하고 ARN 확보
   - Trust policy의 `sub` 조건은 `repo:Kjihoo/aws-aiops-platform:*` 패턴 사용
   - 권한은 W1 단계에서는 VPC/IAM/S3/DynamoDB 관리에 필요한 범위
2. GitHub 리포지토리 `Settings → Secrets and variables → Actions` 에
   - `AWS_ROLE_TO_ASSUME` = 위에서 만든 Role ARN
3. GitHub 리포지토리 `Settings → Environments` 에 `production` 환경 생성 후 필수 reviewer 지정 (apply 승인 게이트)

### 1. Bootstrap — state 백엔드 생성 (로컬에서 1회)

```powershell
cd infrastructure/bootstrap
terraform init
terraform apply
```

생성되는 리소스:
- S3 버킷: `team4-aiops-tfstate-089955620282` (버전관리·암호화·퍼블릭 차단)
- DynamoDB: `team4-aiops-tflock` (state lock)

### 2. dev 환경 init/plan

```powershell
cd infrastructure/environments/dev
terraform init
terraform plan
```

### 3. CI/CD

- PR 이 `infrastructure/**` 를 변경하면 `infra-plan.yml` 이 실행되어 plan 결과를 PR 코멘트로 첨부
- `main` 에 merge 되면 `infra-apply.yml` 이 실행되며 `production` 환경 승인 후 apply

## 공통 태그 규칙

`Project`, `Environment`, `ManagedBy` 는 provider `default_tags` 로 자동 적용. 각 모듈은 `Service` 와 리소스별 `Name` 만 추가 부여.

## 주의 사항 (CLAUDE.md 발췌)

- 모호한 부분은 추측 금지, 질문 우선
- 하드코딩 ARN/계정 ID 금지 (variables / data source 사용)
- AWS 자격증명은 OIDC 기반 IAM Role assume — 액세스 키 직접 사용 금지
- 시크릿은 AWS Secrets Manager / Parameter Store, 일반 설정은 Terraform 변수
