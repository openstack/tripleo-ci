#!/usr/bin/env bash

set -x

for ID in $(sudo virsh list --uuid --all); do
  sudo virsh destroy $ID
  sudo virsh undefine --remove-all-storage $ID
done
