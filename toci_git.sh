#!/usr/bin/env bash

set -xe
. toci_functions.sh

# Get the tripleO repo's
for repo in 'openstack/tripleo-incubator' 'tripleo/bm_poseur' 'stackforge/diskimage-builder' 'stackforge/tripleo-image-elements' 'stackforge/tripleo-heat-templates' ; do
    if [ ${TOCI_GIT_CHECKOUT:-1} == 1 ] ; then
      get_get_repo $repo
    else
      if [ ! -d "$TOCI_WORKING_DIR/$repo" ]; then
        echo "Please checkout $repo to $TOCI_WORKING_DIR or enabled TOCI_GIT_CHECKOUT."
      fi
    fi
done

# Get a local copy of each of the git repositories  referenced in
REGEX="^([^ ]+) (git|tar) ([/~][^ ]+) ([^ ]+) ?([^ ]*)$"
for sr in $TOCI_WORKING_DIR/*/elements/*/source-repository* ; do
    while read line ; do
        # ignore blank lines and lines begining in '#'
        [[ "$line" == \#* ]] || [[ -z "$line" ]] && continue
        if [[ "$line" =~ $REGEX ]]  ; then
            REPONAME=${BASH_REMATCH[1]//-/_}
            REPOTYPE=${BASH_REMATCH[2]}
            REPOLOCATION=${BASH_REMATCH[4]}
            REPOREF=${BASH_REMATCH[5]:-master}

            REPOREF_OVERRIDE=TOCI_REPOREF_$REPONAME
            REPOREF=${!REPOREF_OVERRIDE:-$REPOREF}

            REPO_DIRECTORY=$TOCI_WORKING_DIR/$REPONAME

            if [ $REPOTYPE = git ] ; then
                if [ ! -e $REPO_DIRECTORY ] ; then
                    git clone $REPOLOCATION $REPO_DIRECTORY
                    pushd $REPO_DIRECTORY
                    git reset --hard $REPOREF
                    popd
                fi
            else
                echo "Unsupported repository type"
            fi
        else
            echo "Couldn't parse '$line' as a source repository"
            return 1
        fi
    done < $sr
done
