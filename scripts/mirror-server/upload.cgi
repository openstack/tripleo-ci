#!/bin/python3.4

import cgi
import cgitb
import fcntl
import os
import shutil
import sys
import tempfile

basedir="/var/www/html/builds"

print("Content-Type: text/html\n")
def saveform(form, storagedir):
    for key in form.keys():
        entry = form[key]
        if not isinstance(entry.value, str):
            # Ensure no directory entries sneak in
            filename = os.path.split(entry.filename)[1]
            filename = os.path.join(storagedir, filename)
            if os.path.exists(filename):
                print ("allready received %s" % entry.filename)
                continue

            fp = tempfile.NamedTemporaryFile(delete=False)
            count = 1
            while count > 0:
                data = entry.file.read(1024 * 16)
                count = fp.write(data)
            fp.close()
            shutil.move(fp.name, filename)
        else:
            line = "%s=%s\n" % (entry.name, entry.value)
            fp = open(os.path.join(storagedir, "metadata.txt"), "a+")
            if line not in fp.read():
                fp.write(line)
            fp.close()

def run():

    if not os.environ.get("REMOTE_ADDR", "").startswith("192.168.1."):
        print("File uploads only allowed from the tripleo test network")
        return 1

    form = cgi.FieldStorage()
    try:
        repohash = form["repohash"].value
    except KeyError:
        print("repohash missing")
        return 1

    storagedir = os.path.abspath(os.path.join(basedir,repohash))
    if basedir not in storagedir:
        print("incorrect hash")
        return 1

    try:
        os.makedirs(storagedir)
    except FileExistsError:
        pass

    fd = os.open("/tmp/lock", os.O_WRONLY | os.O_CREAT)
    fcntl.lockf(fd, fcntl.LOCK_EX)
    try:
        saveform(form, storagedir)
    finally:
        fcntl.lockf(fd, fcntl.LOCK_UN)
        os.close(fd)

sys.exit(run())

