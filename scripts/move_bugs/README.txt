# https://help.launchpad.net/API/launchpadlib
# https://help.launchpad.net/API/ThirdPartyIntegration

# setup a python virtenv, WITH site-packages
virtualenv --python /usr/bin/python2.7 /home/whayutin/virtualenv/python2 --system-site-packages


python
keyring.set_password("app_name", "oauthkey", "oauthpass")
from launchpadlib.launchpad import Launchpad
launchpad = Launchpad.login_with('app_name', 'production')

# follow the promps, auth for a short time.
python move_bugs.py tripleo ussuri-2 ussuri-3
# move all the bugs w/o criteria for milestone
python --no-dry-run tripleo ussuri-2 ussuri-3

# due to paging etc, you'll have to run
# the command a few times


Other Notes:
<EmilienM> git clone https://github.com/openstack/release-tools
[13:39:20] <EmilienM> cd release-tools
[13:39:22] <EmilienM> git checkout 8a69cd398af69768221109a7e12c1755e5a2c4eb
[13:39:26] <EmilienM> ./process_bugs.py tripleo --milestone ussuri-1 --settarget ussuri-2
[13:39:43] <EmilienM> repeat a lot of times until there is no more bugs to process (launchpad would limit you)
[13:39:47] <EmilienM> and once it's done, that's it
[13:39:55] <EmilienM> don't forget to close the milestone in LP
[13:39:57] <EmilienM> weshay: ^
[13:40:34] <mwhahaha> weshay: for milestones i just move them all
[13:40:42] <weshay> k.. thanks
[13:40:53] <mwhahaha> weshay: i only use priority when RC time to move all but like the high/critical
[13:40:57] <weshay> aye
