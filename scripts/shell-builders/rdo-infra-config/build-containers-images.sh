set -e

echo ======== BUILD CONTAINERS IMAGES

# Retrieve role
mkdir -p $WORKSPACE/roles
pushd $WORKSPACE/roles
    git clone https://github.com/rdo-infra/ansible-role-rdo-kolla-build rdo-kolla-build
popd

# Delete any leftover configuration ansible
rm -f $WORKSPACE/ansible.cfg
TESTING_TAG="tripleo-ci-testing"
# devstack gate sets this, but conflicts with anything else
unset ANSIBLE_STDOUT_CALLBACK
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_ROLES_PATH="$WORKSPACE/roles"

cat << EOF > $WORKSPACE/playbook.yml
---
- name: Build Kolla images
  hosts: localhost
  become: yes
  become_user: root
  vars:
    kolla_namespace: "$RELEASE"
    kolla_push: true
    kolla_tag: "$TESTING_TAG"
    openstack_release: "$RELEASE"
    trunk_repository: "https://trunk.rdoproject.org/centos7-$RELEASE/$TESTING_TAG/delorean.repo"
  tasks:
    - include_role:
        name: "rdo-kolla-build"
        static: "no"
EOF

ansible-playbook $WORKSPACE/playbook.yml -e kolla_threads=16

echo ======== BUILD CONTAINERS IMAGES COMPLETED
