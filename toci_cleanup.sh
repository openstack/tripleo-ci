#!/usr/bin/env bash

set -x

for NAME in $(sudo virsh list --name --all | grep "^\(seed\|bootstrap\|baremetal_.*\)$"); do
  sudo virsh destroy $NAME
  sudo virsh undefine --remove-all-storage $NAME
done

for NAME in $(virsh vol-list default | grep /var/ | awk '{print $1}' | grep "^\(seed\|bootstrap\|baremetal-\)" ); do
  sudo virsh vol-delete --pool default $NAME
done
