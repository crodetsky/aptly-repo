#!/usr/bin/env bash

echo "Installing prerequisites"
dnf -y install \
  nginx \
  gnupg2 \

echo "Installing Aptly"
if [ ! -d /opt/aptly ]; then
  mkdir -p /opt/aptly
wget https://github.com/aptly-dev/aptly/releases/download/v1.4.0/aptly_1.4.0_linux_amd64.tar.gz
semanage fcontext -a -t httpd_sys_content_t '/opt/aptly(/.*)?'
restorecon -vvRF /opt/aptly
tar zxf aptly_1.4.0_linux_amd64.tar.gz
cp aptly_1.4.0_linux_amd64/* /opt/aptly

echo "Copying configuration"
cp aptly.conf /etc/aptly.conf
cp nginx.conf /etc/nginx/nginx.conf
cp default.conf /etc/nginx/conf.d/default.conf

# Setup Signing Key
GNUPGHOME=/opt/aptly/gpg
if [[ ! -d /opt/aptly/gpg/private-keys-v1.d/ ]] || [[ ! -f /opt/aptly/gpg/pubring.kbx ]]; then
  echo -n "Enter full name for GPG signing key: "
  read FULL_NAME
  echo -n "Enter email: "
  read EMAIL_ADDRESS
  echo -n "Enter passphase: "
  read -s GPG_PASSPHRASE
  echo $GPG_PASSPHRASE > /etc/aptly.pass
  echo "Generating the new GPG keypair."
  cp -a /dev/urandom /dev/random
  mkdir -p /opt/aptly/gpg
  chmod 600 /opt/aptly/gpg
  gpg2 --batch --passphrase "${GPG_PASSPHRASE}" --quick-gen-key "${FULL_NAME} <${EMAIL_ADDRESS}>" default default 0
else
  echo "No need to generate the new GPG keypair"
fi

# Mirror repository
UPSTREAM_URL="http://raspbian.raspberrypi.org/raspbian/"
REPO=raspbian
DISTS=( buster )
COMPONENTS=( main contrib non-free rpi )
ARCH=armhf
echo "Creating mirror of ${REPO} repository."
gpg --no-default-keyring --keyring /opt/aptly/gpg/trustedkeys.gpg --keyserver pool.sks-keyservers.net --recv-keys 9165938D90FDDD2E
for dist in ${DISTS[@]}; do
  echo "Creating mirror of ${REPO}-${dist}"
  /opt/aptly/aptly mirror create \
    -architectures=${ARCH} \
    ${REPO}-${dist} ${UPSTREAM_URL} \
    ${dist} ${COMPONENTS[@]}
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

echo "Starting nginx."
systemctl start nginx
systemctl enable nginx

echo "Allowing http through firewall."
firewall-cmd --zone=public --add-service http

echo "Cleaning up"
rm aptly_1.4.0_linux_amd64.tar.gz
rm -rf aptly_1.4.0_linux_amd64
rm -rf docker-aptly
