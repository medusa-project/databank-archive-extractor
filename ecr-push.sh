#!/bin/sh
#
# Builds a Docker image and pushes it to AWS ECR.
#

aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 721945215539.dkr.ecr.us-east-2.amazonaws.com
docker buildx build -t databank-archive-extractor-prod .
docker tag databank-archive-extractor-prod:latest 721945215539.dkr.ecr.us-east-2.amazonaws.com/databank-archive-extractor-prod:latest
docker push 721945215539.dkr.ecr.us-east-2.amazonaws.com/databank-archive-extractor-prod:latest
