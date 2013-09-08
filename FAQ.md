Before Running any commands below ensure you have sourced the toci_env file

    $ cd /opt/toci
    $ . toci_env

**Q. How can I ssh to the seed vm**

```
$ ssh root@$($TOCI_WORKING_DIR/incubator/scripts/get-vm-ip seed)
```

**Q. How can I ssh to the undercloud controller**
```
$ ssh heat-admin@192.0.2.2
```

**Q. How do I list the nodes making up the overcloud**
```
    $ . undercloudrc
    $ nova list
```

**Q. How can I create more bm_poseur nodes and add them to my undercloud**
```
    $ . undercloudrc
    #              <cpus> <memory> <disk> <architecture> <quantity>
    $ create-nodes  1      1024     10     i386           5
    $ export MACS=$($TOCI_WORKING_DIR/bm_poseur/bm_poseur get-macs)
    $ setup-baremetal 1 768 10 i386 all
```

**Q. How can I create a new image, using the elements fedora, 
     selinux-permissive and stackuser**
```
 $ ./diskimage-builder/bin/disk-image-create -a i386 -o myimage fedora selinux-permissive stackuser
```

**Q. I have a heat template, how can I start a stack on the undercloud using
     it**
```
    $ . undercloudrc
    $ heat stack-create -f /path/to/myheattemplate.yaml mystack
```

**Q. I want to rerun toci without having to build a new set of images each
     time.**

Yes, toci can apply a patch to disk-imagebuilder that will cause it place
build images in a /opt/toci/image_cache, all other runs of toci will use
these files instead of building a new one. To use the patch move it into
the patches directory where you clone toci to.
```
    $ cp patches_dev/diskimage-builder-0001-Save-images-in-a-toci-cache-file-or-use-if-present.patch  patches
```

Do not forget to remove images from /opt/toci/image_cache if you change
anything that would require a new image build

**Q. There is a new version of diskimage-builder I want to update to and use it
     to rebuild images**
```
    $ rm -rf /opt/toci/diskimage-builder
    $ ./toci.sh
```

**Q. I would like to redeploy tripleo with a patch that has been submitted to
     nova**
```
    $ cd /opt/toci/nova
    # You can get the git reference from the patchset in gerrit
    $ git fetch https://review.openstack.org/openstack/nova refs/changes/36/45536/1
    $ git reset --hard FETCH_HEAD
    $ cd /path/to/toci

    # Remove /opt/toci/image_cache/* if you are using the image caching described above

    # Run toci
    $ ./toci.sh
```
**Q. My toci run failed which logfile should I be looking in?**

Toci gathers various log file into a single directory (ouput at the start
of the run), the content of this directory typically looks like this.
```
./git.out                       - output from various git commands as they clone the repositories
./error-applying-patches.log    - if this exists a patch from the patches directory failed to apply
./setup.out                     - output from toci_setup.sh
./test.out                      - output from toci_test.sh
./cleanup.out                   - output from tcoi_cleanup.sh
./192.168.122.218.tgz           - tarball of /var/logs and /etc on seed VM
./192.0.2.2.tgz                 - tarball of /var/logs and /etc on undercloud
./192.0.2.5.tgz                 - tarball of /var/logs and /etc on overcloud notcompute
```
Some of these files may not exist if toci failed to complete
