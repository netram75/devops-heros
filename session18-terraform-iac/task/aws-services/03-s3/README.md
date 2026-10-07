# Session 18 - AWS Services - S3

- **Name:** Netram
- **Enrollment No:** 24BCS10329

> Category: **Storage**. S3 is object storage: files go in over HTTPS and come back by key, with no disk or server to manage.

---

## What is S3

S3 (Simple Storage Service) stores **objects** (a file plus metadata) inside **buckets**, and everything is done through an HTTPS API: `PutObject`, `GetObject`, `ListObjectsV2`, `DeleteObject`. There is no filesystem to mount and no capacity to provision. I pay for what is stored, for requests and for data transferred out.

Why it is the default place for files on AWS:

- **Durability:** designed for 99.999999999% (11 nines). Most classes copy data across at least three Availability Zones.
- **Strong consistency:** since December 2020, a successful write is immediately visible to every read and list. No "upload then wait" hacks.
- **Scale:** no practical limit on total data or object count in a bucket.

S3 is *object* storage, not block storage like EBS. I cannot edit byte 500 of an object in place; I replace the whole object. That is fine for images, backups, logs and datasets, and wrong for a database's data files.

## Buckets

A bucket is the container for objects and the unit where most settings live: region, versioning, encryption defaults, lifecycle rules, policies.

- **Region-bound.** A bucket is created in one region (for me `ap-south-1`) and its data stays there unless I configure replication.
- **Names are global by default.** A general purpose bucket name must be unique across all AWS accounts: 3-63 characters, lowercase letters, numbers, hyphens and dots, starting and ending with a letter or number. I avoid dots, because they break the TLS wildcard certificate for virtual-hosted URLs.
- **Account regional namespace (March 2026):** I can now opt in to names ending in `-<account-id>-<region>-an` (created with `--bucket-namespace account-regional`), which only my account can use. No more "bucket name already taken".
- **Quota:** 10,000 general purpose buckets per account by default, raisable to 1 million.
- **Bucket types:** *general purpose* (the normal one), *directory buckets* for S3 Express One Zone (single-digit millisecond latency in one AZ), *table buckets* for Apache Iceberg tables (S3 Tables) and *vector buckets* for vector search (S3 Vectors).

Two secure defaults apply to every new bucket since April 2023: **Block Public Access is on**, and **Object Ownership is "Bucket owner enforced"**, which disables ACLs. Access is then controlled only by IAM and bucket policies, which are much easier to reason about than per-object ACLs.

## Objects

An object is **key + data + metadata** (plus a version ID if versioning is on).

- **Key:** the full name, for example `logs/2026/10/07/app.log`, up to 1,024 bytes. The namespace is flat: `logs/` is not a real folder, just a prefix that the console and `ListObjectsV2 --prefix` treat like one.
- **Size:** up to **50 TB** per object (raised from 5 TB in December 2025). A single `PutObject` is capped at 5 GB, so large files use **multipart upload**, which uploads parts in parallel and retries only failed parts. The AWS CLI switches to multipart on its own for large files.
- **Metadata:** system metadata (`Content-Type`, `ETag`, storage class) and user metadata (`x-amz-meta-*`).

```bash
aws s3 cp build/report.pdf s3://netram-session18-demo/reports/report.pdf
aws s3api head-object --bucket netram-session18-demo --key reports/report.pdf
aws s3 presign s3://netram-session18-demo/reports/report.pdf --expires-in 900
```

The presigned URL is how I would share a private object for 15 minutes without making anything public.

## Storage classes

Every object has a storage class. They trade storage price against retrieval speed, retrieval fees and minimum storage duration. All are designed for 11 nines of durability.

| Class | First byte | Min storage duration | Designed availability | AZs | Good for |
|---|---|---|---|---|---|
| S3 Standard | Milliseconds | None | 99.99% | 3+ | Hot data, websites, active datasets |
| S3 Intelligent-Tiering | Milliseconds | None | 99.9% | 3+ | Unknown or changing access patterns |
| S3 Standard-IA | Milliseconds, per-GB retrieval fee | 30 days | 99.9% | 3+ | Backups read a few times a month |
| S3 One Zone-IA | Milliseconds, per-GB retrieval fee | 30 days | 99.5% | 1 | Re-creatable copies, secondary backups |
| S3 Glacier Instant Retrieval | Milliseconds, higher retrieval fee | 90 days | 99.9% | 3+ | Archives read about once a quarter |
| S3 Glacier Flexible Retrieval | Minutes to hours (1-5 min expedited, 3-5 h standard, 5-12 h bulk) | 90 days | 99.99% | 3+ | Backups and DR archives |
| S3 Glacier Deep Archive | Within 12 h (standard), 48 h (bulk) | 180 days | 99.99% | 3+ | Compliance archives kept for years |

How I read this table: the minimum durations are a trap if ignored. Deleting a Deep Archive object after 10 days still bills 180 days. The IA and Glacier Instant classes also bill a minimum of 128 KB per object, so millions of tiny files belong in Standard. When I genuinely do not know the access pattern, Intelligent-Tiering moves objects between tiers automatically for a small per-object monitoring fee (objects under 128 KB are not monitored and stay in the frequent tier).

## Versioning

Versioning keeps **every version** of every object in the bucket. A bucket is in one of three states: *unversioned* (the default), *enabled*, or *suspended*. Once enabled it can only be suspended, never returned to unversioned.

```bash
aws s3api put-bucket-versioning --bucket netram-session18-demo \
  --versioning-configuration Status=Enabled
aws s3api list-object-versions --bucket netram-session18-demo --prefix reports/
```

Why it matters:

- An **overwrite** creates a new version; the old one is still there.
- A **delete** without a version ID only adds a *delete marker*. Removing that marker (`delete-object --version-id <marker-id>`) brings the object back.
- It is required for **replication** and **Object Lock**, and it is the cheapest protection against a buggy script or a ransomware-style overwrite.

The cost side: old versions are billed like any other object, so versioning should almost always be paired with a lifecycle rule that expires noncurrent versions. MFA Delete can additionally require MFA to delete versions or change the versioning state.

## Lifecycle policies

Lifecycle rules let S3 **move or delete objects automatically** based on age, prefix or tags, instead of me running cleanup scripts. This rule, applied to `logs/`, tiers logs down as they get colder, deletes them after a year, cleans up old versions and removes abandoned multipart uploads:

```json
{
  "Rules": [
    {
      "ID": "logs-tiering-and-expiry",
      "Status": "Enabled",
      "Filter": { "Prefix": "logs/" },
      "Transitions": [
        { "Days": 30, "StorageClass": "STANDARD_IA" },
        { "Days": 90, "StorageClass": "GLACIER" }
      ],
      "Expiration": { "Days": 365 },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 30 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    }
  ]
}
```

```bash
aws s3api put-bucket-lifecycle-configuration --bucket netram-session18-demo \
  --lifecycle-configuration file://lifecycle.json
```

Things worth knowing: `GLACIER` is the API name for Glacier Flexible Retrieval. Objects must sit in Standard for at least 30 days before moving to Standard-IA or One Zone-IA. Since September 2024, new rules by default skip transitioning objects smaller than 128 KB, because the per-object transition fee would cost more than it saves. The `AbortIncompleteMultipartUpload` line is the one people forget: parts of a failed upload are billed but invisible in a normal listing.

## Encryption

**At rest**, every new object has been encrypted since 5 January 2023 with **SSE-S3** at no extra cost. There is no "unencrypted" option any more; the choice is which key.

| Option | Who controls the key | Why choose it |
|---|---|---|
| SSE-S3 | S3 (AES-256) | Default, free, zero setup |
| SSE-KMS | A KMS key (AWS managed `aws/s3` or customer managed) | Key policy is a second access check, key use shows in CloudTrail, keys can be disabled |
| DSSE-KMS | KMS, two layers of encryption | Compliance rules that demand dual-layer encryption |
| SSE-C | I send the key with every request | Disabled by default on new buckets since April 2026; must be enabled explicitly |
| Client-side | My application | S3 never sees plaintext |

With SSE-KMS I would enable **S3 Bucket Keys**, which cut the number of KMS calls (and KMS cost) dramatically:

```bash
aws s3api put-bucket-encryption --bucket netram-session18-demo \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms","KMSMasterKeyID":"alias/session18-s3"},"BucketKeyEnabled":true}]}'
```

**In transit**, S3 endpoints support HTTPS, but plain HTTP still works unless I block it, which is what the bucket policy below does.

## Bucket policies

A bucket policy is a **resource-based IAM policy** attached to the bucket (JSON, up to 20 KB). Unlike an identity policy it has a `Principal`, so it can grant access to other accounts or AWS services, and it can **deny** things for everyone, including admins of my own account.

This one rejects any request that does not use TLS:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::netram-session18-demo",
        "arn:aws:s3:::netram-session18-demo/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
```

Both ARNs are needed: the first covers bucket-level actions such as listing, the second covers every object.

How the layers fit together: **Block Public Access** sits above everything and blocks any policy that would make the bucket public. Within an account, a request is allowed if either the IAM policy or the bucket policy allows it (and nothing denies). Across accounts, both must allow it. To serve a website, I would keep the bucket private and put CloudFront in front with Origin Access Control, granting only CloudFront in the bucket policy.

## Common use cases

- **Static assets and websites** behind CloudFront.
- **Backups and archives** with lifecycle rules down to Glacier classes.
- **Data lakes:** raw files queried in place with Athena, or Iceberg tables in S3 Tables.
- **Logs:** CloudTrail, ALB access logs and VPC Flow Logs all deliver to S3.
- **CI/CD artifacts** and build caches.
- **Terraform remote state.** Since Terraform 1.11, S3 can also do the state locking with `use_lockfile = true`, so the old DynamoDB lock table is no longer needed:

```hcl
terraform {
  backend "s3" {
    bucket       = "netram-tfstate"
    key          = "session18/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

## How this shows up in Terraform

Since AWS provider v4, a bucket's settings are separate resources instead of nested blocks. My Terraform task in this session creates an `aws_s3_bucket` (against LocalStack); versioning is added as its own resource that points at the bucket:

```hcl
resource "aws_s3_bucket" "demo" {
  bucket = "netram-session18-demo"
  tags   = { ManagedBy = "Terraform", Project = "Session18" }
}

resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

Block Public Access is already on by default, but declaring it means Terraform will show a diff if someone switches it off by hand. The lifecycle rule and bucket policy above map to `aws_s3_bucket_lifecycle_configuration` and `aws_s3_bucket_policy` in the same way.
