#!/bin/bash
#
# Note: 
#  - The script assumes that there's only one account per computer that has the Company Portal installed.
#  - This script requires access to the Microsoft Graph API, it needs the "User.Read.All" Application permission.
#    * Register the App in Entra ID.
#  	   - Go to Entra ID > App registrations > New registration.
#      - Note down the Application (client) ID and Directory (tenant) ID.
#      - Generate and save the Client Secret.
#      - Under API Permissions, add a Microsoft Graph Application Permission and grant the User.Read.All to the application
#
# Disclaimer:
#  - The script is provided AS IS without warranty of any kind.
#

#----- Variables -------------------------------------------------------------------------------------------------------------------------------------

DOMAIN_NAME="contoso.com"
COMPANY_NAME="Contoso"
TENANT_ID="Directory (tenant) ID"
CLIENT_ID="Application (client) ID"
CLIENT_SECRET="Client secret (Value)"
GRAPH_SCOPE="https://graph.microsoft.com/.default"
SCRIPT_NAME="MacRenamify"
LOG_DIR="/Library/Logs/Microsoft/IntuneScripts/${SCRIPT_NAME}"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
TOKEN_URL="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token"


#----- Script Body -----------------------------------------------------------------------------------------------------------------------------------

# Check if the log directory exists.
if [[ -d "${LOG_DIR}" ]]; then
  echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] Log directory already exists (${LOG_DIR})."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] Log directory not found, creating it (${LOG_DIR})."
  mkdir -p "${LOG_DIR}"
fi

# Start logging.
exec &> >(tee -a "${LOG_FILE}")

# Log header.
echo ""
echo "##############################################################"
echo "# $(date +"%Y-%m-%d %H:%M:%S") | Starting ${SCRIPT_NAME}"
echo "##############################################################"
echo "Writing log output to ${LOG_FILE}"
echo ""

# List the local user accounts and find the aadUserId.
LOCAL_USERS=$(find /Users -maxdepth 1 -type d | cut -d "/" -f3-)
for USERS in ${LOCAL_USERS}
do
  if [[ -f /Users/${USERS}/Library/Application\ Support/com.microsoft.CompanyPortalMac.usercontext.info ]]; then
    AAD_USER=$(grep -i "@${DOMAIN_NAME}" /Users/${USERS}/Library/Application\ Support/com.microsoft.CompanyPortalMac.usercontext.info | sed 's/<[\/]*string>//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    AAD_USER_PREFIX=$(echo ${AAD_USER} | sed 's/@.*//')
    if [[ -z "${AAD_USER}" ]]; then
      echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] No aadUserId detected in Company Portal."
      exit 1
    else
      echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] Detected aadUserId as: ${AAD_USER}"
    fi
  fi
done

# Get OAuth 2.0 Token
ACCESS_TOKEN=$(curl -s \
                    -X POST ${TOKEN_URL} \
                    -H "Content-Type: application/x-www-form-urlencoded" \
                    -d "client_id=${CLIENT_ID}" \
                    -d "scope=${GRAPH_SCOPE}" \
                    -d "client_secret=${CLIENT_SECRET}" \
                    -d "grant_type=client_credentials" | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")

if [[ -z "${ACCESS_TOKEN}" ]]; then
  echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] Unable to retrieve access token for the Microsoft Graph API."
  exit 1
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] Access token retrieved for the Microsoft Graph API."
fi

# Query the Microsoft Graph API for the user department info.
USER_INFO_URL="https://graph.microsoft.com/v1.0/users/${AAD_USER}?\$select=department"

USER_INFO=$(curl -s \
                 -X GET "${USER_INFO_URL}" \
                 -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                 -H "Content-Type: application/json")

USER_DEPARTMENT=$(echo "${USER_INFO}" | python3 -c "import sys, json; print(json.load(sys.stdin)['department'])" | sed 's/[[:space:]]//g')
if [[ "${USER_DEPARTMENT}" = "null" ]]; then
  echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] Department attribute is not set for this user."
  exit 1
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] Department attribute detected as: ${USER_DEPARTMENT}"
fi

# Print an overview of the collected information.
echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] Company Name: ${COMPANY_NAME}"
echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] Department: ${USER_DEPARTMENT}"
echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] AAD Username Prefix: ${AAD_USER_PREFIX}"
NEW_HOSTNAME="${COMPANY_NAME}-${USER_DEPARTMENT}-${AAD_USER_PREFIX}"
echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] New computer hostname: ${NEW_HOSTNAME}"

# Retrieve the current ComputerName.
CURRENT_COMPUTER_NAME=$(scutil --get ComputerName)
if [[ "$?" = "0" ]]; then
  echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] Current ComputerName detected as: ${CURRENT_COMPUTER_NAME}"
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] Failed to retrieve the current ComputerName."
  exit 1
fi

# Set the new ComputerName.
scutil --set ComputerName ${NEW_HOSTNAME}
if [[ "$?" = "0" ]]; then
  echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] ComputerName changed from ${CURRENT_COMPUTER_NAME} to ${NEW_HOSTNAME}."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] Failed to set ComputerName from ${CURRENT_COMPUTER_NAME} to ${NEW_HOSTNAME}."
  exit 1
fi

# Set the new HostName.
scutil --set HostName ${NEW_HOSTNAME}
if [[ "$?" = "0" ]]; then
  echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] HostName changed from ${CURRENT_COMPUTER_NAME} to ${NEW_HOSTNAME}."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] Failed to set HostName from ${CURRENT_COMPUTER_NAME} to ${NEW_HOSTNAME}."
  exit 1
fi

# Set the new LocalHostName.
scutil --set LocalHostName ${NEW_HOSTNAME}
if [[ "$?" = "0" ]]; then
  echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] LocalHostName changed from ${CURRENT_COMPUTER_NAME} to ${NEW_HOSTNAME}."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") [ERROR] Failed to set LocalHostName from ${CURRENT_COMPUTER_NAME} to ${NEW_HOSTNAME}."
  exit 1
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") [INFO] All done, kthxbye!"
