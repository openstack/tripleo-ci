# Periodic stable jobs set OVERRIDE_ZUUL_BRANCH, gate stable jobs
# just have the branch they're proposed to, e.g ZUUL_BRANCH, in both
# cases we need to set STABLE_RELEASE to match for tripleo.sh
export ZUUL_BRANCH=${ZUUL_BRANCH:-""}
export OVERRIDE_ZUUL_BRANCH=${OVERRIDE_ZUUL_BRANCH:-""}
export STABLE_RELEASE=
if [[ $ZUUL_BRANCH =~ ^stable/ ]]; then
    export STABLE_RELEASE=${ZUUL_BRANCH#stable/}
fi

if [[ $OVERRIDE_ZUUL_BRANCH =~ ^stable/ ]]; then
    export STABLE_RELEASE=${OVERRIDE_ZUUL_BRANCH#stable/}
fi

export TRIPLEO_ROOT=/opt/stack/new
export PATH=/sbin:/usr/sbin:$PATH

# post ci chores to run at the end of ci
SSH_OPTIONS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=Verbose -o PasswordAuthentication=no -o ConnectionAttempts=32'
TARCMD="sudo XZ_OPT=-3 tar -cJf - --exclude=udev/hwdb.bin --exclude=etc/services --exclude=selinux/targeted --exclude=etc/services --exclude=etc/pki /var/log /etc"
