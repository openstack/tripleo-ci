#!/bin/bash

curl -L https://trunk.rdoproject.org/centos7-master/current-tripleo/delorean.repo > /etc/yum.repos.d/delorean.repo
curl -L https://trunk.rdoproject.org/centos7/delorean-deps.repo > /etc/yum.repos.d/delorean-deps.repo

yum install -y python-pip python-heatclient python-neutronclient python-novaclient python-swiftclient python-openstackclient

pip install gear

BASEPATH=$(realpath $(dirname $0))

cp $BASEPATH/geard.service /lib/systemd/system/geard.service
cp $BASEPATH/te_workers.service /lib/systemd/system/te_workers.service

