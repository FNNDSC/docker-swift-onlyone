#!/bin/bash

#
# Make the rings if they don't exist already
#

# These can be set with docker run -e VARIABLE=X at runtime
SWIFT_PART_POWER=${SWIFT_PART_POWER:-7}
SWIFT_PART_HOURS=${SWIFT_PART_HOURS:-1}
SWIFT_REPLICAS=${SWIFT_REPLICAS:-1}

if [ -e /srv/account.builder ]; then
	echo "Ring files already exist in /srv, copying them to /etc/swift..."
	cp /srv/*.builder /etc/swift/
	cp /srv/*.gz /etc/swift/
else
	echo "No existing ring files, creating them..."

	(
	cd /etc/swift

	# 2^& = 128 we are assuming just one drive
	# 1 replica only

	swift-ring-builder object.builder create ${SWIFT_PART_POWER} ${SWIFT_REPLICAS} ${SWIFT_PART_HOURS}
	swift-ring-builder object.builder add r1z1-127.0.0.1:6010/sdb1 1
	swift-ring-builder object.builder rebalance
	swift-ring-builder container.builder create ${SWIFT_PART_POWER} ${SWIFT_REPLICAS} ${SWIFT_PART_HOURS}
	swift-ring-builder container.builder add r1z1-127.0.0.1:6011/sdb1 1
	swift-ring-builder container.builder rebalance
	swift-ring-builder account.builder create ${SWIFT_PART_POWER} ${SWIFT_REPLICAS} ${SWIFT_PART_HOURS}
	swift-ring-builder account.builder add r1z1-127.0.0.1:6012/sdb1 1
	swift-ring-builder account.builder rebalance
	)

 	# Back these up for later use
 	echo "Copying ring files to /srv to save them if it's a docker volume..."
 	cp /etc/swift/*.gz /srv
 	cp /etc/swift/*.builder /srv
fi

# Ensure device exists
mkdir -p /srv/devices/sdb1

# Ensure that supervisord's log directory exists
mkdir -p /var/log/supervisor

# Ensure that files in /srv are owned by swift.
chown -R swift:swift /srv

# If you are going to put an ssl terminator in front of the proxy, then I believe
# the storage_url_scheme should be set to https. So if this var isn't empty, set
# the default storage url to https.
if [ ! -z "${SWIFT_STORAGE_URL_SCHEME}" ]; then
	echo "Setting default_storage_scheme to https in proxy-server.conf..."
	sed -i -e "s/storage_url_scheme = default/storage_url_scheme = https/g" /etc/swift/proxy-server.conf
	grep "storage_url_scheme" /etc/swift/proxy-server.conf
fi

if [ ! -z "${SWIFT_SET_PASSWORDS}" ]; then
	echo "Setting passwords in /etc/swift/proxy-server.conf..."
	PASS=`pwgen 12 1`
	sed -i -e "s/user_admin_admin = admin .admin .reseller_admin/user_admin_admin = $PASS .admin .reseller_admin/g" /etc/swift/proxy-server.conf
	sed -i -e "s/user_chris_chris1234 = testing .admin/user_chris_chris1234 = $PASS .admin/g" /etc/swift/proxy-server.conf
	grep "user_chris" /etc/swift/proxy-server.conf
fi

# Start supervisord
echo "Starting supervisord..."
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf

# Create default container
if [ ! -z "${SWIFT_DEFAULT_CONTAINER}" ]; then
	echo "Creating default container..."
	for container in ${SWIFT_DEFAULT_CONTAINER} ; do
	    echo "Creating container...${container}"
	    swift -A http://localhost:8080/auth/v1.0 -U chris:chris1234 -K testing post ${container}
	done
fi

# Create meta-url-key to allow temp download url generation
if [ ! -z "${SWIFT_TEMP_URL_KEY}" ]; then
  echo "Setting X-Account-Meta-Temp-URL-Key..."
  swift -A http://localhost:8080/auth/v1.0 -U chris:chris1234 -K testing post -m "Temp-URL-Key:${SWIFT_TEMP_URL_KEY}"
fi

#
# Tail the log file for "docker log $CONTAINER_ID"
#

echo "Starting to tail /var/log/syslog...(hit ctrl-c if you are starting the container in a bash shell)"
exec tail -n 0 -F /var/log/syslog
