#!/bin/bash

# Attach AWS managed policies that provide essential access

# Access to S3 for Terraform state management
aws iam attach-role-policy --role-name GitHubActionsRole --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Access to ECR (Elastic Container Registry)
aws iam attach-role-policy --role-name GitHubActionsRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess

# Access to EKS for creating and managing Kubernetes clusters
aws iam attach-role-policy --role-name GitHubActionsRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# Access to work with EKS node groups and required subnets
aws iam attach-role-policy --role-name GitHubActionsRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy

# Allow GitHub Actions role to assume itself and manage IAM
aws iam attach-role-policy --role-name GitHubActionsRole --policy-arn arn:aws:iam::aws:policy/IAMFullAccess

# Access to create ALB, modify Route53 records, and work with networking components
aws iam attach-role-policy --role-name GitHubActionsRole --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess

# Access to create and modify WAF rules
aws iam attach-role-policy --role-name GitHubActionsRole --policy-arn arn:aws:iam::aws:policy/AWSWAFFullAccess

# Access to ACM (AWS Certificate Manager) to provision SSL certificates
aws iam attach-role-policy --role-name GitHubActionsRole --policy-arn arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess

