-- S3 -> Snowflake access via a storage integration (no AWS keys stored in Snowflake).
-- TODO(Jon): replace clipboard.health.pipeline.bucket, 123456789012, and the role name.

use role accountadmin;

create storage integration if not exists clipboard_s3_int
  type = external_stage
  storage_provider = 'S3'
  enabled = true
  storage_aws_role_arn = 'arn:aws:iam::123456789012:role/snowflake-clipboard-health'
  storage_allowed_locations = ('s3://clipboard.health.pipeline.bucket/clipboard/');

-- Copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID from this output
-- into the IAM role's trust policy (template below).
desc integration clipboard_s3_int;

grant usage on integration clipboard_s3_int to role clipboard_transformer;

use role clipboard_transformer;
create stage if not exists clipboard_health.raw.cms_s3_stage
  storage_integration = clipboard_s3_int
  url = 's3://clipboard.health.pipeline.bucket/clipboard/'
  file_format = clipboard_health.raw.cms_csv_gz;

-- Fallback if S3 access breaks: an internal stage. load_snowflake.py --stage internal
-- PUTs local files here and the rest of the pipeline is unchanged.
create stage if not exists clipboard_health.raw.cms_internal_stage
  file_format = clipboard_health.raw.cms_csv_gz;

-- Smoke test: should list pbj_daily/ and provider_info/ files after ingest
list @clipboard_health.raw.cms_s3_stage;

/* ---------------------------------------------------------------------------
IAM role trust policy (AWS console -> IAM -> Roles -> snowflake-clipboard-health
-> Trust relationships). The AssumeRole error almost always means one of:
  1. the Principal ARN or ExternalId doesn't match `desc integration` exactly
  2. the integration was re-created (CREATE OR REPLACE), which generates a NEW
     external ID; use CREATE ... IF NOT EXISTS, or update the trust policy after
  3. storage_allowed_locations doesn't cover the stage URL (trailing slash matters)

{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "<STORAGE_AWS_IAM_USER_ARN>" },
    "Action": "sts:AssumeRole",
    "Condition": { "StringEquals": { "sts:ExternalId": "<STORAGE_AWS_EXTERNAL_ID>" } }
  }]
}

Permissions policy on the same role:
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["s3:GetObject", "s3:GetObjectVersion"],
      "Resource": "arn:aws:s3:::clipboard.health.pipeline.bucket/clipboard/*" },
    { "Effect": "Allow", "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::clipboard.health.pipeline.bucket",
      "Condition": { "StringLike": { "s3:prefix": ["clipboard/*"] } } }
  ]
}
--------------------------------------------------------------------------- */
