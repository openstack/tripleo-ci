#!/usr/bin/env bash

set -x

for ID in $(virsh list --uuid --all); do
  virsh destroy $ID
  virsh undefine $ID
done
