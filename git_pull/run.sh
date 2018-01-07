#!/bin/bash
set -e

CONFIG_PATH=/data/options.json

DEPLOYMENT_KEY=$(jq --raw-output ".deployment_key[]" $CONFIG_PATH)
DEPLOYMENT_KEY_PROTOCOL=$(jq --raw-output ".deployment_key_protocol" $CONFIG_PATH)
REPOSITORY=$(jq --raw-output '.repository' $CONFIG_PATH)
AUTO_RESTART=$(jq --raw-output '.auto_restart' $CONFIG_PATH)
REPEAT_ACTIVE=$(jq --raw-output '.repeat.active' $CONFIG_PATH)
REPEAT_INTERVAL=$(jq --raw-output '.repeat.interval' $CONFIG_PATH)

# prepare ssh access, if the deployment key has been provided
if [ ! -z "$DEPLOYMENT_KEY" ]; then

    mkdir -p ~/.ssh
    echo "[Info] disable StrictHostKeyChecking for ssh"
    echo "Host *" > ~/.ssh/config
    echo "    StrictHostKeyChecking no" >> ~/.ssh/config

    echo "[Info] setup deployment_key on id_${DEPLOYMENT_KEY_PROTOCOL}"
    while read -r line; do
        echo "$line" >> "${HOME}/.ssh/id_${DEPLOYMENT_KEY_PROTOCOL}"
    done <<< "$DEPLOYMENT_KEY"

    chmod 600 "${HOME}/.ssh/id_${DEPLOYMENT_KEY_PROTOCOL}"
fi


# init config repositorie
if [ ! -d /config/.git ]; then
    echo "[Info] cleanup config folder and clone from repositorie"
    rm -rf /config/.[!.]* /config/* > /dev/null 2>&1

    if ! git clone "$REPOSITORY" /config > /dev/null 2>&1; then
        echo "[Error] can't clone $REPOSITORY into /config"
        exit 1
    fi
fi

# Main programm
cd /config
while true; do

    # get actual commit id
    OLD_COMMIT=$(git rev-parse HEAD)
    
    # perform pull
    echo "[Info] pull from $REPOSITORY"
    git pull > /dev/null 2>&1 || true
    
    # get actual (new) commit id
    NEW_COMMIT=$(git rev-parse HEAD)

    # autorestart of homeassistant if enabled
    if [ "$AUTO_RESTART" == "true" ]; then

        # Compare commit ids & check config
        if [ "$NEW_COMMIT" != "$OLD_COMMIT" ]; then
            echo "[Info] check Home-Assistant config"
            if api_ret="$(curl -s -X POST http://hassio/homeassistant/check)"; then
                result="$(echo "$api_ret" | jq --raw-output ".result")"

                # Config is valid
                if [ "$result" != "error" ]; then
                    echo "[Info] restart Home-Assistant"
                    curl -s -X POST http://hassio/homeassistant/restart > /dev/null 2>&1 || true
                else
                    echo "[Error] invalid config!"
                fi
            fi
        else
            echo "[Info] Nothing has changed."
        fi
    fi

    # do we repeat?
    if [ -z "$REPEAT_ACTIVE" ]; then
        exit 0
    fi
    sleep "$REPEAT_INTERVAL"
done
