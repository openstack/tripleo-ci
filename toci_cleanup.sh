#!/usr/bin/env bash

set -x

for NAME in $(sudo virsh list --name --all | grep "^\(bootstrap\|baremetal_[0-9]\)$"); do
  echo sudo virsh destroy $NAME
  echo sudo virsh undefine --remove-all-storage $NAME
done
