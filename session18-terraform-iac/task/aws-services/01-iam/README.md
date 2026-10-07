# Session 18 - AWS Services - IAM

- **Name:** Netram
- **Enrollment No:** 24BCS10329

> Category: **Governance**. IAM decides who can call which AWS API, on which resource, and under which conditions.

---

## What is IAM

IAM (Identity and Access Management) is the checkpoint every AWS request passes through. Whether a call comes from the console, the CLI, Terraform or an SDK, it is signed with credentials. IAM works out *who* signed it (authentication) and then whether any policy allows *that exact action on that exact resource* (authorization).

Three properties shaped how I think about it:

- **It is global.** Users, roles and policies are not tied to a region. A role I create while my CLI points at `ap-south-1` works in every region.
- **It is free.** There is no cost reason to share one powerful identity between people or between apps.
- **The default answer is "no".** A brand new user or role can do nothing until a policy allows it. Security in AWS is mostly about deciding what to *add*, not what to take away.

Every account also has a **root user** (the sign-up email address). It has full access that identity policies cannot restrict, and AWS now enforces MFA on root users for all account types (rolled out across 2024-2025). I treat root as a break-glass identity: used only for the few tasks that require it, such as closing the account or changing some billing settings.

## Users

An IAM user is a **long-lived identity** in one account. It can have a console password and up to two access keys (an access key ID plus a secret) for the CLI and SDKs.

The problem is the word *long-lived*. An access key works until someone deletes it, so a key pasted into a `.env` file, a CI variable or a git commit is a standing invitation. That is why AWS now recommends that **humans** sign in through IAM Identity Center (SSO), which hands out short-lived credentials (`aws configure sso` on the CLI), and that **workloads** use roles instead of access keys.

IAM users still make sense for the rare tool that can only accept a static key. For this session I point Terraform at LocalStack with dummy credentials, so no real IAM user is involved at all.

## Groups

A group is a **collection of users that share permissions**. Policies are attached to the group, and every member inherits them.

Why bother: onboarding becomes "add to group", offboarding becomes "remove from group", and two developers can never quietly drift into having different permissions.

| Group | Policy attached | Who goes in it |
|---|---|---|
| `Admins` | `AdministratorAccess` plus a deny-without-MFA policy | One or two leads |
| `Developers` | A customer managed policy scoped to dev resources | Engineers |
| `ReadOnly` | `ReadOnlyAccess` | Auditors, new joiners |
| `Billing` | `job-function/Billing` | Finance |

```bash
aws iam create-group --group-name ReadOnly
aws iam attach-group-policy --group-name ReadOnly --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
aws iam add-user-to-group --group-name ReadOnly --user-name netram
```

Limits worth knowing: groups **cannot contain other groups**, a user can belong to at most 10 groups, and a group is **not a principal**. You cannot name a group in a bucket policy or let a group assume a role directly.

## Roles

A role is an identity with permissions but **no permanent credentials**. Something *assumes* the role through AWS STS and receives temporary credentials (access key, secret and session token) that expire, by default after one hour and configurable up to 12 hours.

A role always has two halves: a **trust policy** (*who* may assume it) and **permissions policies** (*what* it can do once assumed). This trust policy lets EC2 instances assume a role:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

Who assumes roles in practice: AWS services (EC2 through an *instance profile*, Lambda, ECS tasks), users or roles from the same or another account, and federated identities (SAML, or OIDC providers such as GitHub Actions). Identity Center permission sets are also roles under the hood.

Why roles are the default for workloads: there is nothing long-term to leak, rotation is automatic, and the SDKs find the credentials on their own (from the instance metadata service on EC2), so no secret ever lands in code.

## Policies

A policy is a **JSON document** listing what is allowed or denied.

| Element | Meaning |
|---|---|
| `Version` | Policy language version. Always `"2012-10-17"`; it is not a date you update. |
| `Statement` | One or more rules. |
| `Sid` | Optional label for the statement. |
| `Effect` | `Allow` or `Deny`. |
| `Principal` | Who the rule applies to. Only in resource-based policies and trust policies. |
| `Action` | API actions, for example `s3:GetObject`. Wildcards allowed. |
| `Resource` | ARNs the actions apply to. |
| `Condition` | Optional extra checks: source IP, MFA, tags, TLS, region and so on. |

Policy types, from most to least common:

| Type | Attached to | Grants access? | Typical use |
|---|---|---|---|
| Identity-based (AWS managed, customer managed, inline) | User, group, role | Yes | Normal permissions |
| Resource-based | A resource: S3 bucket, KMS key, SQS queue, role trust policy | Yes (names a `Principal`) | Cross-account and service access |
| Permissions boundary | User or role | No, sets a ceiling | Let teams create roles without escalating |
| SCP / RCP (AWS Organizations) | Account or OU | No, sets a ceiling | Org-wide guardrails |
| Session policy | Passed when assuming a role | No, narrows the session | Per-session scoping |

Between AWS managed and customer managed, I default to **customer managed**: they are reusable, IAM keeps up to five versions so a bad change can be rolled back, and I control exactly what is in them. AWS managed policies are a fine start but are usually broader than one app needs. Inline policies only make sense when the policy must live and die with exactly one identity.

## Permissions

Permissions are the *result* of all the policies that apply to a request. IAM evaluates them in a fixed order:

1. Every request starts as an **implicit deny**.
2. If **any** applicable policy has an explicit `Deny` that matches, the answer is deny. Nothing overrides it.
3. Otherwise the request needs an explicit `Allow` from an identity-based or resource-based policy.
4. Every guardrail in play (SCP/RCP, permissions boundary, session policy) must also allow it.

So effective permissions are what the identity policies allow, **trimmed** by every guardrail, **minus** any explicit deny. For cross-account access both sides must agree: the caller's identity policy and the resource's policy in the other account. Explicit deny is also what makes guardrails reliable. A `Deny` on `aws:RequestedRegion` outside `ap-south-1`, or a bucket policy that denies non-TLS requests, holds even if someone later attaches `AdministratorAccess`.

I can check a policy without guessing by asking the policy simulator:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT_ID:role/session18-app-role \
  --action-names s3:GetObject s3:DeleteObject \
  --resource-arns arn:aws:s3:::netram-session18-demo/uploads/report.csv
```

## Least privilege

Least privilege means **granting only the actions, on only the resources, that a principal actually needs**. The reason is blast radius: credentials leak eventually, and when they do, the damage is capped by what they were allowed to do.

An app that uploads and reads files under `uploads/` in one bucket gets this, and nothing more:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListOnlyUploadsPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::netram-session18-demo",
      "Condition": { "StringLike": { "s3:prefix": ["uploads/*"] } }
    },
    {
      "Sid": "ReadWriteUploadsObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::netram-session18-demo/uploads/*"
    }
  ]
}
```

Details that matter here: `ListBucket` is a *bucket* action, so its resource is the bucket ARN, while `GetObject`/`PutObject` are *object* actions on `bucket/key` ARNs. Mixing these up is the most common reason a "correct looking" S3 policy fails. There is also no `s3:DeleteObject`, so even a compromised app cannot delete objects (it could still overwrite them with `PutObject`, which is where versioning helps).

How I would get there in practice: start from an AWS managed policy in a sandbox, then use IAM Access Analyzer to **generate a policy from the CloudTrail activity** of that role, and use **last accessed** data to remove services the role never touched.

## IAM best practices

1. **Federate humans, use roles for workloads.** Temporary credentials expire on their own; static keys do not.
2. **MFA everywhere**, phishing-resistant (passkeys or security keys) for admins. Up to 8 MFA devices can be registered per user.
3. **Lock away the root user.** No access keys, MFA on, used only for root-only tasks.
4. **Least privilege** through groups and roles (never ad hoc on individual users), scoped to specific ARNs and tightened over time with Access Analyzer.
5. **Use conditions** (`aws:MultiFactorAuthPresent`, `aws:SourceVpc`, `aws:PrincipalOrgID`, tags) to make permissions context-aware.
6. **Rotate or, better, remove access keys.** Review the credential report for unused keys and passwords.
7. **Guardrails at the org level** with SCPs/RCPs, and Access Analyzer checks on every policy before it ships, so one mistake cannot open everything.
8. **Keep IAM in code** (Terraform), so every permission change goes through review and git history.

## Common use cases

- **EC2 app reading S3:** role + instance profile, no keys on the box.
- **CI/CD without secrets:** GitHub Actions assumes a role through OIDC. The trust policy pins the exact repo and branch:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "repo:netram75/devops-heros:ref:refs/heads/main" }
    }
  }]
}
```

- **Cross-account access:** a role in a prod account that only a specific role in the tooling account may assume.
- **Lambda execution roles:** each function gets its own narrowly scoped role.
- **Terraform pipelines:** a dedicated plan role (read-only) and apply role (write), so a pull request can never apply.

## How this shows up in Terraform

The EC2-reads-S3 case from above as code: a role, its trust policy, an inline permission policy and the instance profile EC2 needs to carry the role.

```hcl
resource "aws_iam_role" "app" {
  name = "session18-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "uploads_rw" {
  name = "uploads-rw"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::netram-session18-demo"
        Condition = { StringLike = { "s3:prefix" = ["uploads/*"] } }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::netram-session18-demo/uploads/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "session18-app-profile"
  role = aws_iam_role.app.name
}
```

I prefer `jsonencode` over pasting raw JSON in a heredoc: Terraform always produces syntactically valid JSON, references like `aws_s3_bucket.x.arn` can replace hard-coded ARNs, and a typo shows up in `terraform validate` instead of as a `MalformedPolicyDocument` error halfway through an apply.
