Before Running any commands below ensure you have sourced the toci_env file

    $ cd /opt/toci
    $ . toci_env

**Q. How can I ssh to the seed vm**

A. $ ssh root@$($TOCI_WORKING_DIR/incubator/scripts/get-vm-ip seed)

**Q. How can I ssh to the undercloud controller**

A. $ ssh heat-admin@192.0.2.2

**Q. How do I list the nodes making up the overcloud**

    $ . undercloudrc
    $ nova list

**Q. How can I create more bm_poseur nodes and add them to my undercloud**

    $ . undercloudrc
    #              <cpus> <memory> <disk> <quantity>
    $ create-nodes  1      1024     10     5
    $ export MACS=$($TOCI_WORKING_DIR/bm_poseur/bm_poseur get-macs)
    $ setup-baremetal 1 768 10 all

**Q. How can I create a new image, using the elements fedora, selinux-permissive and stackuser**

A. $ ./diskimage-builder/bin/disk-image-create -a i386 -o myimage fedora selinux-permissive stackuser

**Q. I have a heat template, how can I start a stack on the undercloud using it**

    $ . undercloudrc
    $ heat stack-create -f /path/to/myheattemplate.yaml mystack

**Q. I want to rerun toci without having to build a new set of images each time.**

A. Yes, toci can apply a patch to disk-imagebuilder that will cause it place build images in a /opt/toci/image_cache, all other runs of toci will use these files instead of building a new one. To use the patch move it into the patches directory where you clone toci to.

    # Toci need to reclone disk-imagebuilder so that the patch is applied
    $ rm -rf /opt/toci/diskimage-builder
    $ cp patches_dev/diskimage-builder-0001-Save-images-in-a-toci-cache-file-or-use-if-present.patch  patches
    $ ./toci.sh

Do not forget to remove images from /opt/toci/image_cache if you change anything that would require a new image

