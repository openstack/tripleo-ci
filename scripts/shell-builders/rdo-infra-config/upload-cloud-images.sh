set -e
echo ======== UPLOAD CLOUD IMAGES
source /tmp/hash_info.sh

# If I try to build images as upstream ( in /home/jenkins ) something will go wrong
# we leave quickstart build in the default location. it proved to work
pushd /var/lib/oooq-images/$RELEASE

ls *.tar
chmod 600 $SSH_KEY
export RSYNC_RSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY"
rsync_cmd="rsync --verbose --archive --delay-updates --relative"
UPLOAD_URL=uploader@images.rdoproject.org:/var/www/html/images/$RELEASE/delorean/tripleo-upstream
mkdir $FULL_HASH
mv overcloud-full.tar overcloud-full.tar.md5 $FULL_HASH
mv ironic-python-agent.tar $FULL_HASH/ipa_images.tar
mv ironic-python-agent.tar.md5 $FULL_HASH/ipa_images.tar.md5

$rsync_cmd $FULL_HASH $UPLOAD_URL
$rsync_cmd --delete --include 'testing**' --exclude '*' ./ $UPLOAD_URL/
# push testing symlink so sub-jobs know what to test
# but only after all images are uploaded
ln -s $FULL_HASH testing
rsync -av testing $UPLOAD_URL/

popd
echo ======== UPLOAD CLOUD IMAGES COMPLETE
