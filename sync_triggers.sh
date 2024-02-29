#!/bin/bash
source ./color.sh
source ./api.sh

if [ -z $t_public_key ]; then
    read -p "Enter target public key: " t_public_key
fi
if [ -z $t_private_key ]; then
    read -p "Enter target private key: " t_private_key
fi

project_id="5d38a6c6cf09a223e0dd9fbb"
app_id="65369ff2d162b72ce3b076cc"

if [ ! -f "functions.json" ] || [ ! -f "triggers.json" ]; then
    echo -e "${RED}Can't find trigger defintion files. Run ./read_triggers.sh first.${NC}"
    exit 1
fi
# Login using public/private key and get access token.
# The token will be used for the rest part of this script.
echo -e "Loging in with public key and private key."
echo '{"username": "'$t_public_key'", "apiKey": "'$t_private_key'"}' > _temp.json
auth_result=`api_post _temp.json 'https://realm.mongodb.com/api/admin/v3.0/auth/providers/mongodb-cloud/login'`
token=`echo -E "$auth_result" | jq -r .access_token`
if [ $token = null ]; then
    echo -e "${RED}Login failed!${NC}"
    echo -e "${RED}$auth_result${NC}"
    exit 1
fi
echo -e "${GREEN}Login OK!${NC}"
auth_header="Authorization: Bearer $token"

funs=`api_get "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/functions?product=atlas"`
if [ $? != 0 ]; then
    echo -e "${RED}Error calling API. Check your project_id or app_id.${NC}"
    exit 1;
elif [ `echo -E "$funs" | jq -r type` != "array" ]; then
    echo -e "${RED}Error getting functions from target cluster.${NC}"
    echo -e "${RED}${funs}${NC}"
    exit 1
fi
cat functions.json | jq -s "." | jq -c ".[]" |
while IFS=$"\n" read -r fun; do
    name=`echo -E "$fun" | jq -r ".name"`
    tfun=`echo -E "$funs" | jq '.[] | select(.name == "'$name'")'`
    echo -E "$fun" | jq -c "del(._id) | del(.last_modified) | . += {run_as_system: false}" > _temp.json
    if [ "$tfun" = "" ]; then
        echo -e "Function ${YELLOW}$name${NC} not found. Creating new..."
        result=`api_post _temp.json "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/functions"`
        if [ $? != 0 ]; then
            echo -e "${RED}Error calling API. Check your project_id or app_id.${NC}"
            exit 1;
        elif [ `echo -E "$result" | jq -r "._id"` = "null" ]; then
            echo -e "${RED}Error creating funtion.${NC}"
            echo -e "${RED}$result${NC}"
            exit 1
        fi
        echo -e -n "${GREEN}Function created: ${NC}"
        echo -E "$result" | jq -c 
    else
        echo -e "Function ${YELLOW}$name${NC} exits. Updating..."
        fid=`echo -E "$tfun" | jq -r "._id"`
        result=`api_put _temp.json "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/functions/${fid}"`

        if [ $? != 0 ]; then
            echo -e "${RED}Error calling API. Check your project_id or app_id.${NC}"
            exit 1;
        elif [ ! $result = "" ]; then
            echo -e "${RED}Error updating funtion.${NC}"
            echo -e "${RED}$result${NC}"
            exit 1
        fi
        echo -e -n "${GREEN}Function updated: ${NC}"
        echo -E "$tfun" | jq -c 
    fi
done
if [ $? != 0 ]; then exit 1; fi

echo -e "${GREEN}All functions synced.${NC}"
echo "Syncing trigger settings"
# Read service name from values
vid=`api_get "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/values?product=atlas" | jq -r '.[] | select(.name == "ServiceName") | ._id'`
val=`api_get "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/values/${vid}?product=atlas" | jq -r .value`
if [ $? != 0 ]; then
    echo -e "${RED}Error calling API. Check your project_id or app_id.${NC}"
    exit 1;
elif [ "$val" = "" ]; then
    echo -e "${RED}Error getting ServiceName. Is it defined?${NC}"
    echo -e "${RED}$result${NC}"
    exit 1
fi
echo -e "Found value: ${GREEN}ServiceName=$val${NC}"
sid=`api_get "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/services?product=atlas" | jq -r '.[] | select(.name == "'$val'") | ._id'`
svc=`api_get "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/services/$sid/config?product=atlas"`
if [ $? != 0 ]; then
    echo -e "${RED}Error calling API. Check your project_id or app_id.${NC}"
    exit 1;
elif [ "$svc" = "" ]; then
    echo -e "${RED}Error getting service by name: $val${NC}"
    echo -e "${RED}$result${NC}"
    exit 1
fi
cluster=`echo -E "$svc" | jq -r ".clusterName"`
echo -e "Found service: ${GREEN}$val${NC}"
echo -e "Found linked cluster ${GREEN}$cluster${NC}"
funs=`api_get "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/functions?product=atlas"`
cat triggers.json | jq -c ".[]" |
while IFS=$"\n" read -r trigger; do
    t_name=`echo -E "$trigger" | jq -r ".name"`
    t_id=`echo -E "$trigger" | jq -r "._id"`
    f_name=`echo -E "$trigger" | jq -r ".function_name"`
    f_id=`echo -E "$funs" | jq -r '.[] | select(.name == "'$f_name'") | ._id'`
    trigger=`echo -E "$trigger" | jq '.config.clusterName = "'$cluster'" | .config.service_id = "'$sid'" | .function_id = "'$f_id'" | .event_processors.FUNCTION.config.function_id = "'$f_id'"'`

    echo -E "$trigger" > _temp.json
    result=`api_put _temp.json "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/triggers/${t_id}" | jq ".error"`
    if [ "$result" != "" ]; then
        # Doesn't exist. Create new.
        result=`api_post _temp.json "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/triggers"`
        if [ `echo -E "$result" | jq -r "._id"` != "" ]; then
            echo -e "Trigger created: ${GREEN}$t_name${NC}"
        else
            echo -e "Trigger create failed: ${RED}$result${NC}"
        fi
    else
        echo -e "Trigger updated: ${GREEN}$t_name${NC}"
    fi
done
if [ $? != 0 ]; then exit 1; fi
echo -e "${GREEN}All triggers are synced.${NC}"

echo -e "${GREEN}Remove unused triggers.${NC}"
triggers=`api_get "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/triggers?product=atlas"`
echo -E "$triggers" | jq -c ".[]" |
while IFS=$"\n" read -r fun; do
    tid=`echo -E "$fun" | jq -r ._id`
    tname=`echo -E "$fun" | jq -r .name`
    fid=`echo -E "$fun" | jq -r .function_id`
    fname=`echo -E "$fun" | jq -r .function_name`
    echo -e "Checking if ${GREEN}$tname${NC} is removed"
    ttid=`cat triggers.json | jq -c -r '.[] | select(._id == "'$tid'") | ._id'`
    if [ -z $ttid ]; then
        # Trigger is removed in source cluster. Remove the trigger and its function
        echo -e "${YELLOW}Trigger is removed in source cluster. Removing the trigger...${NC}"
        result=`api_delete "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/triggers/${tid}"`
        if [ $? != 0 ]; then
            echo -e "${RED}Error calling API. Check your project_id or app_id.${NC}"
            exit 1;
        elif [ ! "$result" = "{}" ]; then
            echo -e "${RED}Error deleting trigger.${NC}"
            echo $result
            exit 1;
        fi
        result=`api_delete "https://realm.mongodb.com/api/admin/v3.0/groups/${project_id}/apps/${app_id}/functions/${fid}"`
        if [ $? != 0 ]; then
            echo -e "${RED}Error calling API. Check your project_id or app_id.${NC}"
            exit 1;
        elif [ ! "$result" = "{}" ]; then
            echo -e "${RED}Error deleting trigger function.${NC}"
            echo $result
            exit 1;
        fi
        echo -e "${RED}Trigger ${tname} deleted.${NC}"
    else
        echo -e "${GREEN}Keep trigger $tname.${NC}"
    fi
done

# cleanup
rm -f _temp.json