#!/usr/bin/env bash

set -x

for ID in $(virsh list --uuid --all); do
  virsh destroy $ID
  virsh undefine --remove-all-storage $ID
done
