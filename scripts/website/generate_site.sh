#!/bin/bash
# Copyright 2016 Red Hat, Inc.
# All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

SCRIPT_DIR=${SCRIPT_DIR:-$(dirname $0)}
SUDO_CP=${SUDO_CP:-''} # useful if you'd like to inject a SUDO command for cp
OUT_HTML=${OUT_HTML:-'out_html'}
REVIEWDAY_INPUT_FILE=${REVIEWDAY_INPUT_FILE:-"${SCRIPT_DIR}/tripleo-reviewday.yaml"}
SKIP_REVIEWDAY=${SKIP_REVIEWDAY:-''}
SKIP_CI_REPORTS=${SKIP_CI_REPORTS:-''}

# TRIPLEO-DOCS
if [ ! -d tripleo-docs ]; then
  git clone git://git.openstack.org/openstack/tripleo-docs
  pushd tripleo-docs
  tox -edocs #initial run
  popd
else
  pushd tripleo-docs
  git reset --hard origin/master
  git pull
  popd
fi

# TRIPLEO SPHINX
if [ ! -d tripleosphinx ]; then
  git clone https://github.com/dprince/tripleosphinx.git
  pushd tripleosphinx
  tox -edocs #creates the blank.html
  popd
else
  pushd tripleosphinx
  git reset --hard origin/master
  git pull
  tox -edocs #creates the blank.html
  popd
fi

# swap in custom tripleosphinx
pushd tripleo-docs
sed -e "s|oslosphinx|tripleosphinx|g" -i doc/source/conf.py
popd

#REVIEWDAY
if [ ! -d reviewday ]; then
  git clone git://git.openstack.org/openstack-infra/reviewday
else
  pushd reviewday
  git reset --hard origin/master
  git pull
  popd
fi

#TRIPLEO CI
if [ ! -d tripleo-ci ]; then
  git clone git://git.openstack.org/openstack-infra/tripleo-ci
else
  pushd tripleo-ci
  git reset --hard origin/master
  git pull
  popd
fi

#-----------------------------------------
source tripleo-docs/.tox/docs/bin/activate
pushd tripleosphinx
python setup.py install
popd
deactivate

pushd tripleo-docs
tox -edocs
popd

# Reviewday
if [ -z "$SKIP_REVIEWDAY" ]; then
  pushd reviewday
  tox -erun -- "-p $REVIEWDAY_INPUT_FILE"
  cp -a arrow* out_report/*.png out_report/*.js out_report/*.css $OUT_HTML
  DATA=$(cat out_report/data_table.html)
  OUT_FILE=~/tripleo-docs/doc/build/html/reviews.html
  TEMPLATE_FILE=~/tripleosphinx/doc/build/html/blank.html
  sed -n '1,/.*Custom Content Here/p' $TEMPLATE_FILE > $OUT_FILE #first half
  echo "<h1>TripleO Reviews</h1>" >> $OUT_FILE
  sed -e "s|<title>.*|<title>TripleO: Reviews</title>|" -i $OUT_FILE # custom title
  sed -e "s|<title>.*|<title>TripleO: Reviews</title><meta name='description' content='OpenStack Deployment Program Reviews'/>|" -i $OUT_FILE # custom title
  echo $DATA >> $OUT_FILE
  sed -n '/.*Custom Content Here/,$p' $TEMPLATE_FILE >> $OUT_FILE #second half
  popd
fi

# TripleO CI
if [ -z "$SKIP_CI_REPORTS" ]; then
  pushd tripleo-ci

  # jobs report
  tox -ecireport -- -f
  DATA=$(cat tripleo-jobs.html-table)
  OUT_FILE=~/tripleo-docs/doc/build/html/cistatus.html
  TEMPLATE_FILE=~/tripleosphinx/doc/build/html/blank.html
  sed -n '1,/.*Custom Content Here/p' $TEMPLATE_FILE > $OUT_FILE #first half
  echo "<h1>TripleO CI Status</h1>" >> $OUT_FILE
  sed -e "s|<title>.*|<title>TripleO: CI Status</title><meta name='description' content='OpenStack Deployment Program CI Status results'/>|" -i $OUT_FILE # custom title
  echo $DATA >> $OUT_FILE
  sed -n '/.*Custom Content Here/,$p' $TEMPLATE_FILE >> $OUT_FILE #second half

  # periodic jobs report
  tox -ecireport -- -f -d tripleo-periodic-jobs.db -o tripleo-periodic-jobs.html -j periodic-tripleo-ci-f22-nonha,periodic-tripleo-ci-f22-ha,periodic-tripleo-ci-f22-upgrades,periodic-tripleo-ci-f22-ha-liberty,periodic-tripleo-ci-f22-ha-mitaka
  DATA=$(cat tripleo-periodic-jobs.html-table)
  OUT_FILE=~/tripleo-docs/doc/build/html/cistatus-periodic.html
  TEMPLATE_FILE=~/tripleosphinx/doc/build/html/blank.html
  sed -n '1,/.*Custom Content Here/p' $TEMPLATE_FILE > $OUT_FILE #first half
  echo "<h1>TripleO CI Periodic Status</h1>" >> $OUT_FILE
  sed -e "s|<title>.*|<title>TripleO: CI Periodic Status</title><meta name='description' content='OpenStack Deployment Program CI Status periodic job results'/>|" -i $OUT_FILE # custom title
  echo $DATA >> $OUT_FILE
  sed -n '/.*Custom Content Here/,$p' $TEMPLATE_FILE >> $OUT_FILE #second half

  popd
fi

# Copy in the new web pages
$SUDO_CP mkdir -p $OUT_HTML
$SUDO_CP cp -a $SCRIPT_DIR/tripleo-docs/doc/build/html/* $OUT_HTML
