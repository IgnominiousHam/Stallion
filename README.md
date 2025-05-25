# 🐎 The Stallion

This project configures a Raspberry Pi for use as a mobile Wi-Fi direction-finding (DF) device. It leverages:

- 🧭 [Kismet](https://www.kismetwireless.net/) – a powerful wireless network detector and sniffer
- 📶 [kismet_web_rssi-bar](https://github.com/GrokkedBandwidth/kismet_web_rssi-bar) – an awesome web-based RSSI bar display

## ⚙️ Features

- ✅ Plug-and-play setup using a prebuilt image and setup script
- 🤗 Pi-hosted access point for simple configuration
- 📡 Real-time signal strength display via a web interface  
- 🚶 Ideal for security research, Wi-Fi mapping, and device tracking on the go

## 🧰 Hardware Requirements

- 🍓 Raspberry Pi (recommended: Pi 4 or Pi 3B+)
- 📳 USB Wi-Fi adapter (monitor mode capable)
- 🔋 Portable power supply
- 🖥️ Phone or laptop to connect to the access point

## 🛠️ Installation

### Option 1. 💾 Flash the Image

Download the prebuilt image in releases and flash it to an SD card. Boot the pi with the NIC attached and connect your phone to the access point with the following credentials:

**SSID:** stallion

**Password:** :meganthee:

Using a web client, navigate to the following:

**Kismet (for real-time survey):** http://10.42.0.1:2501

 - Kismet User: kismet

 - Kismet Password: kismet

**Web RSSI Bar (for DF-ing a device):** http://10.42.0.1:5001

### Option 2. 🚀 Setup Script

Tested on Raspberry Pi OS lite.

```bash
git clone https://github.com/IgnominiousHam/Stallion/
cd Stallion
chmod +x stallion_setup.sh
sudo ./stallion_setup.sh
```

Again, 

 - Kismet User: kismet

 - Kismet Password: kismet

## 🧪 Customization

To modify access point credentials, use:

```bash
sudo nmtui
```

Then navigate to the hotspot connection. 

Your standard USB Glonass GPS should work out of the box, but if you need to make changes, adjust the /etc/default/gpsd file.

## 👌 Logging

Kismet logs are stored in your non-root user's home directory.

To configure logging preferences, head over to /etc/kismet/kismet_logging.conf

