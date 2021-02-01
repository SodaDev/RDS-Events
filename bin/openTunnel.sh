BASTION_IP=`aws ec2 describe-instances --filters Name=tag:Name,Values='RDS Events Bastion' Name=instance-state-name,Values=running | jq -r '.Reservations[].Instances[].PublicIpAddress'`
RDS_CLUSTER_ENDPOINT=`aws rds describe-db-clusters --db-cluster-identifier rds-events-cluster | jq -r '.DBClusters[].Endpoint'`
echo "Found bastion ip: " $BASTION_IP
echo "Found rds cluster: " $RDS_CLUSTER_ENDPOINT
ssh -i ~/.ssh/bastion-key.pem -N -L 33306:"$RDS_CLUSTER_ENDPOINT":3306 ec2-user@"$BASTION_IP" -v
