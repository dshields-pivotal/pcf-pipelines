#!/bin/bash -u

function main() {

local cwd
cwd="${1}"

chmod +x terraform/terraform
CMD_PATH="terraform/terraform"

chmod +x iaas-util/cliaas-linux
AWS_UTIL_PATH="iaas-util/cliaas-linux"

IAAS_CONFIGURATION=$(cat <<-EOF
provider "aws" {
  region = "${AWS_REGION}"
  access_key = "${AWS_ACCESS_KEY_ID}"
  secret_key = "${AWS_SECRET_ACCESS_KEY}"
}

resource "aws_instance" "ops-manager-to-provision" {
  ami = "${AMI}"
  instance_type = "${INSTANCE_TYPE}"
  key_name = "${KEY_NAME}"
  subnet_id = "${SUBNET_ID}"
  associate_public_ip_address = "true"
  instance_initiated_shutdown_behavior = "stop"
  vpc_security_group_ids = ["${SECURITY_GROUP}"]
  tags {
       Name = "${AWS_INSTANCE_NAME}"
   }
}

resource "aws_route53_record" "dns-record-to-provision" {
  zone_id = "${ROUTE53_ZONE_ID}"
  name = "${OPSMAN_SUBDOMAIN}"
  type = "CNAME"
  ttl = "300"
  records = ["\${aws_instance.ops-manager-to-provision.public_dns}"]
}
EOF
)
  echo $IAAS_CONFIGURATION > ./opsman_settings.tf

  read OLD_OPSMAN_INSTANCE ERR < <(./${AWS_UTIL_PATH} "${AWS_INSTANCE_NAME}")

  if [ -n "$OLD_OPSMAN_INSTANCE" ]
  then
    echo "Destroying old Ops Manager instance. ${OLD_OPSMAN_INSTANCE}"
    ./${CMD_PATH} import aws_instance.ops-manager-to-purge ${OLD_OPSMAN_INSTANCE}
    ./${CMD_PATH} destroy -state=./terraform.tfstate -target=aws_instance.ops-manager-to-purge -force
    rm ./terraform.tfstate
  fi

  echo "Provisioning Ops Manager"
  cat ./opsman_settings.tf
  ./${CMD_PATH} apply

# verify that ops manager started
  started=false
  timeout=$((SECONDS+${OPSMAN_TIMEOUT}))

  echo "Starting Ops manager on ${OPSMAN_URI}"

  timeout=$((SECONDS+${OPSMAN_TIMEOUT}))
  while [[ $started ]]; do
    HTTP_OUTPUT=$(curl --write-out %{http_code} --silent -k --output /dev/null ${OPSMAN_URI})
    if [[ $HTTP_OUTPUT == *"302"* || $HTTP_OUTPUT == *"301"* ]]; then
      echo "Site is started! $HTTP_OUTPUT"
      break
    else
      echo "Ops manager is not running on ${OPSMAN_URI}..."
      if [[ $SECONDS -gt $timeout ]]; then
        echo "Timed out waiting for ops manager site to start."
        exit 1
      fi
    fi
  done

}
main "${PWD}"
