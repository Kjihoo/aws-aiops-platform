# AWS AI 기반 인프라 운영·비용 분석 및 리포트 자동화 플랫폼

## 프로젝트 개요

AWS에서 운영 중인 워크로드의 메트릭·로그·비용·구성 데이터를 통합 수집·분석하고, Amazon Bedrock Agent로 운영자에게 자연어 질의응답·자동 리포트·실시간 알림을 제공하는 운영 자동화 플랫폼.

## 아키텍처 레이어

1. 운영 대상 워크로드: 샘플 ECS Fargate 서비스 + CloudFront + S3 정적 웹 + RDS PostgreSQL
2. 데이터 수집·저장: CloudWatch, Cost Explorer/CUR, AWS Config, Resource Tagging → S3 Data Lake + Glue + Athena + DynamoDB
3. 시각화·AI·알림: Grafana, QuickSight, Amazon Bedrock Agent, Slack 알림, 자동 리포트
4. 자동화·배포·IaC: Terraform + GitHub Actions + OIDC

## W1 목표

- 모노레포 초기 셋업
- Terraform 백엔드 부트스트랩 준비
- Network 모듈 작성
- GitHub Actions infra-plan / infra-apply 작성

## 주의 사항

- 모호한 부분은 추측하지 않고 질문
- 하드코딩 ARN/계정 ID 금지
- Terraform 리소스에는 `Project`, `Environment`, `ManagedBy` 태그 필수
- AWS 자격증명은 OIDC 기반 IAM Role assume 사용
