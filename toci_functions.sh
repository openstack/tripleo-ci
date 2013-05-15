
get_get_repo(){
    CACHDIR=$TOCI_CACHE_DIR/${1/\//_}
    if [ ! -e $CACHDIR ] ; then
        git clone https://github.com/$1.git $CACHDIR
    else
        cd $CACHDIR
        git fetch
        git reset --hard origin/master
    fi
    cp -r $CACHDIR $TOCI_WORKING_DIR/${1/\//_}
}
