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
SKIP_BLOG=${SKIP_BLOG:-''}

# TRIPLEO-DOCS
if [ ! -d tripleo-docs ]; then
    git clone https://opendev.org/openstack/tripleo-docs
    pushd tripleo-docs
    tox -edocs #initial run
    popd
else
    pushd tripleo-docs
    git reset --hard origin/master
    git pull
    # NOTE(bnemec): We need to rebuild this venv each time or changes to
    # tripleosphinx won't be picked up.
    tox -re docs
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
sed -e "s|openstackdocstheme|tripleosphinx|g" -i doc/source/conf.py
sed -e "s|html_theme.*||g" -i doc/source/conf.py
popd

#REVIEWDAY
if [ ! -d reviewday ]; then
    git clone https://opendev.org/openstack/reviewday
else
    pushd reviewday
    git reset --hard origin/master
    git pull
    popd
fi

#TRIPLEO CI
if [ ! -d tripleo-ci ]; then
    git clone https://opendev.org/openstack/tripleo-ci
else
    pushd tripleo-ci
    git reset --hard origin/master
    git pull
    popd
fi

#Planet (Blog Feed Aggregator)
PLANET_DIR='planet-venus'
if [ ! -d '$PLANET_DIR' ]; then
    git clone https://github.com/rubys/venus.git $PLANET_DIR
else
    pushd $PLANET_DIR
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

$SUDO_CP mkdir -p $OUT_HTML

# Reviewday
if [ -z "$SKIP_REVIEWDAY" ]; then
    pushd reviewday
    tox -erun -- "-p$REVIEWDAY_INPUT_FILE"
    $SUDO_CP cp -a arrow* out_report/*.png out_report/*.js out_report/*.css $OUT_HTML
    DATA=$(cat out_report/data_table.html)
    popd
    OUT_FILE=$SCRIPT_DIR/tripleo-docs/doc/build/html/reviews.html
    TEMPLATE_FILE=$SCRIPT_DIR/tripleosphinx/doc/build/html/blank.html
    sed -n '1,/.*Custom Content Here/p' $TEMPLATE_FILE > $OUT_FILE #first half
    echo "<h1>TripleO Reviews</h1>" >> $OUT_FILE
    sed -e "s|<title>.*|<title>TripleO: Reviews</title>|" -i $OUT_FILE # custom title
    sed -e "s|<title>.*|<title>TripleO: Reviews</title><meta name='description' content='OpenStack Deployment Program Reviews'/>|" -i $OUT_FILE # custom title
    echo "$DATA" >> $OUT_FILE
    sed -n '/.*Custom Content Here/,$p' $TEMPLATE_FILE >> $OUT_FILE #second half
fi

# TripleO CI
if [ -z "$SKIP_CI_REPORTS" ]; then
    pushd tripleo-ci

    # jobs report
    tox -ecireport -- -b '^.*'
    DATA=$(cat tripleo-jobs.html-table)
    popd
    OUT_FILE=$SCRIPT_DIR/tripleo-docs/doc/build/html/cistatus.html
    TEMPLATE_FILE=$SCRIPT_DIR/tripleosphinx/doc/build/html/blank.html
    sed -n '1,/.*Custom Content Here/p' $TEMPLATE_FILE > $OUT_FILE #first half
    echo "<h1>TripleO CI Status</h1>" >> $OUT_FILE
    sed -e "s|<title>.*|<title>TripleO: CI Status</title><meta name='description' content='OpenStack Deployment Program CI Status results'/>|" -i $OUT_FILE # custom title
    echo "$DATA" >> $OUT_FILE
    sed -n '/.*Custom Content Here/,$p' $TEMPLATE_FILE >> $OUT_FILE #second half
fi

# Planet
if [ -z "$SKIP_BLOG" ]; then
    cp $SCRIPT_DIR/tripleo-ci/scripts/website/planet* $SCRIPT_DIR/$PLANET_DIR
    pushd $SCRIPT_DIR/$PLANET_DIR
    mkdir output
    rm planet.html.tmplc # cleanup from previous runs
    python planet.py planet.config.ini
    popd
    DATA=$(cat $PLANET_DIR/output/planet.html)
    OUT_FILE=$SCRIPT_DIR/tripleo-docs/doc/build/html/planet.html
    TEMPLATE_FILE=$SCRIPT_DIR/tripleosphinx/doc/build/html/blank.html
    sed -n '1,/.*Custom Content Here/p' $TEMPLATE_FILE > $OUT_FILE #first half
    echo "<h1>Planet TripleO</h1>" >> $OUT_FILE
    sed -e "s|<title>.*|<title>Planet TripleO</title><meta name='description' content='OpenStack Deployment Program Planet'/>|" -i $OUT_FILE # custom title
    echo "$DATA" >> $OUT_FILE
    sed -n '/.*Custom Content Here/,$p' $TEMPLATE_FILE >> $OUT_FILE #second half
fi

# Copy in the new web pages
$SUDO_CP cp -a $SCRIPT_DIR/tripleo-docs/doc/build/html/* $OUT_HTML
