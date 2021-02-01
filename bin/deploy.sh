MY_IP="$(dig +short myip.opendns.com @resolver1.opendns.com)"

sam deploy \
  --stack-name RDS-EVENTS \
  --s3-prefix rds-events \
  --s3-bucket sodkiewiczm-deployments \
  --template-file ./cloudformation/app.yaml \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides \
    DatabaseName='flights' \
    MasterUserPassword='AuGcaxWp3HDj]q~z' \
    LocalMachineIp="${MY_IP}" \
    BastionKeyName='bastion-key' \
  --debug


