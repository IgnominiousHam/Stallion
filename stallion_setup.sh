#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Try as root..."
    exit 1
fi


cd /root
read -p "Non-Root User: " user
read -p "AP SSID: " ssid
read -p "AP Password: " password

#Logging options selection
options=("kismet" "pcapppi" "pcapng" "wiglecsv")

echo "Available Kismet logging types:"
for i in "${!options[@]}"; do
    printf "%d) %s\n" "$((i+1))" "${options[$i]}"
done

read -p "Enter the numbers of the logging types you want (e.g., 1,3,4): " input

IFS=',' read -ra selected_indices <<< "$input"

selected_types=()
for index in "${selected_indices[@]}"; do
    idx=$((index - 1))
    if [[ $idx -ge 0 && $idx -lt ${#options[@]} ]]; then
        selected_types+=("${options[$idx]}")
    else
        echo "Invalid selection: $index"
    fi
done

echo "Selected logging types:"
for type in "${selected_types[@]}"; do
    echo "- $type"
done

log_types=$(IFS=, ; echo "${selected_types[*]}")

#Interface setup
echo ""

interfaces=($(iw dev | awk '$1=="Interface"{print $2}' | grep -v "^wlan0$"))

if [ ${#interfaces[@]} -eq 0 ]; then
    echo "No interfaces found..."
    exit 1
fi

echo "Available interfaces:"
select interface in "${interfaces[@]}"; do
    if [[ -n "$interface" ]]; then
        break
    else
        echo "Invalid selection."
    fi
done

interface_mac=$(cat /sys/class/net/"$interface"/address)

read -p "Persistent interface name: " interface_name

dest_path="/etc/udev/rules.d/70-persistent-net.rules"
cat > $dest_path << EOF
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="$interface_mac", NAME="$interface_name"
EOF

apt update

#AP setup
raspi-config nonint do_wifi_country US
nmcli con add con-name hotspot ifname wlan0 type wifi ssid "$ssid" 
nmcli con modify hotspot wifi-sec.key-mgmt wpa-psk
nmcli con modify hotspot wifi-sec.psk "$password"
nmcli con modify hotspot 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared

#Kismet
wget -O - https://www.kismetwireless.net/repos/kismet-release.gpg.key --quiet | gpg --dearmor | sudo tee /usr/share/keyrings/kismet-archive-keyring.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/kismet-archive-keyring.gpg] https://www.kismetwireless.net/repos/apt/release/bookworm bookworm main' | sudo tee /etc/apt/sources.list.d/kismet.list >/dev/null
apt update
apt install -y kismet gpsd gpsd-clients virtualenv git
usermod -aG kismet $user

#Kismet_web_rssi-bar
git clone https://github.com/GrokkedBandwidth/kismet_web_rssi-bar
cd kismet_web_rssi-bar
virtualenv .venv
source .venv/bin/activate
pip install -r requirements.txt
deactivate

#Kismet configuration
cat > "/etc/kismet/kismet_logging.conf" <<EOF
# Kismet logging configuration
#
# This configuration file is part of the Kismet configuration.  It is loaded
# by the kismet.conf main configuration file.
#
# For more information about the configuration options, see the comments in this
# file and the documentation at:
# https://www.kismetwireless.net/docs/readme/config_files/
#
# You can edit the values in these files, but to make it much easier to update Kismet
# in the future, you should put your changes in the kismet_site.conf override file.
# You can learn more about the override config at:
# https://www.kismetwireless.net/docs/readme/config_files/#configuration-override-files---kismet_siteconf

# Generally speaking, the individual options for logging should not need to be 
# modified, but in specific cases it may be valuable to disable log types.

# All logs can be disabled; this will disable logging system-wide.  Generally this
# should be left set to 'true'; logging can be turned off when Kismet is started 
# with the '-n' command line argument
enable_logging=true


# Default log title, can be overridden with the '-t' argument to Kismet
log_title=Kismet

# Default location for logs; by default this is the directory Kismet was launched
# in, but the logs can be automatically stored in other directories as well.
# The directory must exist before Kismet is started - Kismet will /not/ create
# the directory list itself.
log_prefix=/home/$user/logs/


# Logging is enabled by type; plugins may add additional types.  The log types can be
# overridden on the command line with the '--log-types' argument.
#
# Built-in log types (plugins may add more, consult the documentation for plugins):
#   kismet      Unified log which can be turned into multiple types of data
#   pcapppi     Old-style pcap with PPI headers for signal and metadata.  Not as
#               flexible as the pcapng format.
#   pcapng      Pcap-NG (suitable for use with Wireshark and Tshark, as well as other
#               tools) which contains raw pcap data with interface tags.  See the 
#               Kismet readme for methods to turn this into an old-style pcap log.
#
# By default, Kismet only enabled the unified 'kismet' log; the pcapng option is
# provided for special configurations as a legacy fallback mode.
log_types=$log_types


# Log naming template - Kismet can automatically generate a number of variations
# on the log.  Like many of these options, it typically should not be necessary to
# change this.
#
# By default, Kismet will log files as:
# {prefix}/{title}-{YYYYMMDD}-{HH-MM-SS}-{#}.{type}
#
# %p is replaced by the logging prefix + '/'
# %n is replaced by the logging title (-t cmdline)
# %d is replaced by the starting date as Mmm-DD-YYYY
# %D is replaced by the current date as YYYYMMDD
# %t is replaced by the starting time as HH-MM-SS
# %T is replaced by the starting time as HHMMSS
# %i is replaced by the log number if multiple logs of the same name are found
# %I is replaced by the increment log, padded with zeroes
# %l is replaced by the log type (kislog, pcap, etc)
# %h is replaced by the home directory
log_template=%p/%n-%D-%t-%i.%l

# Within the 'kismet' log type, many types of data can be logged.  Generally 
# these should be left on, they are used to generate 


# Kismetdb is the modern log format; it contains in a single file all the previous
# logs, and can be manipulated with the kismetdb_to_xyz tools included in Kismet

# Devices are logged as complete objects.  Device logs are used to generate text 
# summaries of devices Kismet has seen, or to create reports.  Generally, you 
# will want to leave device logging enabled.
kis_log_devices=true

# Devices are logged at regular intervals; by default, every 30 seconds. This rate
# can be tuned for specific system requirements.
kis_log_device_rate=30

# Packet logging allows the generation of pcap files and post-processing of the
# packets seen by Kismet.  Generally, this should be left set to true.  This setting
# also controls the logging of packet-like metadata (such as spectrum sweeps and
# similar)
kis_log_packets=true

# Log duplicate packets in the kismetdb log.  Kismet filters duplicate packets captured by
# multiple interfaces; for doing advanced signal analysis, keeping the duplicates can be
# useful
#
# By default, Kismet logs duplicate packets.  This can be turned off for size.
# kis_log_duplicate_packets=true

# Some protocols (like Wi-Fi) make a distinction between management and data packets.
#
# By default, Kismet logs all packets seen.  This can be turned off for size, however 
# it means the data packets will not be available for analysis.
kis_log_data_packets=true

# Message logging saves any messages displayed on the console where Kismet was
# launched or in the messages tab of the UI
kis_log_messages=true

# Alert logging saves any alerts generated
kis_log_alerts=true

# All connected data sources are logged at regular intervals
kis_log_datasources=true

# By default, data source records are generated once per minute
kis_log_datasources_rate=30

# Channel history is logged at regular intervals
kis_log_channel_history=true

# By default, channel history is logged every 20 seconds
kis_log_channel_history_rate=20

# By default, the current GPS location of all known GPS devices is
# logged once a second
kis_log_gps_track=true

# By default log a system status including device count, memory, and temperatures
kis_log_system_status=true

# How often to log system status, in seconds
kis_log_system_status_rate=30

# For some long-running stationary Kismet setups, the kismetdb log can be used as 
# a rolling backlog of data.  
# Packets, snapshots, messages, alerts, and devices older than the timeout will
# be *REMOVED FROM THE KISMETDB LOG* at regular intervals.
# The timeout is in seconds, so for 24 hours, 60*60*24 or 86400.
# This can be combined with the ephemeral option to make a rolling log which is
# NOT PRESERVED when Kismet exits.
#
# kis_log_alert_timeout=86400
# kis_log_device_timeout=86400
# kis_log_message_timeout=86400
# kis_log_packet_timeout=86400
# kis_log_snapshot_timeout=86400

# Flag the log as ephemeral.  The log will be removed after being opened; this
# will result in the log BEING LOST IMMEDIATELY UPON KISMET EXITING.  This 
# should be combined with a kis_log_packet_timeout, and is ONLY for
# long-running kismet sensors which will be polled via the REST API.
# kis_log_ephemeral_dangerous=false


# The PcapNG logfile is a pcapng formatted log.  Pcapng allows for multiple interfaces
# of multiple types, with the original packet headers.  This is the most complete
# log format besides kismetdb, and is supported by modern tools like Wireshark, however
# some older tools which have not been updated to read pcapng may not be able to 
# read them.  Pcapng can be converted with wireshark and tshark into individual
# capture files.

# By default, Kismet logs duplicate packets.  This can be turned off for size.
pcapng_log_duplicate_packets=true

# Some protocols (like Wi-Fi) make a distinction between management and data packets.
#
# By default, Kismet logs all packets seen.  This can be turned off for size, however 
# it means the data packets will not be available for analysis.
pcapng_log_data_packets=true


# The PPI logfile is a pcap formatted log, primarily for Wi-Fi packets, which includes
# the PPI per-packet header.  Packets are adjusted to fit the PPI header format, which
# may remove some capture metadata.  In general, the pcapng format is preferred.

# By default, Kismet logs duplicate packets.  This can be turned off for size.
ppi_log_duplicate_packets=true

# Some protocols (like Wi-Fi) make a distinction between management and data packets.
#
# By default, Kismet logs all packets seen.  This can be turned off for size, however 
# it means the data packets will not be available for analysis.
ppi_log_data_packets=true


# Flag to raise a warning for users who haven't upgraded
log_config_present=true

EOF


cat > "/etc/kismet/kismet.conf" <<EOF
# Kismet config file

# This master config file loads the other configuration files; to learn more about
# the Kismet configuration options, see the comments in the config files, and
# the documentation at:
# https://www.kismetwireless.net/docs/readme/config_files/
#
# You can edit the values in these files, but to make it much easier to update Kismet
# in the future, you should put your changes in the kismet_site.conf override file.
# You can learn more about the override config at:
# https://www.kismetwireless.net/docs/readme/config_files/#configuration-override-files---kismet_siteconf



# Include optional packaging config; this config file is optional and can be provided
# by the Kismet package; for example on OpenWRT this could restrict the memory use
# by default.
opt_override=%E/kismet_package.conf



# Include optional site-specific override configurations.  These options will
# are loaded AT THE END of config file loading, and OVERRIDE ANY OTHER OPTIONS
# OF THE SAME NAME.
#
# This file can be used to customize server installations or apply a common
# config across many Kismet installs.
opt_override=%E/kismet_site.conf


# Kismet can report basic server information in the status response, this
# can be used in some situations where you are running multiple Kismet
# instances.
#
# server_name=Kismet
# server_description=A Kismet server on a thing
# server_location=Main office


# Include the httpd config options
# %E is expanded to the system etc path configured at install
include=%E/kismet_httpd.conf

# Include the memory tuning options
include=%E/kismet_memory.conf

# Include the alert config options
include=%E/kismet_alerts.conf

# Include 802.11-specific options
include=%E/kismet_80211.conf

# Include logging options
include=%E/kismet_logging.conf

# Include filter options
include=%E/kismet_filter.conf

# Include UAV drone configs
include=%E/kismet_uav.conf


# Path that helper and capture binaries can be found in; for security, Kismet will
# only support binaries in these paths.  Multiple paths can be specified via multiple
# helper_binary_path options.
# By default, Kismet looks in the directory kismet installs into, controlled with
# the ./configure option --bindir
# Plugins may also look in their own directories if installed via usermode.
helper_binary_path=%B




# Kismet can announce itself via broadcast packets for automatic remote capture
# discovery; by default this is off; Check the Kismet README for more information
# and security concerns!
server_announce=false
server_announce_address=0.0.0.0
server_announce_port=2501




# Kismet can accept connections from remote capture datasources; by default this 
# is enabled on the loopback interface *only*.  It's recommended that the remote
# capture socket stay bound to the loopback local interface, and additional
# authentication - such as SSH tunnels - is used.  Check the Kismet README for
# more information about setting up remote capture securely!
# 
# Remote capture can be completely disabled with remote_capture_enabled=false
remote_capture_enabled=true
remote_capture_listen=127.0.0.1
remote_capture_port=3501



# Datasource types can be masked from the probe and list subsystems; this is primarily
# for use on systems where loading some datasource types causes problems due to speed
# or memory, such as very small embedded systems.
# A masked datasource type will NOT be found automatically and will NOT be listed in
# the datasources window as an available source, however it MAY be specified with
# a type=xyz on the source line (such as source=rtladsb-0:type=rtldsb)
#
# mask_datasource_type=rtladsb
# mask_datasource_type=rtlamr



# Potential datasources can be masked from the list subsystem by interface name; this 
# is primarily for systems which list interface you will never use and you'd like to
# remove them from the list.  It will not actually reduce server load in probing interfaces
# however.
#
# mask_datasource_interface=wlan0



# See the README for more information how to define sources; sources take the
# form of:
# source=interface:options
#
# For example to capture from a Wi-Fi interface in Linux you could specify:
# source=wlan0
#
# or to specify a custom name,
# source=wlan0:name=ath9k
#
# Sources may be defined in the config file or on the command line via the 
# '-c' option.  Sources may also be defined live via the WebUI.
#
# Kismet does not pre-define any sources, permanent sources can be added here
# or in kismet_site.conf
source=$interface_name


# Default behavior of capture sources; if there are no options passed on the source
# definition to control hopping, hop rate, or other attributes, these are applied

# Hop channels if possible
channel_hop=true

# How fast do we hop channels?  Time can be hops/second or hops/minute.
channel_hop_speed=5/sec

# If we have multiple sources with the same type, Kismet can try to split
# them up so that they hop from different starting positions; this maximizes the
# coverage
split_source_hopping=true

# Should Kismet scramble the channel list so that it hops in a semi-random pattern?
# This helps sources like Wi-Fi where many channels are adjacent and can overlap, 
# by randomizing 2.4ghz channels Kismet can take advantage of the overlap.  Typically
# leave this turned on.
randomized_hopping=true

# Should sources be re-opened when they encounter an error?
retry_on_source_error=true


# When faced with extremely large numbers of sources, the host Kismet is running on 
# may have trouble reconfiguring the interfaces simultaneously; typically this shows up
# when 10-20 sources are enabled at once.  Kismet will break these sources into
# groups and configure them by group.

# Number of sources before we trigger staggered startup
source_stagger_threshold=16

# Number of sources to launch as each group
source_launch_group=8

# How long do we delay, in seconds, between opening groups of sources?
source_launch_delay=10

# Should we override remote sources timestamps?  If you do not have NTP coordinating
# the time between your remote capture devices, you may see unusual behavior if the
# system clocks are drastically different.
override_remote_timestamp=true


# GPS configuration
# gps=type:options
#
# Kismet supports multiple types of GPS.  Generally you should only activate one of these
# options at a time.
#
# Only one process can open a serial or USB device at the same time; if you are using GPSD,
# make sure not to configure Kismet on the same serial port.
#
# For more information about the GPS types, see the documentation at:
# https://www.kismetwireless.net/docs/readme/gps/
#
# gps=serial:device=/dev/ttyACM0,name=laptop
# gps=tcp:host=1.2.3.4,port=4352
gps=gpsd:host=localhost,port=2947
# gps=virtual:lat=123.45,lon=45.678,alt=1234
# gps=web:name=gpsweb



# Do we process the contents of data frames?  If this is enabled, data
# frames will be truncated to the headers only immediately after frame type
# detection.  This will disable IP detection, etc, however it is likely
# safer (and definitely more polite) if monitoring networks you do not own.
# hidedata=true



# Do we allow plugins to be used?  This will load plugins from the system
# and user plugin directiories when set to true.
allowplugins=true



# OUI file, generated by tools/create_manuf_db.py
# Mapping of OUI to manufacturer data, generated from the IEEE database
ouifile=%S/kismet/kismet_manuf.txt.gz

# ICAO file, generated by tools/create_icao_db.py
# Mapping of ADSB ICAO registration numbers to flight data, generated from the FAA database
icaofile=%S/kismet/kismet_adsb_icao.txt.gz


# Known WEP keys to decrypt, bssid,hexkey.  This is only for networks where
# the keys are already known, and it may impact throughput on slower hardware.
# Multiple wepkey lines may be used for multiple BSSIDs.
# wepkey=00:DE:AD:C0:DE:00,FEEDFACEDEADBEEF01020304050607080900


# Is transmission of the keys to the client allowed?  This may be a security
# risk for some.  If you disable this, you will not be able to query keys from
# a client.
allowkeytransmit=true

# Where state info, etc, is stored.  You shouldn't ever need to change this.
# This is a directory.
configdir=%h/.kismet/


EOF

mkdir -p "/home/$user/.kismet"
mkdir -p "/home/$user/logs"
chown -R "$user":"$user" "/home/$user/.kismet"
chown -R "$user":"$user" "/home/$user/logs"

cat > "/home/$user/.kismet/kismet_httpd.conf" << EOF
httpd_password=kismet
httpd_username=kismet
EOF

#Services
cat > "/etc/systemd/system/kismet.service" <<EOF
[Unit]
Description=Kismet
After=network.target

[Service]
ExecStart=/usr/bin/kismet
RemainAfterExit=yes
User=$user
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > "/etc/systemd/system/rssi.service" <<EOF
Description=Kismet web rssi bar
After=kismet.service

[Service]
ExecStart=/root/kismet_web_rssi-bar/.venv/bin/python /root/kismet_web_rssi-bar/main.py
RemainAfterExit=yes
User=root
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable kismet
systemctl enable rssi

clear

echo "Instructions:"
sleep 1
echo "Connect device to $ssid"
sleep 1
echo "Open web client"
sleep 1
echo "Go to http://10.42.0.1:2501 for kismet, or http://10.42.0.1:5001 for the rssi bar"
sleep 1
echo "Profit"
sleep 7
reboot