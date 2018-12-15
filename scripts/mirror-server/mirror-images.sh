#!/bin/bash

RELEASE=$1
BUILDS="/var/www/html/builds-${RELEASE}/current-tripleo"
MIRRORURL="https://images.rdoproject.org/${RELEASE}/delorean/current-tripleo"
IMAGES="overcloud-full.tar ironic-python-agent.tar"

function check_new_image {
    local img=$1
    wget ${MIRRORURL}/${img}.md5 -O test_md5 -o /dev/null || {
        echo "File ${MIRRORURL}/${img}.md5 doesn't present, can NOT continue"
        exit 1
        }
    diff -q test_md5 ${img}.md5 >/dev/null
}

function update_images {
    for img in $IMAGES; do
        wget ${MIRRORURL}/${img} -O ${img}-${RELEASE}
        wget ${MIRRORURL}/${img}.md5 -O ${img}-${RELEASE}.md5
        down_md5="$(cat ${img}-${RELEASE}.md5 | awk {'print $1'})"
        real_md5="$(md5sum ${img}-${RELEASE} | awk {'print $1'})"
        if [[ "$down_md5" == "$real_md5" ]]; then
            mv -f ${img}-${RELEASE} ${img}
            mv -f ${img}-${RELEASE}.md5 ${img}.md5
        else
            echo "md5 doesn't match, image download was broken!"
            echo "Calculated md5 is $real_md5 and downloaded is $down_md5"
            rm -f "${img}-${RELEASE}"
            rm -f "${img}-${RELEASE}.md5"
        fi
    done
    wget ${MIRRORURL}/delorean_hash.txt -O delorean_hash.txt -o /dev/null
}

mkdir -p $BUILDS
pushd $BUILDS
check_new_image overcloud-full.tar && echo "${RELEASE} images are up to date" || update_images
rm -f test_md5
popd
