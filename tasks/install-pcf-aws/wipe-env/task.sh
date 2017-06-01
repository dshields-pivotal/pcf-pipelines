#!/bin/bash
set -e

root=$(pwd)

cd pcf-pipelines/tasks/install-pcf-aws/terraform

export AWS_ACCESS_KEY_ID=${TF_VAR_aws_access_key}
export AWS_SECRET_ACCESS_KEY=${TF_VAR_aws_secret_key}
export AWS_DEFAULT_REGION=${TF_VAR_aws_region}
export VPC_ID=$(
  terraform state show -state "${root}/terraform-state/terraform.tfstate" aws_vpc.PcfVpc | grep ^id | awk '{print $3}'
)

instances=$(
  aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --output=json |
  jq --raw-output '.Reservations[].Instances[].InstanceId'
)
if [[ -n "$instances" ]]; then
  # Purge all BOSH-managed VMs from the VPC
  echo "instances: $instances will be deleted......"
  aws ec2 terminate-instances --instance-ids $instances
  aws ec2 wait instance-terminated --instance-ids $instances
fi

set +e
terraform destroy \
  -force \
  -var "opsman_ami=dontcare" \
  -var "db_master_username=dontcare" \
  -var "db_master_password=dontcare" \
  -var "prefix=dontcare" \
  -state "${root}/terraform-state/terraform.tfstate" \
  -state-out "${root}/terraform-state-output/terraform.tfstate"
