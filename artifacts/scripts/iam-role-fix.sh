aws iam create-role --role-name lab-a2-diagnostic-role --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' --region us-east-1

aws iam attach-role-policy --role-name lab-a2-diagnostic-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess

aws iam attach-role-policy --role-name lab-a2-diagnostic-role --policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly

aws iam create-instance-profile --instance-profile-name lab-a2-diagnostic-profile

aws iam add-role-to-instance-profile --instance-profile-name lab-a2-diagnostic-profile --role-name lab-a2-diagnostic-role

aws ec2 describe-instances --filters "Name=tag:Name,Values=lab-a2-linux" --query 'Reservations[0].Instances[0].InstanceId' --output text --region us-east-1

aws ec2 associate-iam-instance-profile --instance-id <A2_INSTANCE_ID_FROM_ABOVE> --iam-instance-profile Name=lab-a2-diagnostic-profile --region us-east-1