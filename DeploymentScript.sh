#!/bin/bash

## Variables
INSTALL_LOG="/tmp/v1es_install.log"

# POLICY_ID, GROUP_ID and RELAY_GROUP_ID are for SWP configuration
POLICY_ID=75 # 0 means no specific choice
GROUP_ID=0 # 0 means no specific choice
RELAY_GROUP_ID=0 # 0 means no specific choice

## Pre-Check
# Check whether /tmp is writable
if [[ ! -w /tmp ]]; then
    echo "[ERROR] /tmp is not writable. Please check the permission of /tmp."
    exit 1
fi

# Check whether the script is running as root
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "[ERROR] You are not running as the root user.  Please try again with root privileges."
    echo "$(date) [ERROR] You are not running as the root user.  Please try again with root privileges." >> $INSTALL_LOG
    exit 1
fi

# Check whether curl is installed
if ! type curl >/dev/null 2>&1; then
    echo "[ERROR] Please install curl before running this script."
    echo "$(date) [ERROR] Please install curl before running this script." >> $INSTALL_LOG
    exit 1
fi

# Check whether curl supports tls v1.2
CURL_TLS_VERSION=$(curl --help tls | grep tlsv1.2)
if [[ -z "$CURL_TLS_VERSION" ]]; then
    echo "[ERROR] Your version of curl does not support TLS v1.2. Please update curl."
    echo "$(date) [ERROR] Your version of curl does not support TLS v1.2. Please update curl." >> $INSTALL_LOG
    exit 1
fi
echo "[INFO] curl support tls v1.2."
echo "$(date) [INFO] curl support tls v1.2." >> $INSTALL_LOG

# Check whether tar is installed
if ! type tar >/dev/null 2>&1; then
    echo "[ERROR] Please install tar before running this script."
    echo "$(date) [ERROR] Please install tar before running this script." >> $INSTALL_LOG
    exit 1
fi

# check if base64 method exists
if ! type base64 >/dev/null 2>&1; then
    echo "[ERROR] Please install base64 before running this script."
    echo "$(date) [ERROR] Please install base64 before running this script." >> $INSTALL_LOG
    exit 1
fi

echo "[INFO] Start deploying."
echo "$(date) [INFO] Start deploying." >> $INSTALL_LOG

# PROXY_ADDR_PORT and PROXY_CREDENTIAL define proxy for software download and Agent activation
PROXY_ADDR_PORT="" 
PROXY_USERNAME=""
PROXY_PASSWORD=""

# HTTP_PROXY is exported for compatibility purpose, remove it if it is not needed in your environment
PROXY_CREDENTIAL=""
if [[ ! -z $PROXY_PASSWORD ]]; then
    PROXY_CREDENTIAL=$(eval echo \"$PROXY_USERNAME:$PROXY_PASSWORD\")
elif [[ ! -z $PROXY_USERNAME ]]; then
    PROXY_CREDENTIAL=$(eval echo "$PROXY_USERNAME")
fi

if [[ ! -z $PROXY_CREDENTIAL ]]; then
    export HTTP_PROXY=http://$PROXY_CREDENTIAL@$PROXY_ADDR_PORT/
    export HTTPS_PROXY=http://$PROXY_CREDENTIAL@$PROXY_ADDR_PORT/
    echo "[INFO] Use proxy with credentials."
    echo "$(date) [INFO] Use proxy with credentials." >> $INSTALL_LOG
elif [[ ! -z $PROXY_ADDR_PORT ]]; then
    export HTTP_PROXY=http://$PROXY_ADDR_PORT/
    export HTTPS_PROXY=http://$PROXY_ADDR_PORT/
    echo "[INFO] Use proxy without credentials."
    echo "$(date) [INFO] Use proxy without credentials." >> $INSTALL_LOG
fi

# configure connection methods
CONNECT_CONFIG=$(eval echo -n '{\"fps\":[{\"connections\": [{\"type\": \"DIRECT_CONNECT\"}]}]}' | base64 -w 0)
if [[ $PROXY_ADDR_PORT ]]; then
    PROXY_CONFIG=$(echo "$PROXY_ADDR_PORT")
    if [[ $PROXY_USERNAME ]]; then
        CREDENTIAL_ENCODE=$(eval echo -n \"$PROXY_USERNAME:\" | base64 -w 0)
        PROXY_CONFIG=$(echo "$CREDENTIAL_ENCODE@$PROXY_ADDR_PORT")
        if [[ $PROXY_PASSWORD ]]; then
            CREDENTIAL_ENCODE=$(eval echo -n \"$PROXY_USERNAME:$PROXY_PASSWORD\" | base64 -w 0)
            PROXY_CONFIG=$(echo "$CREDENTIAL_ENCODE@$PROXY_ADDR_PORT")
        fi
    fi
    CONNECT_CONFIG=$(eval echo -n '{\"fps\":[{\"connections\": [{\"type\": \"USER_INPUT\"}]}]}' | base64 -w 0)
fi

# Platform detection
isRPM=""
linuxPlatform=""
archType=""
CURLOPTIONS="--silent --tlsv1.2"
CUSTOMER_ID="d8fb390a-7550-4ffd-80c8-b3c2cd1dd8d6"
XBC_FQDN="api-eu1.xbc.trendmicro.com"


# Detect Linux platform
platform='';  # platform for requesting package
runningPlatform='';   # platform of the running machine
majorVersion='';
platform_detect() {
 isRPM=1
 if !(type lsb_release &>/dev/null); then
    distribution=$(cat /etc/*-release | grep '^NAME' );
    release=$(cat /etc/*-release | grep '^VERSION_ID');
 else
    distribution=$(lsb_release -i | grep 'ID' | grep -v 'n/a');
    release=$(lsb_release -r | grep 'Release' | grep -v 'n/a');
 fi;
 if [ -z "$distribution" ]; then
    distribution=$(cat /etc/*-release);
    release=$(cat /etc/*-release);
 fi;

 releaseVersion=${release//[!0-9.]};
 case $distribution in
     *"Debian"*)
        platform='Debian_'; isRPM=0; runningPlatform=$platform;
        if [[ $releaseVersion =~ ^10.* ]]; then
           majorVersion='10';
        elif [[ $releaseVersion =~ ^11.* ]]; then
           majorVersion='11';
        elif [[ $releaseVersion =~ ^12.* ]]; then
           majorVersion='12';
        fi;
        ;;

     *"Ubuntu"*)
        platform='Ubuntu_'; isRPM=0; runningPlatform=$platform;
        if [[ $releaseVersion =~ ([0-9]+)\.(.*) ]]; then
           majorVersion="${BASH_REMATCH[1]}.04";
        fi;
        ;;

     *"SUSE"* | *"SLES"*)
        platform='SuSE_'; runningPlatform=$platform;
        if [[ $releaseVersion =~ ^12.* ]]; then
           majorVersion='12';
        elif [[ $releaseVersion =~ ^15.* ]]; then
           majorVersion='15';
        fi;
        ;;

     *"Oracle"* | *"EnterpriseEnterpriseServer"*)
        platform='Oracle_OL'; runningPlatform=$platform;
        if [[ $releaseVersion =~ ^7.* ]]; then
           majorVersion='7';
        elif [[ $releaseVersion =~ ^8.* ]]; then
           majorVersion='8';
        elif [[ $releaseVersion =~ ^9.* ]]; then
           majorVersion='9';
        fi;
        ;;

     *"CentOS"*)
        platform='RedHat_EL'; runningPlatform='CentOS_';
        if [[ $releaseVersion =~ ^6.* ]]; then
           majorVersion='6';
        elif [[ $releaseVersion =~ ^7.* ]]; then
           majorVersion='7';
        elif [[ $releaseVersion =~ ^8.* ]]; then
           majorVersion='8';
        fi;
        ;;

     *"AlmaLinux"*)
        platform='RedHat_EL'; runningPlatform='AlmaLinux_';
        if [[ $releaseVersion =~ ^8.* ]]; then
           majorVersion='8';
        elif [[ $releaseVersion =~ ^9.* ]]; then
           majorVersion='9';
        fi;
        ;;

     *"Rocky"*)
        platform='RedHat_EL'; runningPlatform='Rocky_';
        if [[ $releaseVersion =~ ^8.* ]]; then
           majorVersion='8';
        elif [[ $releaseVersion =~ ^9.* ]]; then
           majorVersion='9';
        fi;
        ;;

     *"MIRACLE"*)
        platform='RedHat_EL'; runningPlatform='Miracle_';
        if [[ $releaseVersion =~ ^8.* ]]; then
           majorVersion='8';
        elif [[ $releaseVersion =~ ^9.* ]]; then
           majorVersion='9';
        fi;
        ;;

     *"CloudLinux"*)
        platform='CloudLinux_'; runningPlatform=$platform;
        if [[ $releaseVersion =~ ^8.* ]]; then
           majorVersion='8';
        fi;
        ;;

     *"Amazon"*)
        platform='amzn'; runningPlatform=$platform;
        if [[ $(uname -r) == *"amzn2023"* ]]; then
           majorVersion='2023';
        elif [[ $(uname -r) == *"amzn2"* ]]; then
           majorVersion='2';
        fi;
        ;;

     *"RedHat"* | *"Red Hat"*)
        platform='RedHat_EL'; runningPlatform=$platform;
        if [[ $releaseVersion =~ ^6.* ]]; then
           majorVersion='6';
        elif [[ $releaseVersion =~ ^7.* ]]; then
           if [[ ${distribution} == *"Workstation"* ]]; then
              runningPlatform='RedHatWorkstation_';
           fi;
           majorVersion='7';
        elif [[ $releaseVersion =~ ^8.* ]]; then
           majorVersion='8';
        elif [[ $releaseVersion =~ ^9.* ]]; then
           majorVersion='9';
         elif [[ $releaseVersion =~ ^10.* ]]; then
           majorVersion='10';
        fi;
        ;;

 esac

 if [[ -z "${platform}" ]] || [[ -z "${majorVersion}" ]]; then
    detectError="Unsupported platform is detected."
    linuxPlatform = "";
 else
    archType='i386'; architecture=$(arch);
    if [[ ${architecture} == *"x86_64"* ]]; then
       archType='x86_64';
    elif [[ ${architecture} == *"aarch64"* ]]; then
       archType='aarch64';
    fi

    linuxPlatform="${platform}${majorVersion}/${archType}/";

    if [[ ${archType} == 'i386' ]]; then
       detectError="Unsupported architecture is detected."
       linuxPlatform = "";
    fi
 fi
}


platform_detect
if [[ -z "${linuxPlatform}" ]] || [[ -z "${isRPM}" ]]; then
    echo "[ERROR] ${detectError}"
    echo "$(date) [ERROR] ${detectError}." >> $INSTALL_LOG
    exit 1
fi

## Get Installer Package
INSTALLER_PATH="/tmp/v1es_installer.tgz"

# Get XBC installer
GET_INSTALLER_URL="https://$XBC_FQDN/apk/installer"
HTTP_BODY=""

if [[ ${archType} == "x86_64" ]]; then
    HTTP_BODY='{"company_id":"d8fb390a-7550-4ffd-80c8-b3c2cd1dd8d6","platform":"linux64","scenario_ids":["920eff7b-3576-4138-9176-d976090474b1","94ed0c80-2970-4be7-95dd-a3d84c7fa359"]}'
elif [[ ${archType} == "aarch64" ]]; then
    HTTP_BODY='{"company_id":"d8fb390a-7550-4ffd-80c8-b3c2cd1dd8d6","platform":"linuxaarch64","scenario_ids":["338d9daa-42a8-4633-8dfc-f8d51a041503","ef2f0742-df68-453d-9d0b-32c203d1f0f5"]}'
else
    echo "[ERROR] Architecture type ${archType} is not in the supported architecture list."
    echo "$(date) [ERROR] Architecture type ${archType} is not in the supported architecture list." >> $INSTALL_LOG
    exit 1
fi

echo "[INFO] Start downloading the installer."
echo "$(date) [INFO] Start downloading the installer." >> $INSTALL_LOG
CURLOUT=$(eval curl -w "%{http_code}" -L -H \"Content-Type: application/json\" -H \"X-Customer-Id: $CUSTOMER_ID\" -d \'$HTTP_BODY\' -o $INSTALLER_PATH $CURLOPTIONS $GET_INSTALLER_URL;)
err=$?
if [[ $CURLOUT -ge 400 || $err -ne 0 ]]; then
    echo "[ERROR] Failed to download the installer. Curl error: $err, HTTP error: $CURLOUT."
    echo "$(date) [ERROR] Failed to download the installer. Curl error: $err, HTTP error: $CURLOUT." >> $INSTALL_LOG
    exit 1
fi
echo "[INFO] The installer downloaded."
echo "$(date) [INFO] The installer downloaded." >> $INSTALL_LOG
TAR_ARGS="-zxvf"

## Install v1es agents
EXTRATED_DIR="/tmp/v1es"
mkdir -p $EXTRATED_DIR && tar $TAR_ARGS $INSTALLER_PATH -C $EXTRATED_DIR
err=$?
if [[ $err -ne 0 ]]; then
    echo "[ERROR] Fail to extract the agent installer / full package. Error: $err."
    echo "$(date) [ERROR] Fail to extract the agent installer / full package. Error: $err." >> $INSTALL_LOG
    exit 1
fi

# set xbc site and scenario IDs
XBC_ENV="prod-eu1"
if [[ ${archType} == "x86_64" ]]; then
    PROPERTY=$(eval echo '{\"xbc_env\": \"$XBC_ENV\", \"xbc_agent_token\": "\"920eff7b-3576-4138-9176-d976090474b1|94ed0c80-2970-4be7-95dd-a3d84c7fa359\"", \"full_package\": true}')
elif [[ ${archType} == "aarch64" ]]; then
    PROPERTY=$(eval echo '{\"xbc_env\": \"$XBC_ENV\", \"xbc_agent_token\": "\"338d9daa-42a8-4633-8dfc-f8d51a041503|ef2f0742-df68-453d-9d0b-32c203d1f0f5\"", \"full_package\": true}')
fi
echo $PROPERTY > $EXTRATED_DIR/.property

echo "[INFO] Start agent installation"
echo "$(date) [INFO] Start agent installation" >> $INSTALL_LOG

## Check openssl version
REQUIRED_OPENSSL_VERSION="1.0.2"
CURRENT_OPENSSL_VERSION=$(openssl version | cut -d' ' -f2)
version_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "\$1"; }

if ! version_gt $CURRENT_OPENSSL_VERSION $REQUIRED_OPENSSL_VERSION; then
    echo "[ERROR] The openssl version is lower than the required version $REQUIRED_OPENSSL_VERSION."
    echo "$(date) [ERROR] The openssl version is lower than the required version $REQUIRED_OPENSSL_VERSION." >> $INSTALL_LOG
    exit 1
fi

## Validate the installer
cd $EXTRATED_DIR
openssl cms -verify -binary -in checksum.p7 -inform DER -verify -content checksum -purpose any -certsout need_to_check.certs -out /dev/null
if [[ $? -ne 0 ]]; then
    echo "[ERROR] Failed to validate the checksum file. Error: $?"
    echo "$(date) [ERROR] Failed to validate the checksum file. Error: $?" >> $INSTALL_LOG
    exit 1
fi

sha256sum -c checksum
if [[ $? -ne 0 ]]; then
    echo "[ERROR] Failed to validate the agent installer with checksum. Error: $?"
    echo "$(date) [ERROR] Failed to validate the agent installer with checksum. Error: $?" >> $INSTALL_LOG
    exit 1
fi

echo "[INFO] Agent is installing..."
echo "$(date) [INFO] Agent is installing..." >> $INSTALL_LOG

if [[ $PROXY_CONFIG ]]; then
    echo "[INFO] The agent installation is using a proxy."
    echo "$(date) [INFO] The agent installation is using a proxy." >> $INSTALL_LOG
    INSTALL_RESULT=$(eval $EXTRATED_DIR/tmxbc install --proxiesWithCred \'$PROXY_CONFIG\' --connection \'$CONNECT_CONFIG\')
else
    echo "[INFO] The agent installation is using a direct connection."
    echo "$(date) [INFO] The agent installation is using a direct connection." >> $INSTALL_LOG
    INSTALL_RESULT=$(eval $EXTRATED_DIR/tmxbc install --connection \'$CONNECT_CONFIG\')
fi

# check if XBC is installed as usual
if [[ $? -ne 0 ]]; then
    echo "[ERROR] Failed to install agent. Error: $INSTALL_RESULT."
    echo "$(date) [ERROR] Failed to install agent. Error: $INSTALL_RESULT." >> $INSTALL_LOG
    exit 1
fi
echo "[INFO] Agent is installed."
echo "$(date) [INFO] Agent is installed." >> $INSTALL_LOG

# check if XBC is registered
IDENTITY_FILE_PATH="/opt/TrendMicro/EndpointBasecamp/etc/.identity"
retryCount=0
maxRetryCount=30
while [[ ! -a $IDENTITY_FILE_PATH ]]; do
    echo "[INFO] Waiting for agent to register."
    echo "$(date) [INFO] Waiting for agent to register." >> $INSTALL_LOG
    sleep 10
    retryCount=$((retryCount + 1))
    if [[ $retryCount -gt maxRetryCount ]]; then
        echo "[ERROR] Failed to register agent to the backend service. Please see the tmxbc.log for more details."
        echo "$(date) [ERROR] Failed to register agent to the backend service. Please see the tmxbc.log for more details." >> $INSTALL_LOG
        exit 1
    fi
done
echo "[INFO] Agent is registered."
echo "$(date) [INFO] Agent is registered." >> $INSTALL_LOG

## SWP installation prerequisites
STATUS_CMD="systemctl status ds_agent"
if ! type systemctl >/dev/null 2>&1; then
    STATUS_CMD="service ds_agent status"
fi

## Check SWP is installed and running
STATUS=$($STATUS_CMD | grep "running")
retryCount=0
maxRetryCount=60
while [[ -z "$STATUS" ]]; do
    echo "[INFO] Waiting for Server & Workload Protection to install."
    echo "$(date) [INFO] Waiting for Server & Workload Protection to install." >> $INSTALL_LOG
    sleep 10
    retryCount=$((retryCount + 1))
    if [[ $retryCount -gt maxRetryCount ]]; then
        STATUS=$($STATUS_CMD)
        echo "[ERROR] Failed to install Server & Workload Protection. Error: $STATUS"
        echo "$(date) [ERROR] Failed to install Server & Workload Protection. Error: $STATUS" >> $INSTALL_LOG
        exit 1
    fi
    STATUS=$($STATUS_CMD | grep "running")
done
echo "[INFO] Server & Workload Protection is installed."
echo "$(date) [INFO] Server & Workload Protection is installed." >> $INSTALL_LOG

## Check SWP is activated
retryCount=0
maxRetryCount=30
DEPLOY_LOG_PATH="/tmp/.dsa-deploy/dsa-deploy.log"
CONFIG=""
LOG_CONTENT=""

while [[ -z "$CONFIG" || -z "$LOG_CONTENT" ]]; do
    echo "[INFO] Waiting for Server & Workload Protection to activate."
    echo "$(date) [INFO] Waiting for Server & Workload Protection to activate." >> $INSTALL_LOG
    sleep 10
    retryCount=$((retryCount + 1))
    if [[ $retryCount -gt maxRetryCount ]]; then
        echo "[ERROR] Failed to activate Server & Workload Protection. Error: $CONFIG. Please see ds_agent.log for more details."
        echo "$(date) [ERROR] Failed to activate Server & Workload Protection. Error: $CONFIG. Please see ds_agent.log for more details." >> $INSTALL_LOG
        exit 1
    fi
    CONFIG=$(/opt/ds_agent/sendCommand --get GetConfiguration | grep -i dsmUrl)
    if [[ -f $DEPLOY_LOG_PATH ]]; then
        LOG_CONTENT=$(cat $DEPLOY_LOG_PATH | grep "Command session completed.")
    fi
done
echo "[INFO] Server & Workload Protection is activated."
echo "$(date) [INFO] Server & Workload Protection is activated." >> $INSTALL_LOG
sleep 10

## Set SWP configuration
HB_RESULT=$(eval /opt/ds_agent/dsa_control -m "policyid:$POLICY_ID" "relaygroupid:$RELAY_GROUP_ID" "groupid:$GROUP_ID")
STATUS=$(eval echo $HB_RESULT | grep 200)
if [[ -z $STATUS ]]; then
    echo "[ERROR] Failed to set Server & Workload Protection configuration. Error: $HB_RESULT"
    echo "$(date) [ERROR] Failed to set Server & Workload Protection configuration. Error: $HB_RESULT" >> $INSTALL_LOG
    exit 1
fi
echo "[INFO] Server & Workload Protection configuration is set."
echo "$(date) [INFO] Server & Workload Protection configuration is set." >> $INSTALL_LOG

echo "[INFO] Finish deploying."
echo "$(date) [INFO] Finish deploying." >> $INSTALL_LOG
exit 0
