set -e

echo ======== PREPARE HASH PROMOTION

export PROMOTE_NAME=tripleo-ci-testing
mkdir $WORKSPACE/logs

curl -o /tmp/delorean.repo https://trunk.rdoproject.org/centos7-$RELEASE/consistent/delorean.repo

export FULL_HASH=$(grep -o -E '[0-9a-f]{40}_[0-9a-f]{8}' < /tmp/delorean.repo)
export HASH_PATH=$(grep -o -E '[a-f0-9]{2}/[a-f0-9]{2}/[0-9a-f]{40}_[0-9a-f]{8}' < /tmp/delorean.repo)
export COMMIT_HASH=$(awk -F_ '{print $1}' <<<$FULL_HASH)
delorean_commit_url="https://trunk.rdoproject.org/centos7-$RELEASE/$HASH_PATH/commit.yaml"
export DISTRO_HASH=$(curl $delorean_commit_url | awk -F": " '/distro_hash/ {print $2}')
export DLRNAPI_URL="https://trunk.rdoproject.org/api-centos-$RELEASE"
if [ "$RELEASE" = "master" ]; then
    # for master we have two DLRN builders, use the "upper constraint" one that
    # places restrictions on the maximum version of all dependencies
    export DLRNAPI_URL="${DLRNAPI_URL}-uc"
fi

cat > /tmp/hash_info.sh << EOF
export DLRNAPI_URL=$DLRNAPI_URL
export RELEASE=$RELEASE
export HASH_PATH=$HASH_PATH
export FULL_HASH=$FULL_HASH
export COMMIT_HASH=$COMMIT_HASH
export DISTRO_HASH=$DISTRO_HASH
export PROMOTE_NAME=$PROMOTE_NAME
EOF

mv /tmp/delorean.repo $WORKSPACE/logs
cp /tmp/hash_info.sh $WORKSPACE/logs

virtualenv --system-site-packages /tmp/delorean
source /tmp/delorean/bin/activate
pip install ansible==2.3.0.0 dlrnapi_client

# Assign label to latest hash using the DLRN API
dlrnapi --url $DLRNAPI_URL \
    --username review_rdoproject_org \
    repo-promote \
    --commit-hash $COMMIT_HASH \
    --distro-hash $DISTRO_HASH \
    --promote-name $PROMOTE_NAME

deactivate
echo ======== PREPARE HASH PROMOTION COMPLETED
