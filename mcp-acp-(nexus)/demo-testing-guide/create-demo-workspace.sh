#!/bin/bash
# Create demo workspace for testing mcp-acp-nexus

set -e

WORKSPACE="/tmp/mcp-demo-workspace"

echo "Creating demo workspace at $WORKSPACE..."

# Clean up existing
rm -rf "$WORKSPACE"

# Create directory structure
mkdir -p "$WORKSPACE"/{projects/client-portal/{src/components,src/utils,tests,config},projects/internal-api/{src,tests,config}}
mkdir -p "$WORKSPACE"/data/{analytics,fixtures}
mkdir -p "$WORKSPACE"/docs/{adr,meeting-notes}
mkdir -p "$WORKSPACE"/reports
mkdir -p "$WORKSPACE"/documents/{contracts,financial,hr-records}
mkdir -p "$WORKSPACE"/secrets/{api-tokens,certificates,ssh-keys}
mkdir -p "$WORKSPACE"/{backups,logs,tmp}

# ============================================================
# Projects - client-portal (TypeScript frontend)
# ============================================================

cat > "$WORKSPACE/projects/client-portal/src/Dashboard.tsx" << 'EOF'
import React from 'react';
import { Header } from './components/Header';
import { Sidebar } from './components/Sidebar';

export const Dashboard: React.FC = () => {
  return (
    <div className="dashboard">
      <Header />
      <Sidebar />
      <main>
        {/* TODO: Add main content */}
      </main>
    </div>
  );
};
EOF

cat > "$WORKSPACE/projects/client-portal/src/components/Header.tsx" << 'EOF'
import React from 'react';
export const Header: React.FC = () => <header>Client Portal</header>;
EOF

cat > "$WORKSPACE/projects/client-portal/src/components/Sidebar.tsx" << 'EOF'
import React from 'react';
export const Sidebar: React.FC = () => <nav>Navigation</nav>;
EOF

cat > "$WORKSPACE/projects/client-portal/src/utils/api.ts" << 'EOF'
export const fetchData = async (endpoint: string) => {
  const response = await fetch(`/api/${endpoint}`);
  return response.json();
};
EOF

cat > "$WORKSPACE/projects/client-portal/tests/Dashboard.test.tsx" << 'EOF'
import { render } from '@testing-library/react';
import { Dashboard } from '../src/Dashboard';

test('renders dashboard', () => {
  render(<Dashboard />);
});
EOF

cat > "$WORKSPACE/projects/client-portal/config/settings.json" << 'EOF'
{
  "apiEndpoint": "https://api.example.com",
  "theme": "light",
  "features": {
    "darkMode": true,
    "notifications": true
  }
}
EOF

cat > "$WORKSPACE/projects/client-portal/.env.local" << 'EOF'
# DO NOT COMMIT - Local development secrets
API_KEY=sk-demo-12345-fake-key
DATABASE_URL=postgres://user:password@localhost:5432/dev
STRIPE_SECRET=sk_test_fake_stripe_key
EOF

cat > "$WORKSPACE/projects/client-portal/package.json" << 'EOF'
{
  "name": "client-portal",
  "version": "1.0.0",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "test": "vitest"
  }
}
EOF

# ============================================================
# Projects - internal-api (Python backend)
# ============================================================

cat > "$WORKSPACE/projects/internal-api/src/users.py" << 'EOF'
from fastapi import APIRouter

router = APIRouter()

@router.get("/users")
async def list_users():
    return {"users": []}

@router.get("/users/{user_id}")
async def get_user(user_id: str):
    return {"id": user_id, "name": "Demo User"}
EOF

cat > "$WORKSPACE/projects/internal-api/src/auth.py" << 'EOF'
from fastapi import Depends, HTTPException

def verify_token(token: str):
    if not token:
        raise HTTPException(401, "Not authenticated")
    return {"sub": "user123"}
EOF

cat > "$WORKSPACE/projects/internal-api/src/database.py" << 'EOF'
from sqlalchemy import create_engine
engine = create_engine("sqlite:///./test.db")
EOF

cat > "$WORKSPACE/projects/internal-api/tests/test_users.py" << 'EOF'
import pytest
from src.users import router

def test_list_users():
    # Test implementation
    pass
EOF

cat > "$WORKSPACE/projects/internal-api/tests/test_auth.py" << 'EOF'
import pytest
from src.auth import verify_token

def test_verify_token_missing():
    with pytest.raises(Exception):
        verify_token("")
EOF

cat > "$WORKSPACE/projects/internal-api/config/settings.json" << 'EOF'
{
  "debug": false,
  "log_level": "INFO",
  "cors_origins": ["http://localhost:3000"]
}
EOF

cat > "$WORKSPACE/projects/internal-api/config/database.yaml" << 'EOF'
database:
  host: db-prod-replica.internal.acme.com
  port: 5432
  name: internal_api
  user: svc_internal_api
  password: "prod-db-password-rotated-2025-01"
  pool_size: 10
  ssl_mode: require
EOF

cat > "$WORKSPACE/projects/internal-api/package.json" << 'EOF'
{
  "name": "internal-api",
  "version": "2.0.0"
}
EOF

# ============================================================
# Data - analyst files (read-only source data)
# ============================================================

cat > "$WORKSPACE/data/analytics/error_codes_jan2025.csv" << 'EOF'
date,error_code,count,service,severity
2025-01-01,ERR_TIMEOUT,142,api-gateway,high
2025-01-01,ERR_AUTH_FAILED,23,auth-service,medium
2025-01-01,ERR_DB_CONN,8,user-service,critical
2025-01-02,ERR_TIMEOUT,156,api-gateway,high
2025-01-02,ERR_RATE_LIMIT,89,api-gateway,low
2025-01-02,ERR_AUTH_FAILED,31,auth-service,medium
2025-01-03,ERR_TIMEOUT,98,api-gateway,high
2025-01-03,ERR_DB_CONN,12,user-service,critical
2025-01-03,ERR_PARSE,45,data-pipeline,medium
2025-01-04,ERR_TIMEOUT,201,api-gateway,high
2025-01-04,ERR_OOM,3,batch-processor,critical
2025-01-05,ERR_TIMEOUT,167,api-gateway,high
2025-01-05,ERR_AUTH_FAILED,18,auth-service,medium
EOF

cat > "$WORKSPACE/data/analytics/api_latency_jan2025.csv" << 'EOF'
date,endpoint,p50_ms,p95_ms,p99_ms,requests
2025-01-01,/api/users,12,45,120,45230
2025-01-01,/api/orders,34,89,340,12450
2025-01-01,/api/auth/login,8,22,55,8900
2025-01-02,/api/users,14,52,150,47100
2025-01-02,/api/orders,31,78,290,13200
2025-01-03,/api/users,11,41,110,44800
2025-01-03,/api/orders,38,95,380,11900
EOF

cat > "$WORKSPACE/data/fixtures/users.json" << 'EOF'
[
  {"id": "usr_001", "name": "Alice Chen", "email": "alice@example.com", "role": "admin", "created_at": "2024-03-15"},
  {"id": "usr_002", "name": "Bob Martinez", "email": "bob@example.com", "role": "editor", "created_at": "2024-06-01"},
  {"id": "usr_003", "name": "Carol Park", "email": "carol@example.com", "role": "viewer", "created_at": "2024-09-20"}
]
EOF

cat > "$WORKSPACE/data/fixtures/products.json" << 'EOF'
[
  {"id": "prod_001", "name": "Starter Plan", "price_cents": 999, "currency": "USD", "active": true},
  {"id": "prod_002", "name": "Pro Plan", "price_cents": 4999, "currency": "USD", "active": true},
  {"id": "prod_003", "name": "Enterprise", "price_cents": null, "currency": "USD", "active": true}
]
EOF

cat > "$WORKSPACE/data/fixtures/orders.json" << 'EOF'
[
  {"id": "ord_001", "user_id": "usr_001", "product_id": "prod_002", "status": "completed", "total_cents": 4999},
  {"id": "ord_002", "user_id": "usr_002", "status": "pending"},
  {"id": "ord_003", "product_id": "prod_001", "status": "completed", "total_cents": 999}
]
EOF

# ============================================================
# Docs - project documentation (read free, write needs approval)
# ============================================================

cat > "$WORKSPACE/docs/adr/001-api-versioning.md" << 'EOF'
# ADR 001: API Versioning Strategy

## Status
Accepted

## Context
We need a consistent API versioning approach as we scale to multiple clients.

## Decision
Use URL path versioning (`/v1/`, `/v2/`) with a sunset policy of 12 months after deprecation notice.

## Consequences
- All new endpoints must be versioned
- Breaking changes require a new version
- Old versions must remain functional during sunset period
EOF

cat > "$WORKSPACE/docs/adr/002-auth-migration.md" << 'EOF'
# ADR 002: Migration from Session Auth to JWT

## Status
Proposed

## Context
Session-based auth doesn't scale well across our microservices. Each service needs to validate tokens independently.

## Decision
Migrate to JWT with OIDC provider (Auth0). Short-lived access tokens (15 min) with refresh tokens.

## Consequences
- Need to update all service middleware
- Token refresh logic required in frontend
- Enables zero-trust architecture for internal services
EOF

cat > "$WORKSPACE/docs/meeting-notes/2025-01-15-sprint-planning.md" << 'EOF'
# Sprint Planning - January 15, 2025

## Attendees
Alice, Bob, Carol, Dave

## Sprint Goals
1. Complete JWT migration for auth-service
2. Fix timeout issues in api-gateway
3. Set up monitoring dashboards

## Action Items
- Alice: Auth middleware updates (3 points)
- Bob: Gateway timeout investigation (2 points)
- Carol: Grafana dashboard setup (2 points)
- Dave: Load testing for new auth flow (3 points)
EOF

cat > "$WORKSPACE/docs/meeting-notes/2025-01-22-architecture-review.md" << 'EOF'
# Architecture Review - January 22, 2025

## Attendees
Alice, Carol, Dave, VP Engineering

## Topics Discussed

### Database Migration Strategy
- Decided: Move from single PostgreSQL to read replicas
- Timeline: Q2 2025
- Need ADR documenting the decision

### API Rate Limiting
- Current: 1000 req/min global
- Proposed: Per-tenant limits with burst allowance
- Decision: Implement in api-gateway, not per-service

### Observability
- Add distributed tracing (OpenTelemetry)
- Structured logging standard across all services
- Carol to draft logging ADR

## Decisions
1. Database read replicas - APPROVED
2. Per-tenant rate limiting - APPROVED
3. OpenTelemetry adoption - APPROVED, start with api-gateway
EOF

cat > "$WORKSPACE/docs/CHANGELOG.md" << 'EOF'
# Changelog

## [2.1.0] - 2025-01-20
### Added
- Per-tenant rate limiting in api-gateway
- Health check endpoint for all services

### Fixed
- Connection timeout in external API calls
- Memory leak in batch processor

## [2.0.0] - 2025-01-05
### Changed
- Migrated auth from sessions to JWT
- Updated all service middleware for token validation

### Removed
- Legacy session endpoints (deprecated since 1.8.0)
EOF

cat > "$WORKSPACE/docs/onboarding.md" << 'EOF'
# Developer Onboarding

## Getting Started
1. Clone the monorepo
2. Install dependencies: `npm install` in each project
3. Copy `.env.example` to `.env.local` and fill in values
4. Run `docker-compose up` for local services
5. Run tests: `npm test`

## Architecture Overview
- **client-portal**: React frontend, deployed to Vercel
- **internal-api**: FastAPI backend, deployed to AWS ECS
- **api-gateway**: Kong, handles routing and rate limiting

## Key Contacts
- Alice Chen: Tech lead, architecture questions
- Bob Martinez: DevOps, deployment pipeline
- Carol Park: Frontend, design system
EOF

# ============================================================
# Reports - output directory (unrestricted)
# ============================================================

cat > "$WORKSPACE/reports/.gitkeep" << 'EOF'
EOF

# ============================================================
# Documents - sensitive business docs
# ============================================================

cat > "$WORKSPACE/documents/contracts/vendor_agreement_cloudprovider.txt" << 'EOF'
MASTER SERVICE AGREEMENT
========================
CloudProvider Inc. and ACME Corp

Effective Date: January 1, 2025
Term: 3 years with auto-renewal

Services: Cloud infrastructure, compute, storage
Monthly Commitment: $50,000
SLA: 99.9% uptime guarantee

CONFIDENTIAL - Internal Use Only
EOF

cat > "$WORKSPACE/documents/contracts/nda_partner_corp.txt" << 'EOF'
NON-DISCLOSURE AGREEMENT
========================
Between ACME Corp and Partner Corp

Duration: 5 years from signing
Scope: Product roadmap, technical specifications, customer data

STRICTLY CONFIDENTIAL
EOF

cat > "$WORKSPACE/documents/financial/quarterly_report_q4_2024.txt" << 'EOF'
QUARTERLY FINANCIAL REPORT - Q4 2024
====================================

Revenue: $12.5M (+15% YoY)
Operating Expenses: $8.2M
Net Income: $4.3M

Key Metrics:
- ARR: $48M
- Customer Count: 1,250
- Churn Rate: 2.1%

CONFIDENTIAL - Board Distribution Only
EOF

cat > "$WORKSPACE/documents/financial/budget_2025.txt" << 'EOF'
2025 ANNUAL BUDGET
==================

Engineering: $15M
Sales & Marketing: $8M
Operations: $4M
G&A: $3M
Total: $30M

DRAFT - CFO Review Required
EOF

cat > "$WORKSPACE/documents/hr-records/employment_contract_jsmith.txt" << 'EOF'
EMPLOYMENT CONTRACT
===================
Employee: John Smith
Position: Senior Engineer
Start Date: March 15, 2023
Salary: $185,000/year
Equity: 0.05%

HIGHLY CONFIDENTIAL - HR Access Only
EOF

cat > "$WORKSPACE/documents/hr-records/perf_review_2024.txt" << 'EOF'
PERFORMANCE REVIEW 2024
=======================
Employee: John Smith
Manager: Jane Doe
Rating: Exceeds Expectations

Strengths: Technical leadership, mentoring
Areas for Growth: Cross-team collaboration

Recommended: Promotion to Staff Engineer

CONFIDENTIAL
EOF

cat > "$WORKSPACE/documents/hr-records/salary_bands.txt" << 'EOF'
ENGINEERING SALARY BANDS 2025
=============================

Junior Engineer: $90,000 - $120,000
Engineer: $120,000 - $160,000
Senior Engineer: $160,000 - $200,000
Staff Engineer: $200,000 - $250,000
Principal Engineer: $250,000 - $320,000

STRICTLY CONFIDENTIAL - HR/Management Only
EOF

# ============================================================
# Secrets (fake credentials for demo)
# ============================================================

cat > "$WORKSPACE/secrets/api-tokens/anthropic_key.txt" << 'EOF'
sk-ant-api03-FAKE-KEY-FOR-DEMO-PURPOSES-ONLY-xxxxxxxx
EOF

cat > "$WORKSPACE/secrets/api-tokens/github_pat.txt" << 'EOF'
ghp_FakeGitHubPersonalAccessTokenForDemo1234
EOF

cat > "$WORKSPACE/secrets/api-tokens/aws_credentials.txt" << 'EOF'
[default]
aws_access_key_id = AKIAFAKEACCESSKEYID
aws_secret_access_key = FakeSecretAccessKey1234567890abcdef
EOF

cat > "$WORKSPACE/secrets/certificates/server.crt" << 'EOF'
-----BEGIN CERTIFICATE-----
MIIFake...Certificate...ForDemo...Purposes...Only
-----END CERTIFICATE-----
EOF

cat > "$WORKSPACE/secrets/certificates/server.key" << 'EOF'
-----BEGIN PRIVATE KEY-----
MIIFake...PrivateKey...ForDemo...Purposes...Only
-----END PRIVATE KEY-----
EOF

cat > "$WORKSPACE/secrets/certificates/ca-bundle.pem" << 'EOF'
-----BEGIN CERTIFICATE-----
MIIFake...CABundle...ForDemo...Purposes...Only
-----END CERTIFICATE-----
EOF

cat > "$WORKSPACE/secrets/ssh-keys/id_ed25519" << 'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
FakePrivateKeyForDemoPurposesOnlyDoNotUse
-----END OPENSSH PRIVATE KEY-----
EOF

cat > "$WORKSPACE/secrets/ssh-keys/id_ed25519.pub" << 'EOF'
ssh-ed25519 AAAAC3FakePublicKeyForDemo user@demo
EOF

cat > "$WORKSPACE/secrets/ssh-keys/deploy_key" << 'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
FakeDeployKeyForCICDPipeline
-----END OPENSSH PRIVATE KEY-----
EOF

# ============================================================
# Backups
# ============================================================

cat > "$WORKSPACE/backups/users_backup_20250110.json" << 'EOF'
{
  "backup_date": "2025-01-10T00:00:00Z",
  "users": [
    {"id": 1, "email": "admin@example.com", "password_hash": "$2b$12$FakeHashedPassword"},
    {"id": 2, "email": "user@example.com", "password_hash": "$2b$12$AnotherFakeHash"}
  ]
}
EOF

cat > "$WORKSPACE/backups/database_dump_20250115.sql" << 'EOF'
-- Database backup 2025-01-15
-- Contains sensitive customer data

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255),
    password_hash VARCHAR(255)
);

INSERT INTO users VALUES (1, 'admin@example.com', '$2b$12$...');
EOF

echo "Backup archive placeholder" > "$WORKSPACE/backups/config_backup_20250118.tar.gz"

# ============================================================
# Logs
# ============================================================

cat > "$WORKSPACE/logs/app.log" << 'EOF'
2025-01-18 10:00:00 INFO  Application started
2025-01-18 10:00:01 INFO  Connected to database
2025-01-18 10:00:05 INFO  User login: user@example.com
2025-01-18 10:01:00 WARN  High memory usage detected
2025-01-18 10:02:00 INFO  Request processed in 150ms
EOF

cat > "$WORKSPACE/logs/error.log" << 'EOF'
2025-01-18 09:30:00 ERROR Connection timeout to external API
2025-01-18 09:45:00 ERROR Failed to parse JSON response
EOF

cat > "$WORKSPACE/logs/access.log" << 'EOF'
192.168.1.100 - - [18/Jan/2025:10:00:00] "GET /api/users HTTP/1.1" 200
192.168.1.101 - - [18/Jan/2025:10:01:00] "POST /api/login HTTP/1.1" 200
EOF

# ============================================================
# Temp workspace
# ============================================================

cat > "$WORKSPACE/tmp/scratch.txt" << 'EOF'
Temporary scratch file for experiments
EOF

cat > "$WORKSPACE/tmp/notes.md" << 'EOF'
# Notes
- Work in progress
- Safe to modify
EOF

echo ""
echo "Demo workspace created at $WORKSPACE"
echo ""
echo "Directory structure:"
find "$WORKSPACE" -type f | sort | head -50
echo "..."
echo ""
echo "Total files: $(find "$WORKSPACE" -type f | wc -l | tr -d ' ')"
echo ""
echo "To clean up: rm -rf $WORKSPACE"
