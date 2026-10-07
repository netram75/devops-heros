# Session 18 - AWS Services - DynamoDB and RDS

- **Name:** Netram
- **Enrollment No:** 24BCS10329

> Category: **Databases**. DynamoDB is AWS's serverless NoSQL key-value store; RDS runs managed relational databases (PostgreSQL, MySQL and others) for me.

---

# Part 1: DynamoDB

## NoSQL

DynamoDB is a **fully managed, serverless NoSQL database** for key-value and document data. There are no servers, versions or patches; I create a table and send requests over HTTPS.

"NoSQL" here means: no fixed schema beyond the key, **no joins**, and data is fetched by key instead of by arbitrary SQL. That is a deliberate trade. Every request is routed by its key straight to one partition, so latency stays in single-digit milliseconds whether the table holds 1 GB or 100 TB. The cost is that I must **design the table around my access patterns up front** ("fetch all orders for a customer, newest first") rather than normalizing data and deciding the queries later.

## Tables

A table is a collection of items. At creation I only define the **table name and the primary key** (the Terraform version is at the end); every other attribute is free-form.

Table-level choices and why they matter:

- **Capacity mode.** *On-demand* (`PAY_PER_REQUEST`) bills per read and write and scales instantly; it is the sensible default, especially since the November 2024 price cut. *Provisioned* (read/write capacity units plus auto scaling) is cheaper only for steady, predictable traffic.
- **Secondary indexes** for other access patterns: a **GSI** has its own partition and sort key and can be added any time; an **LSI** shares the partition key with a different sort key and can only be created with the table.
- **Always encrypted at rest** (AWS owned key by default, or a KMS key).
- **Point-in-time recovery** (restore to any second within a configurable 1-35 day window), **TTL** (free automatic deletion of expired items), **Streams** (change feed for Lambda), **deletion protection** and **global tables** (multi-region replication).

## Items

An item is one record, comparable to a row, uniquely identified by its primary key. Items in the same table can have completely different attributes. The hard limit is **400 KB per item**, attribute names included.

```bash
aws dynamodb put-item --table-name session18-orders --item '{
  "customer_id": {"S": "C-1001"},
  "order_date":  {"S": "2026-10-07#ORD-5001"},
  "total":       {"N": "1499"},
  "items":       {"L": [{"M": {"sku": {"S": "BOOK-42"}, "qty": {"N": "1"}}}]}
}'
```

Reads are **eventually consistent by default** (half the cost); a strongly consistent read is available on the table and LSIs but not on GSIs. Conditional writes give optimistic locking, and transactions group up to 100 actions atomically.

## Attributes

An attribute is a name-value pair inside an item. Only the key attributes have a declared type; the rest are typed per value.

| Type code | Meaning | Example |
|---|---|---|
| `S`, `N`, `B` | String, number, binary | `{"N": "1499"}` (numbers travel as strings to keep precision) |
| `BOOL`, `NULL` | Boolean, null | `{"BOOL": true}` |
| `M`, `L` | Map (nested object), list | `{"M": {"city": {"S": "Pune"}}}` |
| `SS`, `NS`, `BS` | String, number, binary sets | `{"SS": ["red", "blue"]}` |

Item size drives cost: one write unit covers 1 KB and one strongly consistent read unit covers 4 KB, so short attribute names and not stuffing large blobs into items (put them in S3 and store the key) both save money.

## Partition key

The partition key is the mandatory part of the primary key. DynamoDB **hashes its value to decide which physical partition stores the item**. With a partition key alone (a *simple* primary key), each value must be unique.

The hash is why key choice is the most important design decision. Each partition handles roughly 3,000 read units and 1,000 write units per second, so if most traffic hits one key value, that partition throttles no matter how much total capacity the table has.

| Partition key | Verdict | Why |
|---|---|---|
| `customer_id`, `device_id`, `order_id` | Good | Many distinct values, traffic spread evenly |
| `status` (`PLACED`, `SHIPPED`) | Bad | Few values, one hot partition |
| Today's date | Bad | All of today's writes land on one key |

## Sort key

Adding a sort key makes a *composite* primary key: the **pair** must be unique, and all items with the same partition key are stored together, **sorted by the sort key**. That unlocks range queries with `=`, `<`, `>`, `BETWEEN` and `begins_with` on the sort key.

Strings sort by their bytes, so an ISO 8601 date prefix (`2026-10-07#...`) sorts chronologically. "All of customer C-1001's orders in October 2026" becomes one efficient `Query`:

```bash
aws dynamodb query --table-name session18-orders \
  --key-condition-expression "customer_id = :c AND begins_with(order_date, :m)" \
  --expression-attribute-values '{":c":{"S":"C-1001"},":m":{"S":"2026-10"}}' \
  --no-scan-index-forward
```

`Query` reads one partition key's items; `Scan` reads the whole table and is billed for all of it, so a Scan in a hot code path is a design smell.

## DynamoDB use cases

- **User profiles, sessions, shopping carts:** key lookups at any scale.
- **Serverless backends:** Lambda plus API Gateway, with no connection pool to exhaust because every call is HTTP.
- **High-write telemetry:** IoT readings, game events, clickstreams, with TTL expiring old data for free.
- **Event-driven flows:** Streams trigger a Lambda whenever an item changes.
- **Idempotency keys and counters:** conditional writes and atomic `ADD` updates.
- **Terraform state locking**, historically. Terraform 1.11 deprecated the DynamoDB lock table in favor of S3-native locking (`use_lockfile = true`), covered in my [S3 notes](../03-s3/README.md).

# Part 2: RDS

## Relational database

A relational database stores data in **tables with a fixed schema**, linked by keys, queried with **SQL**, and protected by **ACID transactions** (a transfer either fully happens or does not). Joins and constraints keep data consistent across tables.

RDS (Relational Database Service) runs these engines **as a managed service**. AWS handles provisioning, OS and engine patching, automated backups, failover and monitoring; I handle the schema, queries, indexes, parameter tuning and sizing. Running PostgreSQL on EC2 myself would mean building backups, replication and failover by hand; RDS turns them into settings. The trade-off is no SSH or OS access to the database host.

## Supported engines

| Engine | Notes |
|---|---|
| PostgreSQL | My default for new projects |
| MySQL | Very common for web apps |
| MariaDB | Community fork of MySQL |
| Oracle | Bring-your-own-license or license included (Standard Edition 2) |
| Microsoft SQL Server | Express, Web, Standard and Enterprise editions |
| IBM Db2 | Added to RDS in late 2023 |
| Amazon Aurora (MySQL- and PostgreSQL-compatible) | Part of the RDS family, with a distributed storage layer and a cluster model |

## DB instances

A **DB instance** is one isolated database server running one engine. What I choose when creating it:

- **Identifier** (unique per account and region), which also forms the **endpoint**: a DNS name like `session18-postgres.<random>.ap-south-1.rds.amazonaws.com:5432`. Applications must connect by this name, never by IP, because the IP changes on failover.
- **Instance class:** `db.t4g`/`db.t3` (burstable, dev), `db.m7g` (general), `db.r7g` (memory-heavy).
- **Storage:** `gp3` for most workloads, `io2` for heavy IOPS. Storage can grow (with autoscaling up to a limit I set) but **can never shrink**.
- **Parameter group** (engine settings such as `max_connections`), an **option group** for some engines, and a **maintenance window** for patching.

## Security

Security works in layers, and each one covers a different risk:

- **Network:** the instance sits in a **DB subnet group** of private subnets in at least two AZs, with `publicly_accessible = false`. Its security group allows 5432 only from the app's security group.
- **Credentials:** the master password is **managed in Secrets Manager** and rotated by RDS, so it never appears in code or Terraform state. For MySQL, MariaDB and PostgreSQL, **IAM database authentication** swaps passwords for 15-minute tokens from `aws rds generate-db-auth-token`.
- **Encryption at rest** with KMS covers storage, snapshots, backups and replicas. It must be chosen **at creation**: an unencrypted instance can only be fixed by snapshot, encrypted copy, restore.
- **Encryption in transit:** TLS, enforced with `rds.force_ssl` (PostgreSQL) or `require_secure_transport` (MySQL).
- **Two separate permission systems:** IAM decides who can *modify or delete the instance*; database users and `GRANT` decide who can *read tables*.
- **Deletion protection** stops a stray `terraform destroy` or console click.

## Backups

- **Automated backups:** a daily snapshot in the backup window plus transaction logs shipped about every 5 minutes. Together they allow **point-in-time restore** to any second in the retention period (1-35 days; 0 disables backups). Backup storage up to the size of the database is free.
- **Manual snapshots:** kept until I delete them, can be copied to other regions or accounts. I take one before any risky migration.
- **A restore always creates a new DB instance with a new endpoint.** It never overwrites the original, so the app's connection string (or a DNS alias in front of it) has to change.
- On deletion RDS offers a **final snapshot**; automated backups are removed with the instance unless I choose to retain them.

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier session18-postgres \
  --target-db-instance-identifier session18-postgres-restored \
  --restore-time 2026-10-07T09:30:00Z
```

## Multi-AZ

A **Multi-AZ DB instance** keeps a **synchronous standby** in a second AZ. Every committed write is on both before it is acknowledged, so a failover loses no committed data. If the primary or its AZ fails (or during patching and class changes), RDS flips the endpoint's DNS to the standby, typically in **60-120 seconds**.

The standby **cannot serve reads**. Multi-AZ is for **high availability, not read scaling**; it roughly doubles instance cost to buy uptime. The newer **Multi-AZ DB cluster** (MySQL and PostgreSQL only) is the exception: a writer plus two *readable* standbys in three AZs, with failover typically under 35 seconds.

## Read replicas

A read replica is an **asynchronous**, readable copy of the source instance, used to **scale reads**: reporting queries, dashboards and read-heavy APIs.

- Up to **15 per source** instance, in the same region or another region.
- **Replication lag:** a replica can be slightly behind, so read-your-own-write flows must read from the primary.
- RDS does **not** split traffic for me; the app sends reads to the replica's own endpoint.
- A replica can be **promoted** to a standalone instance, which makes a cross-region replica a simple DR plan.
- Created with `aws rds create-db-instance-read-replica`; automated backups must be enabled on the source first.

| | Multi-AZ (DB instance) | Read replica |
|---|---|---|
| Purpose | High availability | Read scaling, cross-region DR |
| Replication | Synchronous | Asynchronous |
| Readable | No | Yes |
| Failover | Automatic, same endpoint | Manual promotion, new endpoint |
| Data loss on failure | None for committed writes | Possible (lag) |
| Placement | Another AZ, same region | Any AZ or another region |

## RDS use cases

- **Transactional app backends:** users, orders, payments, anywhere integrity and joins matter.
- **Existing MySQL/PostgreSQL/SQL Server apps** moved to AWS without running database servers.
- **Reporting and ad hoc SQL**, with read replicas taking the load off the primary.
- **Commercial software** (ERP, CRM) that requires Oracle or SQL Server.

## DynamoDB vs RDS

| | DynamoDB | RDS |
|---|---|---|
| Data model | Key-value and document | Relational tables |
| Schema | Only the key is fixed | Strict schema, migrations |
| Querying | By key and index; no joins | Full SQL, joins, aggregates |
| Scaling | Horizontal and automatic | Bigger instance class, plus read replicas |
| Operations | Serverless | I pick class, storage and windows |
| Pricing | Per request (or provisioned capacity) plus storage | Per instance-hour plus storage |
| Best when | Access patterns are known and scale is large or spiky | Data is relational and queries are varied |

## How this shows up in Terraform

```hcl
resource "aws_dynamodb_table" "orders" {
  name         = "session18-orders"
  billing_mode = "PAY_PER_REQUEST" # Terraform's default is PROVISIONED
  hash_key     = "customer_id"
  range_key    = "order_date"

  attribute {
    name = "customer_id"
    type = "S"
  }
  attribute {
    name = "order_date"
    type = "S"
  }
}

resource "aws_db_subnet_group" "db" {
  name       = "session18-db"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_db_instance" "app" {
  identifier                  = "session18-postgres"
  engine                      = "postgres"
  engine_version              = "17"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  storage_type                = "gp3"
  storage_encrypted           = true # defaults to false
  db_name                     = "appdb"
  username                    = "appadmin"
  manage_master_user_password = true # password lives in Secrets Manager
  db_subnet_group_name        = aws_db_subnet_group.db.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  multi_az                    = true
  backup_retention_period     = 7
  deletion_protection         = true
  final_snapshot_identifier   = "session18-postgres-final"
}
```

The private subnets and `aws_security_group.db` follow the pattern in the [VPC notes](../04-vpc/README.md). Only key (and index key) attributes go in `attribute` blocks; Terraform rejects a table that declares an attribute no key uses. For RDS, I set every security-relevant argument explicitly, because several provider defaults (no encryption, `gp2` storage) are not what I want.
