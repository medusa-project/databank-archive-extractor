# Databank Archive Extractor

A Ruby worker that inspects archive files stored in Amazon S3 and reports their contents to Databank. It supports ZIP, gzip, tar/gzip, 7-Zip, TAR, RAR, XZ, and other archives handled by libarchive, and uses 7-Zip as an additional CLI fallback.

The worker downloads an object from S3, generates a nested-item listing and optional text peek, uploads the result as JSON to S3, and publishes a notification to Amazon SQS.

## Features

- Extracts ZIP, gzip, TAR, 7-Zip, RAR, and XZ archive listings
- Generates MIME type information and HTML archive previews
- Handles small files from ephemeral storage and large files from an attached EFS mount
- Filters common macOS metadata entries
- Falls back to 7-Zip for supported archive formats
- Reports S3 download/upload and extraction errors through SQS
- Runs as a Docker container

## Requirements

- Ruby 3.4.5
- Bundler 4
- System packages:
  - `build-essential` or equivalent C/C++ toolchain
  - `libarchive-dev`
  - `libmagic-dev`
  - `p7zip-full` (`7z`)
  - `zip`

## Installation

Clone the repository and install its Ruby dependencies:

```sh
bundle install
```

The Docker image is the recommended way to run the worker because it includes all native dependencies:

```sh
docker build -t databank-archive-extractor .
```

## Configuration

Set `RUBY_HOME` to the application directory and `RUBY_ENV` to the environment to load:

- `RUBY_ENV=demo` loads `config/settings/demo.yml`
- `RUBY_ENV=prod` loads `config/settings/prod.yml`
- `RUBY_ENV=test` loads `config/settings/test.yml`

For example:

```sh
export RUBY_HOME="$(pwd)"
export RUBY_ENV=demo
```

Environment-specific AWS settings are defined in `config/settings.yml` and `config/settings/<environment>.yml`. Configure the AWS region, SQS queue name and URL, JSON result bucket, EFS mount point, and ephemeral storage path for the deployment environment.

The worker requires AWS credentials and permissions to:

- Read the source object and its attributes from S3
- Write the JSON result to the configured S3 bucket
- Send the result notification to SQS

## Usage

The application is hosted on AWS ECS Fargate. Invoke an extraction by calling `run_task` with the source object details in the container command. For example, from a Ruby process with AWS credentials and permission to run the task:

```ruby
require 'aws-sdk-ecs'

client = Aws::ECS::Client.new(
  region: "us-east-2",
)

resp = client.run_task({
  cluster: "databank-archive-extractor-prod",
  count: 1,
  launch_type: "FARGATE",
  enable_execute_command: true,
  network_configuration: {
    awsvpc_configuration: {
      subnets: ["<subnet-a>", "<subnet-b>"],
      security_groups: ["<sg>"],
      assign_public_ip: "ENABLED",
    },
  },
  overrides: {
    container_overrides: [
      {
        name: "databank-archive-extractor-prod-task",
        command: [
          "ruby", "-r", "./lib/extractor.rb", "-e",
          "Extractor.extract '<source bucket>', '<object key>', '<filename>', '<web_id>', '<mime type>'",
        ],
      },
    ],
  },
  platform_version: "1.4.0",
  task_definition: "databank-archive-extractor-prod-td:4",
})
```

Replace the bucket, object key, filename, web ID, and MIME type in `Extractor.extract` with the object to process. The cluster, task definition, container name, subnet IDs, and security group must match the target AWS environment. The caller needs ECS permissions to start tasks and the required `iam:PassRole` permission for the task's roles.

## Development

Set the application and test environment variables, then run the test suite:

```sh
export RUBY_HOME="$(pwd)"
export RUBY_ENV=test
bundle exec rake test
```

The test configuration uses paths under `test/` and `test/efs/`; test fixtures include ZIP, TAR, gzip, and text files.

To build and run the test image locally:

```sh
docker build -f docker/extractor/Dockerfile-test -t databank-archive-extractor-test .
docker run --rm databank-archive-extractor-test
```
