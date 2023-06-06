# Prompt user for required info
read -p "Enter Cloud9 environment name: " C9_NAME
while [ -z "${C9_NAME}" ]; do
  echo "This is required."
  read -p "Enter Cloud9 environment name: " C9_NAME
done


# Install dependencies
sudo yum -y install jq
npm install -g yarn
yarn global add --force aws-cdk

# Grow storage
SIZE_TARGET=20
CF_NAME=$( \
  aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE \
  | jq -r \
    --arg C9_NAME ${C9_NAME} \
    '.StackSummaries[] | select(.StackName | contains($C9_NAME)) | .StackName' \
)
EC2_ID=$( \
  aws cloudformation list-stack-resources --stack-name ${CF_NAME} \
  | jq -r \
    '.StackResourceSummaries[] | select(.LogicalResourceId == "Instance") | .PhysicalResourceId' \
)
VOL_ID=$( \
  aws ec2 describe-instances --instance-ids ${EC2_ID} \
  | jq -r \
    '.Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
)
VOL_SIZE=$( \
  aws ec2 describe-volumes --volume-ids ${VOL_ID} \
  | jq -r \
    --arg VOL_ID "${VOL_ID}" \
    '.Volumes[] | select(.VolumeId == $VOL_ID) | .Size' \
)
if [ ${VOL_SIZE} -lt ${SIZE_TARGET} ]; then
  aws ec2 modify-volume --volume-id ${VOL_ID} --size ${SIZE_TARGET}
  until [ \
    $( \
      aws ec2 describe-volumes-modifications --volume-id ${VOL_ID} \
      | jq -r \
        '.VolumesModifications[0].ModificationState' \
    ) = "optimizing" \
  ]; do
    sleep 1
  done
fi

# Use storage
DEV="/dev/nvme0n1"
PART=${DEV}"p1"
FS=$(df -hT | grep ${PART} | awk '{ print $2 }')
sudo growpart ${DEV} 1
if [ "${FS}" = "xfs" ]; then
  sudo xfs_growfs -d /
fi
if [ "${FS}" = "ext4" ]; then
  sudo resize2fs ${PART}
fi

# Bootstrap CDK
yarn
npx yaml2json cdk.context.yaml > cdk.context.json

ACCOUNT=$( \
  aws sts get-caller-identity \
  | jq -r .Account \
)
REGION=$(aws configure get region)
cdk bootstrap aws://${ACCOUNT}/${REGION}
