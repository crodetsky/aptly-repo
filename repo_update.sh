#!/usr/bin/env bash

# Mirror repository
UPSTREAM_URL="http://raspbian.raspberrypi.org/raspbian/"
REPO=raspbian
DISTS=( buster )
COMPONENTS=( main contrib non-free rpi )
ARCH=armhf
GNUPGHOME=/opt/aptly/gpg
echo "Creating mirror of ${REPO} repository."
for dist in ${DISTS[@]}; do
  echo "Updating ${REPO} repository mirror.."
  /opt/aptly/aptly mirror update ${REPO}-${dist}
  echo "Creating snapshot of ${REPO}-${dist} repository mirror.."
  SNAPSHOT=${REPO}-${dist}-`date +%s%N`
  SNAPSHOTARRAY+="${SNAPSHOT} "
  /opt/aptly/aptly snapshot create ${SNAPSHOT} from mirror ${REPO}-${dist}
done
echo "Publishing snapshots."
for snap in ${SNAPSHOTARRAY[@]}; do
  dist=$(echo ${snap} | sed "s/^${REPO}-\(.*\)-[^-]*\$/\1/")
  /opt/aptly/aptly publish list -raw | grep "^${REPO} ${dist}$"
  if [[ $? -eq 0 ]]; then
    /opt/aptly/aptly publish switch \
      -batch -passphrase-file=/etc/aptly.pass ${dist} ${REPO} ${snap}
  else
    # Keys must be before name of a snapshot
    # -distribution=${REPO_MERGED} - it can be missed
    /opt/aptly/aptly publish snapshot \
      -batch -passphrase-file=/etc/aptly.pass ${snap} ${REPO}
  fi
done
